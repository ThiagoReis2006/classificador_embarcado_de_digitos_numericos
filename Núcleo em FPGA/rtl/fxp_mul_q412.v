// Multiplicador de ponto fixo no formato Q4.12
// Ambos os operandos são Q4.12 com 16 bits (1 sinal + 3 inteiro + 12 fracionário).
// A multiplicação plena gera Q8.24 em 32 bits; o shift aritmético de 12 posições
// descarta a parte fracionária extra e retorna o resultado em Q4.12.
module fxp_mul_q412 (
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    output wire signed [31:0] prod_q412
);

    wire signed [31:0] prod_full;

    assign prod_full = a * b;
	 
	 // Reajuste do ponto fixo: descarta os 12 bits fracionários extras
    // >>> preserva o sinal (shift aritmético)
    assign prod_q412 = prod_full >>> 12;

endmodule