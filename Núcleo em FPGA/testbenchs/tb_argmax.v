`timescale 1ns/1ps

module tb_argmax;
    logic signed [31:0] current_logit;
    logic signed [31:0] best_score;
    logic [3:0] best_class;
    
    // Simulação do array de saída da rede neural (Logits)
    logic signed [31:0] test_logits [0:9] = '{
        32'hFFFFF000, // Classe 0: -1.0
        32'h00002000, // Classe 1:  2.0
        32'h00005000, // Classe 2:  5.0 (Vencedor)
        32'h00001800, // Classe 3:  1.5
        32'hFFFFE000, // Classe 4: -2.0
        32'h00004500, // Classe 5:  4.3
        32'h00000000, // Classe 6:  0.0
        32'h00001000, // Classe 7:  1.0
        32'hFFFFC000, // Classe 8: -4.0
        32'h00000500  // Classe 9:  0.3
    };

    initial begin
        best_score = 32'h80000000; // Menor valor possível (Sinalizado)
        best_class = 0;

        $display("Iniciando busca do Argmax...");

        for (int i = 0; i < 10; i++) begin
            current_logit = test_logits[i];
            
            // Lógica idêntica ao seu elm_accel.v
            if (current_logit > best_score || i == 0) begin
                best_score = current_logit;
                best_class = i[3:0];
            end
            $display("Iteracao %0d: Score=%f | Melhor ate agora: Classe %0d", i, real'(current_logit)/4096, best_class);
        end

        $display("\nResultado Final: Classe %0d com Score %f", best_class, real'(best_score)/4096);
        
        if (best_class == 4'd2) $display(">>> ARGMAX: SUCESSO");
        else $display(">>> ARGMAX: FALHA");

        $finish;
    end
endmodule