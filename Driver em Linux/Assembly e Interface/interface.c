#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <math.h>
#include <sys/mman.h>
#include "APIdriverFPGA.h"
#include "dados_imagem.h"
#include "pesos.h"

int main() {
    //Declaração do ponteiro para a base da FPGA
    volatile uint32_t *ptr;
    //O ponteiro recebe o endereço da base da FPGA
    ptr = inicializar_hardware();
    //Número de inferências para o loop
    int numero_de_testes = 20; 
    //Variável que retorna o Data out (contém o resultado da inferência, bit done,erro e busy, e também o contador de ciclos gastos)
    int retorno;
    //Variáveis para armazenar    
    int contador_clock;
    int resultado;
    int done;
    int busy;
    int erro;

    printf("\n|-------------------------------------------------|");
    printf("\n| Iniciando inferência sem os pesos carregados... |");
    printf("\n|-------------------------------------------------|\n");
    //retorna o data out do coprocessador
    retorno = iniciar_inferencia(ptr);
    //Máscara de bits para separar as informações contida no data out 
    contador_clock = (retorno >> 8) & 0xFFFFFF;
    resultado      = retorno & 0x0F;
    done           = (retorno >> 4) & 1;
    busy           = (retorno >> 5) & 1;
    erro           = (retorno >> 6) & 1;
    //Print da inferência antes de enviar os dados
    printf("| Resultado: %d\n| Erro: %d\n| Ciclos de clock: %d\n| Done: %d\n|-------------------------------------------------|\n", resultado, erro, contador_clock, done);
    
    int i;
    //Loop para fazer as operações necessárias da inferência
    for (i = 0; i < numero_de_testes; i++) { 
        printf("\n--- Iniciando Execução %d ---\n", i + 1);

        printf("\nResetando hardware...\n");
        //Reseta o coprocessador
        resetar_fpga(ptr);

        printf("Enviando Bias...\n");
        //Envia o bias
        enviarBias(ptr, vetor_Bias);

        printf("Enviando Betas...\n");
        //Envia o beta
        enviarBeta(ptr, vetor_Beta);

        printf("Enviando W_in...\n");
        //Envia o W_in
        enviarPesos(ptr, vetor_W_in);

        printf("Enviando imagem...\n");
        //Envia a imagem
        enviarImagem(ptr, imagem4); 

        printf("\n|-------------------------|");
        printf("\n| Iniciando inferência... |");
        printf("\n|-------------------------|\n");
        //retorna o data out do coprocessador
        retorno = iniciar_inferencia(ptr);
        //Máscara de bits para separar as informações contida no data out 
        contador_clock = (retorno >> 8) & 0xFFFFFF;
        resultado      = retorno & 0x0F;
        done           = (retorno >> 4) & 1;
        busy           = (retorno >> 5) & 1;
        erro           = (retorno >> 6) & 1;

        printf("| Resultado: %d\n| Erro: %d\n| Ciclos de clock: %d\n| Done: %d\n|-------------------------|\n", resultado, erro, contador_clock, done);
    }

    return 0;
}
