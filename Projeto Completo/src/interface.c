#define _GNU_SOURCE
#define _POSIX_C_SOURCE 199309L
#define _DEFAULT_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <math.h>
#include <sys/mman.h>
#include <unistd.h>
#include <linux/input.h>
#include <stdint.h>
#include <time.h>        
#include <string.h>

/* Tempo de exibição da imagem no VGA antes de iniciar a inferência (em segundos).
 * Ajuste conforme necessário. Modos 1 e 4 usam ATRASO_VGA_S; modo 3 usa metade. */
#define ATRASO_VGA_S 2

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#include "APIdriverFPGA.h"
#include "dados_imagem.h"
#include "pesos.h"

uint8_t imagem_desenhada[784];
uint16_t tela_virtual[240][320];

void limpar_buffer_entrada() {
    int c;
    while ((c = getchar()) != '\n' && c != EOF);
}

int ler_png_para_vetor(const char *caminho, uint8_t buffer[784]) {
    int largura, altura, canais;

    // Força leitura em escala de cinza (1 canal)
    uint8_t *dados = stbi_load(caminho, &largura, &altura, &canais, 1);

    if (dados == NULL) {
        fprintf(stderr, "Erro: não abriu '%s': %s\n", caminho, stbi_failure_reason());
        return -1;
    }

    if (largura != 28 || altura != 28) {
        fprintf(stderr, "Erro: imagem deve ser 28x28, mas é %dx%d\n", largura, altura);
        stbi_image_free(dados);
        return -1;
    }

    // Copia para o buffer
    for (int i = 0; i < 784; i++)
        buffer[i] = dados[i];

    stbi_image_free(dados);
    return 0;
}

int carregar_pesos_txt(const char *caminho_txt, int *vetor_destino, int tamanho_total) {
    FILE *arquivo = fopen(caminho_txt, "r");
    if (arquivo == NULL) {
        fprintf(stderr, "Erro: Não foi possível abrir o arquivo '%s'\n", caminho_txt);
        return -1;
    }

    for (int i = 0; i < tamanho_total; i++) {
        // %d lê o número inteiro e pula automaticamente a quebra de linha (\n)
        if (fscanf(arquivo, "%d", &vetor_destino[i]) != 1) {
            fprintf(stderr, "Erro: Falha ao ler o elemento no índice %d de '%s'. O arquivo pode estar incompleto.\n", i, caminho_txt);
            fclose(arquivo);
            return -1;
        }
    }

    fclose(arquivo);
    return 0;
}

void carregarBiasDinamico(volatile uint32_t *base){
    //Caminho do peso bias
    char caminho[100];
    int bias[128];
    printf("Digite o caminho do peso bias: ");
    scanf("%99s", caminho);
    limpar_buffer_entrada();
    if (carregar_pesos_txt(caminho,bias,128) != 0) return;
    enviarBias(base,bias);
    printf("Novo bias carregado com sucesso!\n");
};

void carregarBetaDinamico(volatile uint32_t *base){
    //Caminho do peso beta
    char caminho[100];
    int beta[1280];
    printf("Digite o caminho do peso beta: ");
    scanf("%99s", caminho);
    limpar_buffer_entrada();
    if (carregar_pesos_txt(caminho,beta,1280) != 0) return;
    enviarBeta(base,beta);
    printf("Novo beta carregado com sucesso!\n");
};

void carregarPesosEntradaDinamico(volatile uint32_t *base){
    char caminho[100];
    printf("Digite o caminho dos pesos de entrada (W_in): ");
    scanf("%99s", caminho);
    limpar_buffer_entrada();
    // Alocação dinâmica usando malloc para evitar STACK OVERFLOW
    int *pesosEntrada = (int *)malloc(100352 * sizeof(int));
    if (pesosEntrada == NULL) {
        fprintf(stderr, "Erro crítico: Falha ao alocar memória RAM para os pesos de entrada.\n");
        return;
    }
    if (carregar_pesos_txt(caminho, pesosEntrada, 100352) == 0) {
        enviarPesos(base, pesosEntrada);
        printf("Novos pesos de entrada (W_in) carregados com sucesso no Hardware!\n");
    }
    //Libera a memória alocada
    free(pesosEntrada);
}

void pintar_pixel_vga(volatile uint32_t *ptr_vga, int x, int y, int r, int g, int b) {
    if (x < 0 || x > 319 || y < 0 || y > 239) return;
    uint32_t pacote = (1 << 31) | (x << 17) | (y << 9) | (r << 6) | (g << 3) | b;
    enviarPixelVGA(ptr_vga, pacote);
    tela_virtual[y][x] = (r << 6) | (g << 3) | b;
}

void restaurar_pixel_vga(volatile uint32_t *ptr_vga, int x, int y) {
    if (x < 0 || x > 319 || y < 0 || y > 239) return;
    uint16_t cor = tela_virtual[y][x];
    int r = (cor >> 6) & 0x7;
    int g = (cor >> 3) & 0x7;
    int b = cor & 0x7;
    uint32_t pacote = (1 << 31) | (x << 17) | (y << 9) | (r << 6) | (g << 3) | b;
    enviarPixelVGA(ptr_vga, pacote);
}

void desenhar_cursor(volatile uint32_t *ptr_vga, int cx, int cy) {
    for(int i = -3; i <= 3; i++) {
        if (cx + i >= 0 && cx + i < 320) {
            uint32_t p = (1 << 31) | ((cx + i) << 17) | (cy << 9) | (7 << 6);
            enviarPixelVGA(ptr_vga, p);
        }
        if (cy + i >= 0 && cy + i < 240) {
            uint32_t p = (1 << 31) | (cx << 17) | ((cy + i) << 9) | (7 << 6);
            enviarPixelVGA(ptr_vga, p);
        }
    }
}

void apagar_cursor(volatile uint32_t *ptr_vga, int cx, int cy) {
    for(int i = -3; i <= 3; i++) {
        restaurar_pixel_vga(ptr_vga, cx + i, cy);
        restaurar_pixel_vga(ptr_vga, cx, cy + i);
    }
}

void limpar_tela_vga(volatile uint32_t *ptr_vga) {
    for (int y = 0; y < 240; y++) {
        for (int x = 0; x < 320; x++) {
            pintar_pixel_vga(ptr_vga, x, y, 0, 0, 0);
        }
    }
}

/*
 * exibir_imagem_vga — Renderiza um vetor 28x28 (grayscale 8-bit) no VGA.
 *
 * Cada pixel da imagem é ampliado para um bloco de 8x8 pixels na tela,
 * ocupando a região x=[48,271], y=[8,231] (224x224 px), centralizada no
 * display de 320x240. O valor de cinza [0,255] é convertido para RGB333
 * (3 bits por canal, [0,7]) proporcionalmente.
 *
 * Parâmetros:
 *   ptr_vga — ponteiro MMIO do IP-Core VGA
 *   imagem  — vetor de 784 bytes (linha-maior, 28 colunas por linha)
 */
void exibir_imagem_vga(volatile uint32_t *ptr_vga, const uint8_t imagem[784]) {
    for (int row = 0; row < 28; row++) {
        for (int col = 0; col < 28; col++) {
            uint8_t pixel = imagem[row * 28 + col];
            /* Escala [0,255] → [0,7] para RGB333 */
            int intensidade = (pixel * 7) / 255;
            int tela_x = 48 + col * 8;  /* offset horizontal = (320 - 224) / 2 */
            int tela_y = 8  + row * 8;  /* offset vertical   = (240 - 224) / 2 */
            for (int dy = 0; dy < 8; dy++) {
                for (int dx = 0; dx < 8; dx++) {
                    pintar_pixel_vga(ptr_vga,
                                     tela_x + dx, tela_y + dy,
                                     intensidade, intensidade, intensidade);
                }
            }
        }
    }
}

void registrar_ponto(volatile uint32_t *ptr_vga, int mouse_x, int mouse_y) {
    if (mouse_x >= 48 && mouse_x < 272 && mouse_y >= 8 && mouse_y < 232) {
        int nn_x = (mouse_x - 48) / 8;
        int nn_y = (mouse_y - 8) / 8;
        int tela_x = 48 + (nn_x * 8);
        int tela_y = 8 + (nn_y * 8);
        
        for (int i = 0; i < 8; i++) {
            for (int j = 0; j < 8; j++) {
                pintar_pixel_vga(ptr_vga, tela_x + i, tela_y + j, 7, 7, 7);
            }
        }
        
        if (nn_x >= 0 && nn_x < 28 && nn_y >= 0 && nn_y < 28) {
            imagem_desenhada[(nn_y * 28) + nn_x] = 255;
            if (nn_x > 0)  imagem_desenhada[(nn_y * 28) + (nn_x - 1)] = 255; 
            if (nn_x < 27) imagem_desenhada[(nn_y * 28) + (nn_x + 1)] = 255; 
            if (nn_y > 0)  imagem_desenhada[((nn_y - 1) * 28) + nn_x] = 255; 
            if (nn_y < 27) imagem_desenhada[((nn_y + 1) * 28) + nn_x] = 255; 
        }
    }
}

void desenhar_linha(volatile uint32_t *ptr_vga, int x0, int y0, int x1, int y1) {
    int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = dx + dy, e2;

    while (1) {
        registrar_ponto(ptr_vga, x0, y0);
        if (x0 == x1 && y0 == y1) break;
        e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}

void printar_matriz_desenhada() {
    printf("\n\n=== VISUALIZACAO DA MATRIZ (28x28) ===\n");
    for (int y = 0; y < 28; y++) {
        for (int x = 0; x < 28; x++) {
            if (imagem_desenhada[(y * 28) + x] > 0) printf("XX"); 
            else printf(".."); 
        }
        printf("\n"); 
    }
    printf("======================================\n\n");
}

void capturar_desenho_mouse(volatile uint32_t *ptr_vga) {
    int fd = open("/dev/input/event0", O_RDONLY | O_NONBLOCK); 
    if (fd < 0) return;

    struct input_event ev;
    int pos_x = 160, pos_y = 120;
    int pos_x_antiga = 160, pos_y_antiga = 120;
    int desenhando = 0;
    int moveu = 0;
    
    limpar_tela_vga(ptr_vga);
    for (int k = 0; k < 784; k++) imagem_desenhada[k] = 0;
    
    desenhar_cursor(ptr_vga, pos_x, pos_y);

    while (1) {
        if (read(fd, &ev, sizeof(struct input_event)) > 0) {
            if (ev.type == EV_KEY) {
                if (ev.code == BTN_LEFT) {
                    desenhando = ev.value;
                    if (desenhando) {
                        pos_x_antiga = pos_x;
                        pos_y_antiga = pos_y;
                    }
                }
                if (ev.code == BTN_RIGHT && ev.value == 1) break;
            }
            if (ev.type == EV_REL) {
                if (ev.code == REL_X) pos_x += ev.value;
                if (ev.code == REL_Y) pos_y += ev.value;

                if (pos_x < 0) pos_x = 0;
                if (pos_x > 319) pos_x = 319;
                if (pos_y < 0) pos_y = 0;
                if (pos_y > 239) pos_y = 239;
                
                moveu = 1;
            }
        } else {
            if (moveu) {
                apagar_cursor(ptr_vga, pos_x_antiga, pos_y_antiga);
                if (desenhando) {
                    desenhar_linha(ptr_vga, pos_x_antiga, pos_y_antiga, pos_x, pos_y);
                }
                desenhar_cursor(ptr_vga, pos_x, pos_y);
                pos_x_antiga = pos_x;
                pos_y_antiga = pos_y;
                moveu = 0;
            }
            usleep(1000);
        }
    }
    close(fd);
    apagar_cursor(ptr_vga, pos_x, pos_y);
}


void enviarImagemArquivo(volatile uint32_t *ptr, volatile uint32_t *ptr_vga){
    //Vetor da imagem em png
    uint8_t image[784];
    //Caminho da imagem
    char caminho[100];
    //Variável que retorna o Data out (contém o resultado da inferência, bit done,erro e busy, e também o contador de ciclos gastos)
    int retorno;
    //Variáveis para armazenar    
    int contador_clock;
    int resultado;
    int done;
    int busy;
    int erro;
    printf("Digite o caminho da imagem: ");
    scanf("%99s", caminho);
    limpar_buffer_entrada();
    if (ler_png_para_vetor(caminho, image) != 0) return;

    /* Exibe a imagem carregada no monitor VGA antes da inferência */
    printf("\nExibindo imagem no VGA...\n");
    limpar_tela_vga(ptr_vga);
    exibir_imagem_vga(ptr_vga, image);
    sleep(ATRASO_VGA_S);

    //Reseta o coprocessador
    printf("\nResetando hardware...\n");
    resetar_fpga(ptr);
    //Envia a imagem
    enviarImagem(ptr, image); 
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

void desenharVGA(volatile uint32_t *ptr, volatile uint32_t *ptr_vga){
    int contador_clock, resultado, done, busy, erro, retorno;

    capturar_desenho_mouse(ptr_vga);
    printar_matriz_desenhada();

    enviarImagem(ptr, imagem_desenhada); 
    retorno = iniciar_inferencia(ptr);

    contador_clock = (retorno >> 8) & 0xFFFFFF;
    resultado      = retorno & 0x0F;
    erro           = (retorno >> 6) & 1;

    printf("\n|--- RESULTADO DO SEU DESENHO ---|");
    printf("\n| Predicao : %d", resultado);
    printf("\n| Erro     : %d", erro);
    printf("\n| Ciclos   : %d", contador_clock);
    printf("\n|--------------------------------|\n\n");
    
}

void modoBenchmarkEValidacao(volatile uint32_t *ptr, volatile uint32_t *ptr_vga) {
    char caminho_dataset[100];
    printf("Digite o caminho do arquivo de índice do dataset (ex: dataset.txt): ");
    scanf("%99s", caminho_dataset);

    FILE *arquivo_index = fopen(caminho_dataset, "r");
    if (arquivo_index == NULL) {
        fprintf(stderr, "Erro ao abrir o arquivo de índice %s\n", caminho_dataset);
        return;
    }

    FILE *arquivo_csv = fopen("benchmark_resultados.csv", "w");
    if (arquivo_csv == NULL) {
        fprintf(stderr, "Erro ao criar arquivo CSV de saída.\n");
        fclose(arquivo_index);
        return;
    }

    // Cabeçalho do arquivo CSV PRINCIPAL atualizado com a coluna de throughput
    fprintf(arquivo_csv, "id,imagem,classe_real,classe_predita,ciclos_hardware,latencia_software_segundos,throughput_ips,status\n");

    // Variáveis de acumulação para métricas
    int total_imagens = 0;
    int acertos = 0;
    double soma_latencias = 0.0;
    double soma_quadrados_latencias = 0.0; // Para cálculo do desvio padrão

    // Buffers de leitura
    char caminho_imagem[150];
    int classe_real;
    uint8_t buffer_imagem[784];

    // Estruturas de tempo de alta precisão
    struct timespec t_ini, t_fim;

    /* Prepara o VGA para exibir as imagens do dataset */
    limpar_tela_vga(ptr_vga);

    printf("\nIniciando processamento em lote...\n");

    // O arquivo de índice deve conter linhas no formato: caminho_da_imagem.png classe_alvo
    // Exemplo: imagens/img_0.png 5
    while (fscanf(arquivo_index, "%s %d", caminho_imagem, &classe_real) != EOF) {
        
        // 1. Carrega a imagem do disco para a memória RAM
        if (ler_png_para_vetor(caminho_imagem, buffer_imagem) != 0) {
            fprintf(stderr, "Pulando imagem %s devido a erro de leitura.\n", caminho_imagem);
            continue;
        }

        total_imagens++;

        /* Exibe a imagem atual no VGA (fora da janela de medição de tempo) */
        exibir_imagem_vga(ptr_vga, buffer_imagem);
        sleep(ATRASO_VGA_S / 2);   /* metade do atraso: benchmark processa várias imagens */

        // Reset antes da transmissão de dados
        resetar_fpga(ptr);
        enviarImagem(ptr, buffer_imagem);

        // 2. Medição crítica da inferência (Início)
        clock_gettime(CLOCK_MONOTONIC, &t_ini);
        
        int retorno = iniciar_inferencia(ptr);
        
        clock_gettime(CLOCK_MONOTONIC, &t_fim);
        // Medição crítica da inferência (Fim)

        // 3. Extração das máscaras do hardware
        int contador_clock = (retorno >> 8) & 0xFFFFFF;
        int resultado      = retorno & 0x0F;
        int erro           = (retorno >> 6) & 1;

        // 4. Cálculo do tempo decorrido em software (em segundos)
        double latencia = (t_fim.tv_sec - t_ini.tv_sec) + 
                          (t_fim.tv_nsec - t_ini.tv_nsec) / 1000000000.0;

        // Calcula o Throughput Instantâneo desta imagem específica (Imagens por segundo)
        double throughput_inst = 0.0;
        if (latencia > 0.0) {
            throughput_inst = 1.0 / latencia;
        }

        // 5. Acumulação de dados estatísticos
        soma_latencias += latencia;
        soma_quadrados_latencias += (latencia * latencia);

        int status_acerto = (resultado == classe_real) ? 1 : 0;
        if (status_acerto) {
            acertos++;
        }

        // 6. Gravação imediata no log CSV (Agora imprimindo também o throughput_inst)
        fprintf(arquivo_csv, "%d,%s,%d,%d,%d,%.9f,%.2f,%s\n", 
                total_imagens, caminho_imagem, classe_real, resultado, 
                contador_clock, latencia, throughput_inst, status_acerto ? "CORRETO" : "ERRADO");
    }

    fclose(arquivo_index);
    fclose(arquivo_csv);

    if (total_imagens == 0) {
        printf("Nenhuma imagem válida foi processada no benchmark.\n");
        return;
    }

    FILE *arquivo1_csv = fopen("benchmark_métricas.csv", "w");
    if (arquivo1_csv == NULL) {
        fprintf(stderr, "Erro ao criar arquivo CSV de saída.\n");
        return;
    }

    // Cabeçalho do arquivo CSV
    fprintf(arquivo1_csv, "acurácia,latência média,desvio,throughput\n");

    // --- Cálculos Estatísticos Finais ---
    double acuracia = ((double)acertos / total_imagens) * 100.0;
    double latencia_media = soma_latencias / total_imagens;
    
    // Cálculo da variância e desvio padrão amostral
    double variancia = (soma_quadrados_latencias / total_imagens) - (latencia_media * latencia_media);
    double desvio_padrao = sqrt(variancia < 0 ? 0 : variancia);
    
    // Throughput = Total de Imagens / Tempo total gasto acumulado nas inferências
    double throughput_global = total_imagens / soma_latencias;

    // Deixei o printf do segundo csv corrigido com %.2f (ponto flutuante) para evitar de corromper o arquivo como acontecia no seu original.
    fprintf(arquivo1_csv, "%.2f,%.6f,%.6f,%.2f\n", 
        acuracia, latencia_media, desvio_padrao, throughput_global);

    fclose(arquivo1_csv);

    // --- Exibição na Interface Texto (Exigência do enunciado) ---
    printf("\n============================================================\n");
    printf("              RELATÓRIO FINAL DE BENCHMARK                   \n");
    printf("============================================================\n");
    printf(" Total de imagens processadas : %d\n", total_imagens);
    printf(" Total de acertos             : %d\n", acertos);
    printf(" Acurácia Global              : %.2f %%\n", acuracia);
    printf("------------------------------------------------------------\n");
    printf(" Latência Média de Software   : %.6f segundos (%.2f ms)\n", latencia_media, latencia_media * 1000.0);
    printf(" Desvio Padrão da Latência    : %.6f segundos\n", desvio_padrao);
    printf(" Throughput (Vazão)           : %.2f imagens/segundo\n", throughput_global);
    printf("============================================================\n");
    printf("Resultados detalhados salvos em 'benchmark_resultados.csv'\n\n");
}

void inferenciaComImagemQualquer(volatile uint32_t *ptr, volatile uint32_t *ptr_vga, int numero_de_testes){
    //Variável que retorna o Data out (contém o resultado da inferência, bit done,erro e busy, e também o contador de ciclos gastos)
    int retorno;
    //Variáveis para armazenar    
    int contador_clock;
    int resultado;
    int done;
    int busy;
    int erro;
    int i;

    /* Exibe a imagem de teste no VGA uma vez, antes do loop de repetições */
    printf("\nExibindo imagem de teste no VGA...\n");
    limpar_tela_vga(ptr_vga);
    exibir_imagem_vga(ptr_vga, imagem7);
    sleep(ATRASO_VGA_S);

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
        enviarImagem(ptr, imagem7); 

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
}

int main() {
    //Declaração do ponteiro para a base da FPGA
    volatile uint32_t *ptr;
    //O ponteiro recebe o endereço da base da FPGA
    ptr = inicializar_hardware();
    //Verifica se retornou um endereço nulo
    if (ptr == NULL){
        printf("Erro obter endereço base da FPGA!\n");
        return 1;
    }
    //ponteiro virtual para o VGA
    volatile uint32_t *ptr_vga = ptr + (0x40 / 4);
    //Reseta as flags da FPGA e o último número inferido
    resetar_fpga(ptr);
    //Carrega o bias
    enviarBias(ptr, vetor_Bias);
    //Carrega o beta
    enviarBeta(ptr, vetor_Beta);
    //Carrega o peso de entrada
    enviarPesos(ptr, vetor_W_in);
    //Número de testes
    int testes = 0;
    //Menu
    int escolha = 0;
    int sair = 0;
    do {
        printf("---------------------------[MENU]---------------------------\n");
        printf("\n| [1] MODO DE IMAGEM DE UM ARQUIVO                         |\n");
        printf("| [2] MODO DE IMAGEM DESENHADA NA TELA                     |\n");
        printf("| [3] MODO DE VALIDAÇÃO/BENCHMARK                          |\n");
        printf("| [4] TESTAR UMA IMAGEM ALGUMAS VEZES                      |\n");
        printf("| [5] CARREGAR BIAS                                        |\n");
        printf("| [6] CARREGAR BETA                                        |\n");
        printf("| [7] CARREGAR PESOS DE ENTRADA                            |\n");
        printf("| [8] SAIR                                                 |\n");
        printf("------------------------------------------------------------\n");
        printf("Escolha uma opção: ");
        // Verifica se o usuário digitou um número válido para evitar loop infinito
        if (scanf("%d", &escolha) != 1) {
            printf("Entrada inválida! Digite apenas números.\n");
            limpar_buffer_entrada();
            continue;
        }
        limpar_buffer_entrada();
        switch (escolha)
        {
        case 1:
            enviarImagemArquivo(ptr, ptr_vga);
            break;

        case 2:
            desenharVGA(ptr,ptr_vga);
            break;

        case 3:
            modoBenchmarkEValidacao(ptr, ptr_vga);
            break;

        case 4:
            printf("Digite o número de testes: ");
            if (scanf("%d", &testes) != 1) {
                printf("Número inválido.\n");
                limpar_buffer_entrada();
                break;
            }
            limpar_buffer_entrada();
            inferenciaComImagemQualquer(ptr, ptr_vga, testes);
            break;

        case 5:
            carregarBiasDinamico(ptr);
            break;

        case 6:
            carregarBetaDinamico(ptr);
            break;
            
        case 7:
            carregarPesosEntradaDinamico(ptr);
            break;

        case 8:
            sair = 1;
            break;
        
        default:
            break;
        }
    } while (sair != 1);
    
    return 0;
}