`timescale 1ns/1ps

module tb_mac;
    logic signed [15:0] a, b;
    logic signed [31:0] prod;
    logic signed [31:0] accumulator;

    // Instância do seu multiplicador
    fxp_mul_q412 multiplier (.a(a), .b(b), .prod_q412(prod));

    initial begin
        accumulator = 0;
        $display("MAC Unit Test (Fixed Point Q4.12)");

        // Operação: (2.0 * 1.5) + (-0.5 * 2.0) = 3.0 - 1.0 = 2.0
        
        // Passo 1: 2.0 * 1.5
        a = 16'sh2000; // 2.0 em Q4.12
        b = 16'sh1800; // 1.5 em Q4.12
        #10;
        accumulator = accumulator + prod;
        $display("Step 1: Acc = %f", real'(accumulator)/4096);

        // Passo 2: -0.5 * 2.0
        a = -16'sh0800; // -0.5 em Q4.12
        b = 16'sh2000;  // 2.0 em Q4.12
        #10;
        accumulator = accumulator + prod;
        $display("Step 2: Acc = %f (Esperado: 2.0)", real'(accumulator)/4096);

        if (accumulator == 32'sh2000) $display(">>> MAC: SUCESSO");
        else $display(">>> MAC: FALHA");
        
        $finish;
    end
endmodule