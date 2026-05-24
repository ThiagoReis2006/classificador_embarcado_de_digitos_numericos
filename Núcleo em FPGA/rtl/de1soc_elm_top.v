/* * Módulo: de1soc_elm_top
 * Descrição: Top-level para integração do co-processador ELM na placa DE1-SoC.
 * Responsável pela interface entre periféricos físicos (SW, KEY, HEX)
 */
module de1soc_elm_top (
    input  wire        CLOCK_50,
    input  wire [9:0]  SW,
    input  wire [3:0]  KEY,
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5
);

// Definição das Opcodes (Instruções) do Co-processador
    localparam [2:0]
        OP_NOP          = 3'b000,
        OP_STORE_IMG    = 3'b001,
        OP_STORE_WEIGHT = 3'b010,
        OP_STORE_BIAS   = 3'b011,
        OP_START        = 3'b100,
        OP_STATUS       = 3'b101,
        OP_STORE_BETA   = 3'b110,
        OP_CLEAR        = 3'b111;

    wire rst;
    wire exec_pulse;

    wire protect_inference;
    wire [2:0] opcode_sw;
    wire [2:0] addr_sw;
    wire [2:0] data_sw;

    reg        start_cmd;
    reg        clear_status_cmd;

    reg        img_we_cmd;
    reg [9:0]  img_addr_cmd;
    reg [7:0]  img_wdata_cmd;

    reg        w_in_we_cmd;
    reg [16:0] w_in_addr_cmd;
    reg [15:0] w_in_wdata_cmd;

    reg        b_we_cmd;
    reg [6:0]  b_addr_cmd;
    reg [15:0] b_wdata_cmd;

    reg        beta_we_cmd;
    reg [10:0] beta_addr_cmd;
    reg [15:0] beta_wdata_cmd;

    wire        busy;
    wire        done;
    wire        error;
    wire [3:0]  pred;
    wire [31:0] cycles;

    reg [31:0] reg_ctrl;
    reg [31:0] reg_status;
    reg [31:0] reg_addr;
    reg [31:0] reg_wdata;
    reg [31:0] reg_result;
    reg [31:0] reg_cycles;
    reg [31:0] reg_debug;

    reg [3:0] display_nibble;
    reg [3:0] status_code;

    function [15:0] expand_q412_3b;
        input [2:0] x;
        begin
            case (x)
                3'd0: expand_q412_3b = 16'h0000;
                3'd1: expand_q412_3b = 16'h0100;
                3'd2: expand_q412_3b = 16'h0200;
                3'd3: expand_q412_3b = 16'h0400;
                3'd4: expand_q412_3b = 16'h0800;
                3'd5: expand_q412_3b = 16'h1000;
                3'd6: expand_q412_3b = 16'h2000;
                3'd7: expand_q412_3b = 16'h4000;
            endcase
        end
    endfunction
	 
// Mapeamento das chaves para controle manual
    assign rst               = ~KEY[0];
    assign protect_inference = SW[9];
    assign opcode_sw         = SW[8:6];
    assign addr_sw           = SW[5:3];
    assign data_sw           = SW[2:0];

    key_fall_pulse u_exec_pulse (
        .clk   (CLOCK_50),
        .rst   (rst),
        .key_n (KEY[1]),
        .pulse (exec_pulse)
    );

    elm_accel u_elm_accel (
        .clk          (CLOCK_50),
        .rst          (rst),
        .start        (start_cmd),
        .clear_status (clear_status_cmd),

        .img_we       (img_we_cmd),
        .img_addr     (img_addr_cmd),
        .img_wdata    (img_wdata_cmd),

        .w_in_we      (w_in_we_cmd),
        .w_in_addr_ext(w_in_addr_cmd),
        .w_in_wdata   (w_in_wdata_cmd),

        .b_we         (b_we_cmd),
        .b_addr_ext   (b_addr_cmd),
        .b_wdata      (b_wdata_cmd),

        .beta_we      (beta_we_cmd),
        .beta_addr_ext(beta_addr_cmd),
        .beta_wdata   (beta_wdata_cmd),

        .busy         (busy),
        .done         (done),
        .error        (error),
        .pred         (pred),
        .cycles       (cycles)
    );
	 /*
     * Lógica de Controle Sequencial
     * Processa comandos manuais baseados no pulso do KEY[1]
     */
    always @(posedge CLOCK_50) begin
        if (rst) begin
            start_cmd        <= 1'b0;
            clear_status_cmd <= 1'b0;

            img_we_cmd       <= 1'b0;
            img_addr_cmd     <= 10'd0;
            img_wdata_cmd    <= 8'd0;

            w_in_we_cmd      <= 1'b0;
            w_in_addr_cmd    <= 17'd0;
            w_in_wdata_cmd   <= 16'd0;

            b_we_cmd         <= 1'b0;
            b_addr_cmd       <= 7'd0;
            b_wdata_cmd      <= 16'd0;

            beta_we_cmd      <= 1'b0;
            beta_addr_cmd    <= 11'd0;
            beta_wdata_cmd   <= 16'd0;

            reg_ctrl         <= 32'd0;
            reg_status       <= 32'd0;
            reg_addr         <= 32'd0;
            reg_wdata        <= 32'd0;
            reg_result       <= 32'd0;
            reg_cycles       <= 32'd0;
            reg_debug        <= 32'd0;
            display_nibble   <= 4'd0;
        end else begin
            start_cmd        <= 1'b0;
            clear_status_cmd <= 1'b0;
            img_we_cmd       <= 1'b0;
            w_in_we_cmd      <= 1'b0;
            b_we_cmd         <= 1'b0;
            beta_we_cmd      <= 1'b0;

            reg_status <= {24'd0, error, done, busy, pred};
            reg_result <= {28'd0, pred};
            reg_cycles <= cycles;
            reg_ctrl   <= {20'd0, protect_inference, opcode_sw, addr_sw, data_sw};

            if (exec_pulse) begin
                reg_addr    <= {29'd0, addr_sw};
                reg_wdata   <= {29'd0, data_sw};
                reg_debug   <= {20'd0, protect_inference, opcode_sw, addr_sw, data_sw};

                case (opcode_sw)
                    OP_NOP: begin
                        display_nibble <= 4'h0;
                    end

                    OP_STORE_IMG: begin
                        img_addr_cmd   <= {7'd0, addr_sw};
                        img_wdata_cmd  <= {5'd0, data_sw};
                        display_nibble <= {1'b0, data_sw};
                        if (!protect_inference && !busy)
                            img_we_cmd <= 1'b1;
                    end

                    OP_STORE_WEIGHT: begin
                        w_in_addr_cmd   <= {14'd0, addr_sw};
                        w_in_wdata_cmd  <= expand_q412_3b(data_sw);
                        display_nibble  <= {1'b0, data_sw};
                        if (!protect_inference && !busy)
                            w_in_we_cmd <= 1'b1;
                    end

                    OP_STORE_BIAS: begin
                        b_addr_cmd      <= {4'd0, addr_sw};
                        b_wdata_cmd     <= expand_q412_3b(data_sw);
                        display_nibble  <= {1'b0, data_sw};
                        if (!protect_inference && !busy)
                            b_we_cmd <= 1'b1;
                    end

                    OP_START: begin
                        start_cmd      <= 1'b1;
                        display_nibble <= 4'hA;
                    end

                    OP_STATUS: begin
                        display_nibble <= pred;
                    end

                    OP_STORE_BETA: begin
                        beta_addr_cmd   <= {8'd0, addr_sw};
                        beta_wdata_cmd  <= expand_q412_3b(data_sw);
                        display_nibble  <= {1'b0, data_sw};
                        if (!protect_inference && !busy)
                            beta_we_cmd <= 1'b1;
                    end

                    OP_CLEAR: begin
                        clear_status_cmd <= 1'b1;
                        display_nibble   <= 4'hC;
                    end
                endcase
            end
        end
    end

    always @(*) begin
        if (error)
            status_code = 4'hE;
        else if (done)
            status_code = 4'hD;
        else if (busy)
            status_code = 4'hB;
        else
            status_code = 4'h0;
    end
	 /*
     * Mapeamento Visual e Status
     * Converte sinais binários para representação em 7 segmentos (HEX) e LEDs
     */
    assign LEDR[0] = busy;
    assign LEDR[1] = done;
    assign LEDR[2] = error;
    assign LEDR[3] = protect_inference;
    assign LEDR[6:4] = opcode_sw;
    assign LEDR[9:7] = addr_sw;
	// Decodificação para displays de 7 segmentos
    hex7seg_de1soc u_hex0 (.hex(pred),         .seg(HEX0));
    hex7seg_de1soc u_hex1 (.hex(status_code),  .seg(HEX1));
    hex7seg_de1soc u_hex2 (.hex(cycles[3:0]),  .seg(HEX2));
    hex7seg_de1soc u_hex3 (.hex(cycles[7:4]),  .seg(HEX3));
    hex7seg_de1soc u_hex4 (.hex(display_nibble), .seg(HEX4));
    hex7seg_de1soc u_hex5 (.hex({1'b0, data_sw}), .seg(HEX5));

endmodule