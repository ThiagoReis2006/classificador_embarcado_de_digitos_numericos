// =============================================================================
// Acelerador de inferência para rede neural ELM (Extreme Learning
// Machine) com arquitetura de duas camadas:
//   Camada oculta : 784 entradas → 128 neurônios com ativação sigmoid PWL
//   Camada saída  : 128 entradas → 10 classes 
//
// Interface de escrita (externa, fora da inferência):
//   img_we / w_in_we / b_we / beta_we — carregam dados nas RAMs via barramento
//   externo. Qualquer escrita durante busy levanta error.
//
// Controle de inferência:
//   start  — pulso alto inicia nova inferência (também reinicia em S_DONE)
//   rst    — reset síncrono global
//   clear_status — limpa done/error quando não está busy
// =============================================================================
module elm_accel (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        clear_status,

	 // --- interface de escrita da imagem (784 pixels, 8b cada) ---
    input  wire        img_we,
    input  wire [9:0]  img_addr,
    input  wire [7:0]  img_wdata,
	 
	 // --- interface de escrita dos pesos W (784×128 = 100352 entradas, 16b) ---
    input  wire        w_in_we,
    input  wire [16:0] w_in_addr_ext,
    input  wire [15:0] w_in_wdata,

	 // --- interface de escrita dos bias da camada oculta (128 entradas, 16b) ---
    input  wire        b_we,
    input  wire [6:0]  b_addr_ext,
    input  wire [15:0] b_wdata,
	 
	 // --- interface de escrita dos pesos de saída beta (128×10 = 1280, 16b) ---
    input  wire        beta_we,
    input  wire [10:0] beta_addr_ext,
    input  wire [15:0] beta_wdata,

    output reg         busy,
    output reg         done,
    output reg         error,
    output reg  [3:0]  pred,
    output reg  [31:0] cycles
);

    localparam integer IMG_SIZE    = 784;
    localparam integer HIDDEN_SIZE = 128;
    localparam integer OUT_SIZE    = 10;

    localparam [4:0]
        S_IDLE          = 5'd0,
        S_LOAD_BIAS_REQ = 5'd1,
        S_LOAD_BIAS_W1  = 5'd2,
        S_LOAD_BIAS_W2  = 5'd3,
        S_LOAD_BIAS_W3  = 5'd4,
        S_LOAD_BIAS_W4  = 5'd5,
        S_HID_REQ       = 5'd6,
        S_HID_W1        = 5'd7,
        S_HID_W2        = 5'd8,
        S_HID_W3        = 5'd9,
        S_HID_W4        = 5'd10,
        S_HID_ACC       = 5'd11,
        S_ACTIVATION    = 5'd12,
        S_OUT_INIT      = 5'd13,
        S_BETA_REQ      = 5'd14,
        S_BETA_W1       = 5'd15,
        S_BETA_W2       = 5'd16,
        S_BETA_W3       = 5'd17,
        S_BETA_W4       = 5'd18,
        S_OUT_ACC       = 5'd19,
        S_ARGMAX_INIT   = 5'd20,
        S_ARGMAX_STEP   = 5'd21,
        S_DONE          = 5'd22,
        S_ERROR         = 5'd23;

    reg [4:0] state;
	 
// Contadores de iteração
    reg [9:0] pix_idx;
    reg [6:0] hid_idx;
    reg [3:0] out_idx;
// Registradores de acumulação (ponto fixo Q4.12, 32 bits)
    reg signed [31:0] acc_hidden;
    reg signed [31:0] acc_out;
// Buffers internos de ativações e logits
    reg signed [15:0] hidden_vec [0:HIDDEN_SIZE-1];
    reg signed [31:0] logits [0:OUT_SIZE-1];
// Registradores do argmax
    reg signed [31:0] best_score;
    reg        [3:0]  best_class;
// Sinais de endereço e controle das RAMs
    reg  [16:0] w_in_addr;
    reg   [6:0] b_addr;
    reg  [10:0] beta_addr;

    reg         w_in_rden;
    reg         b_rden;
    reg         beta_rden;

    wire [15:0] w_in_q;
    wire [15:0] b_q;
    wire [15:0] beta_q;
// Sinais internos de controle da img_ram (leitura pela FSM)
    reg  [9:0] img_addr_ram;
    reg  [7:0] img_wdata_ram;
    reg        img_wren_ram;
    reg        img_rden_ram;
    wire [7:0] img_q_ram;
 // Conversões de tipo (as RAMs retornam unsigned; o datapath usa signed)
    wire signed [15:0] img_x_q412;
    wire signed [15:0] w_in_s;
    wire signed [15:0] b_s;
    wire signed [15:0] beta_s;
// Operandos e resultado do multiplicador MAC
    reg  signed [15:0] mac_a;
    reg  signed [15:0] mac_b;
    wire signed [31:0] mac_prod_q412;
 // Saída combinacional do sigmoid (conectada direto a acc_hidden)
    wire signed [15:0] hidden_act_q412;

    integer i;
// Funções de cálculo de endereço (evitam multiplicações no RTL)
    function [16:0] calc_w_in_addr;
        input [6:0] h;
        input [9:0] p;
        reg [31:0] tmp;
        begin
            tmp = (h * IMG_SIZE) + p;
            calc_w_in_addr = tmp[16:0];
        end
    endfunction

    function [10:0] calc_beta_addr;
        input [3:0] o;
        input [6:0] h;
        reg [31:0] tmp;
        begin
            tmp = (h * OUT_SIZE) + o;
            calc_beta_addr = tmp[10:0];
        end
    endfunction

	 
    w_in_ram u_w_in_ram (
        .clock   (clk),
        .rden    (w_in_rden),
        .wren    (w_in_we),
        .address (w_in_we ? w_in_addr_ext : w_in_addr),
        .data    (w_in_wdata),
        .q       (w_in_q)
    );

    b_ram u_b_ram (
        .clock   (clk),
        .rden    (b_rden),
        .wren    (b_we),
        .address (b_we ? b_addr_ext : b_addr),
        .data    (b_wdata),
        .q       (b_q)
    );

    beta_ram u_beta_ram (
        .clock   (clk),
        .rden    (beta_rden),
        .wren    (beta_we),
        .address (beta_we ? beta_addr_ext : beta_addr),
        .data    (beta_wdata),
        .q       (beta_q)
    );

    img_ram u_img_ram (
        .clock   (clk),
        .data    (img_we ? img_wdata : img_wdata_ram),
        .wren    (img_we ? 1'b1 : img_wren_ram),
        .address (img_we ? img_addr : img_addr_ram),
        .rden    (img_rden_ram),
        .q       (img_q_ram)
    );

    fxp_mul_q412 u_fxp_mul_q412 (
        .a         (mac_a),
        .b         (mac_b),
        .prod_q412 (mac_prod_q412)
    );

    sigmoid_pwl_q412 u_sigmoid_pwl_q412 (
        .x_q412 (acc_hidden),
        .y_q412 (hidden_act_q412)
    );

    assign img_x_q412 = $signed({4'b0000, img_q_ram, 4'b0000});
    assign w_in_s     = $signed(w_in_q);
    assign b_s        = $signed(b_q);
    assign beta_s     = $signed(beta_q);
// =========================================================================
// FSM + Datapath — processo síncrono principal
// =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            error         <= 1'b0;
            pred          <= 4'd0;
            cycles        <= 32'd0;

            pix_idx       <= 10'd0;
            hid_idx       <= 7'd0;
            out_idx       <= 4'd0;

            acc_hidden    <= 32'sd0;
            acc_out       <= 32'sd0;

            best_score    <= 32'sd0;
            best_class    <= 4'd0;

            w_in_addr     <= 17'd0;
            b_addr        <= 7'd0;
            beta_addr     <= 11'd0;

            w_in_rden     <= 1'b0;
            b_rden        <= 1'b0;
            beta_rden     <= 1'b0;

            img_addr_ram  <= 10'd0;
            img_wdata_ram <= 8'd0;
            img_wren_ram  <= 1'b0;
            img_rden_ram  <= 1'b0;

            mac_a         <= 16'sd0;
            mac_b         <= 16'sd0;

            for (i = 0; i < HIDDEN_SIZE; i = i + 1)
                hidden_vec[i] <= 16'sd0;

            for (i = 0; i < OUT_SIZE; i = i + 1)
                logits[i] <= 32'sd0;

        end else begin
            w_in_rden    <= 1'b0;
            b_rden       <= 1'b0;
            beta_rden    <= 1'b0;
            img_wren_ram <= 1'b0;
            img_rden_ram <= 1'b0;

            if (clear_status && !busy) begin
                done  <= 1'b0;
                error <= 1'b0;
            end

            if (busy && !done && !error)
                cycles <= cycles + 32'd1;

            if ((img_we || w_in_we || b_we || beta_we) && busy) begin
                error <= 1'b1;
                done  <= 1'b0;
                busy  <= 1'b0;
                state <= S_ERROR;
            end

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        busy       <= 1'b1;
                        done       <= 1'b0;
                        error      <= 1'b0;
                        pred       <= 4'd0;
                        cycles     <= 32'd0;

                        pix_idx    <= 10'd0;
                        hid_idx    <= 7'd0;
                        out_idx    <= 4'd0;

                        acc_hidden <= 32'sd0;
                        acc_out    <= 32'sd0;

                        best_score <= 32'sd0;
                        best_class <= 4'd0;

                        mac_a      <= 16'sd0;
                        mac_b      <= 16'sd0;

                        for (i = 0; i < HIDDEN_SIZE; i = i + 1)
                            hidden_vec[i] <= 16'sd0;

                        for (i = 0; i < OUT_SIZE; i = i + 1)
                            logits[i] <= 32'sd0;

                        state <= S_LOAD_BIAS_REQ;
                    end
                end
					 // -------------------------------------------------------------
                // Fase 1: carregamento do bias do neurônio oculto hid_idx
                // -------------------------------------------------------------
                S_LOAD_BIAS_REQ: begin
                    b_addr  <= hid_idx;
                    b_rden  <= 1'b1;
                    state   <= S_LOAD_BIAS_W1;
                end

                S_LOAD_BIAS_W1: state <= S_LOAD_BIAS_W2;
                S_LOAD_BIAS_W2: state <= S_LOAD_BIAS_W3;
                S_LOAD_BIAS_W3: state <= S_LOAD_BIAS_W4;

                S_LOAD_BIAS_W4: begin
                    acc_hidden <= {{16{b_s[15]}}, b_s};
                    pix_idx    <= 10'd0;
                    state      <= S_HID_REQ;
                end
                // -------------------------------------------------------------
                // Fase 2: MAC da camada oculta — itera sobre os 784 pixels
                // acc_hidden += W[hid_idx][pix_idx] × img[pix_idx]
                // -------------------------------------------------------------
                S_HID_REQ: begin
                    img_addr_ram <= pix_idx;
                    img_rden_ram <= 1'b1;

                    w_in_addr    <= calc_w_in_addr(hid_idx, pix_idx);
                    w_in_rden    <= 1'b1;

                    state        <= S_HID_W1;
                end

                S_HID_W1: state <= S_HID_W2;
                S_HID_W2: state <= S_HID_W3;
                S_HID_W3: state <= S_HID_W4;

                S_HID_W4: begin
                    mac_a <= w_in_s;
                    mac_b <= img_x_q412;
                    state <= S_HID_ACC;
                end

                S_HID_ACC: begin
                    acc_hidden <= acc_hidden + mac_prod_q412;

                    if (pix_idx == IMG_SIZE - 1) begin
                        state <= S_ACTIVATION;
                    end else begin
                        pix_idx <= pix_idx + 10'd1;
                        state   <= S_HID_REQ;
                    end
                end
                // -------------------------------------------------------------
                // Fase 3: aplica sigmoid ao acumulador e armazena em hidden_vec
                // sigmoid_pwl é combinacional, então hidden_act_q412 já é válido
                // -------------------------------------------------------------
                S_ACTIVATION: begin
                    hidden_vec[hid_idx] <= hidden_act_q412;

                    if (hid_idx == HIDDEN_SIZE - 1) begin
                        out_idx <= 4'd0;
                        hid_idx <= 7'd0;
                        acc_out <= 32'sd0;
                        state   <= S_OUT_INIT;
                    end else begin
                        hid_idx <= hid_idx + 7'd1;
                        pix_idx <= 10'd0;
                        state   <= S_LOAD_BIAS_REQ;
                    end
                end
                // -------------------------------------------------------------
                // Fase 4: MAC da camada de saída — itera sobre os 128 neurônios
                // logits[out_idx] = Σ beta[hid][out] × hidden_vec[hid]
                // -------------------------------------------------------------
                S_OUT_INIT: begin
                    acc_out <= 32'sd0;
                    hid_idx <= 7'd0;
                    state   <= S_BETA_REQ;
                end

                S_BETA_REQ: begin
                    beta_addr <= calc_beta_addr(out_idx, hid_idx);
                    beta_rden <= 1'b1;
                    state     <= S_BETA_W1;
                end

                S_BETA_W1: state <= S_BETA_W2;
                S_BETA_W2: state <= S_BETA_W3;
                S_BETA_W3: state <= S_BETA_W4;

                S_BETA_W4: begin
                    mac_a <= beta_s;
                    mac_b <= hidden_vec[hid_idx];
                    state <= S_OUT_ACC;
                end

                S_OUT_ACC: begin
                    acc_out <= acc_out + mac_prod_q412;

                    if (hid_idx == HIDDEN_SIZE - 1) begin
                        logits[out_idx] <= acc_out + mac_prod_q412;

                        if (out_idx == OUT_SIZE - 1) begin
                            state <= S_ARGMAX_INIT;
                        end else begin
                            out_idx <= out_idx + 4'd1;
                            hid_idx <= 7'd0;
                            acc_out <= 32'sd0;
                            state   <= S_OUT_INIT;
                        end
                    end else begin
                        hid_idx <= hid_idx + 7'd1;
                        state   <= S_BETA_REQ;
                    end
                end
                // -------------------------------------------------------------
                // Fase 5: argmax — encontra a classe com maior logit
                // -------------------------------------------------------------
                S_ARGMAX_INIT: begin
                    best_score <= logits[0];
                    best_class <= 4'd0;
                    out_idx    <= 4'd1;
                    state      <= S_ARGMAX_STEP;
                end

                S_ARGMAX_STEP: begin
                    if (logits[out_idx] > best_score) begin
                        if (out_idx == OUT_SIZE - 1) begin
                            pred  <= out_idx;
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            best_score <= logits[out_idx];
                            best_class <= out_idx;
                            out_idx    <= out_idx + 4'd1;
                        end
                    end else begin
                        if (out_idx == OUT_SIZE - 1) begin
                            pred  <= best_class;
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            out_idx <= out_idx + 4'd1;
                        end
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_DONE;
                    if (start) begin  // Reuso imediato: reinicia sem passar por S_IDLE
                        done  <= 1'b0;
                        error <= 1'b0;
                        cycles <= 32'd0;
                        state <= S_LOAD_BIAS_REQ;
                        busy <= 1'b1;
                        pred <= 4'd0;
                        pix_idx <= 10'd0;
                        hid_idx <= 7'd0;
                        out_idx <= 4'd0;
                        acc_hidden <= 32'sd0;
                        acc_out <= 32'sd0;
                        best_score <= 32'sd0;
                        best_class <= 4'd0;
                        for (i = 0; i < HIDDEN_SIZE; i = i + 1)
                            hidden_vec[i] <= 16'sd0;
                        for (i = 0; i < OUT_SIZE; i = i + 1)
                            logits[i] <= 32'sd0;
                    end
                end

                S_ERROR: begin
                    busy  <= 1'b0;
                    done  <= 1'b0;
                    error <= 1'b1;
                    state <= S_ERROR;
                    if (clear_status)
                        state <= S_IDLE;
                end

                default: state <= S_ERROR;
            endcase
        end
    end

endmodule