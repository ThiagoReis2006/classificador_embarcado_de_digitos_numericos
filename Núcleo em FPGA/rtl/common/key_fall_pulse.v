module key_fall_pulse (
    input  wire clk,
    input  wire rst,
    input  wire key_n,   // botão ativo em 0
    output reg  pulse
);

    reg key_n_d;

    always @(posedge clk) begin
        if (rst) begin
            key_n_d <= 1'b1;
            pulse   <= 1'b0;
        end else begin
            pulse   <= key_n_d & ~key_n; // pulso no pressionamento
            key_n_d <= key_n;
        end
    end

endmodule