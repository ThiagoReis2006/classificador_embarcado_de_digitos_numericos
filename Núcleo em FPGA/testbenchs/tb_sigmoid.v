`timescale 1ns/1ps

module tb_sigmoid;
    logic signed [31:0] x;
    logic signed [15:0] y;

    // Instância do seu módulo
    sigmoid_pwl_q412 dut (.x_q412(x), .y_q412(y));

    initial begin
        $display("Sigmoid PWL Test (Format Q4.12)");
        $display("X (Hex)    | X (Dec) | Y (Hex) | Y (Dec)");
        
        // Teste 1: x <= -4 (deve saturar em 0)
        x = -32'sd20000; #10; 
        $display("%h | %f | %h | %f", x, real'(x)/4096, y, real'(y)/4096);

        // Teste 2: x = 0 (deve ser 0.5 -> 2048 em Hex)
        x = 32'sd0; #10;
        $display("%h | %0.1f      | %h | %0.4f", x, 0.0, y, real'(y)/4096);

        // Teste 3: x = 2.0 (região de transição)
        x = 32'sd8192; #10;
        $display("%h | %0.1f      | %h | %0.4f", x, 2.0, y, real'(y)/4096);

        // Teste 4: x >= 4 (deve saturar em 1.0 -> 4096 em Hex)
        x = 32'sd16384; #10;
        $display("%h | %0.1f      | %h | %0.4f", x, 4.0, y, real'(y)/4096);

        $finish;
    end
endmodule