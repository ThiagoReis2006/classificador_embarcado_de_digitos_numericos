// Aproximação linear por partes (PWL) da função sigmoid em Q4.12.
module sigmoid_pwl_q412 (
    input  wire signed [31:0] x_q412,
    output reg  signed [15:0] y_q412
);

    localparam signed [31:0] NEG4 = -32'sd16384;
    localparam signed [31:0] NEG2 = -32'sd8192;
    localparam signed [31:0] POS2 =  32'sd8192;
    localparam signed [31:0] POS4 =  32'sd16384;
	 
//   x ≤ -4.0  (-16384) → y = 0.0       (0)
//   -4 < x < -2.0      → y = 0.0625·(x + 4)   (rampa suave)
//   -2 ≤ x < +2.0      → y = 0.5 + 0.125·x    (região linear central)
//   +2 ≤ x < +4.0      → y = 0.75 + 0.0625·(x - 2)  (rampa suave)
//   x ≥ +4.0  (+16384) → y = 1.0       (4096)

    always @(*) begin
        if (x_q412 <= NEG4) begin
            y_q412 = 16'sd0;
        end else if (x_q412 < NEG2) begin
            y_q412 = (x_q412 + 32'sd16384) >>> 4;
        end else if (x_q412 < POS2) begin
            y_q412 = 16'sd2048 + (x_q412 >>> 3);
        end else if (x_q412 < POS4) begin
            y_q412 = 16'sd3072 + ((x_q412 - 32'sd8192) >>> 4);
        end else begin
            y_q412 = 16'sd4096;
        end
    end

endmodule