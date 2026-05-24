.section .data
dev_mem: .asciz "/dev/mem"

.section .text
.global enviarImagem
.global enviarBias
.global enviarBeta
.global enviarPesos
.global resetar_fpga
.global iniciar_inferencia
.global clear_fpga
.global inicializar_hardware
.global enviarSingleImage
.global enviarSingleBeta
.global enviarSingleBias
.global enviarSingleWin

.equ endereco_base, 0xFF200000
.equ endereco_base_pgoff, 0xFF200
.equ MAX_PIXELS, 784
.equ MAX_BIAS,   128
.equ MAX_BETA,   1280
.equ MAX_PESOS,  100352
.equ OFFSET_SIGNALS, 0x10
.equ OFFSET_DATA_IN, 0x30
.equ OFFSET_DATA_OUT, 0x20
.equ BIT_ENABLE, 1
.equ BIT_CLEAR,  2
.equ BIT_RESET,  4
.equ BIT_DONE,   0x10
.equ BIT_BUSY,   0x20
.equ BIT_ERROR,  0x40

.type inicializar_hardware, %function
.type resetar_fpga, %function
.type clear_fpga, %function
.type enviarImagem, %function
.type iniciar_inferencia, %function
.type enviarBias, %function
.type enviarBeta, %function
.type enviarPesos, %function
.type enviarSingleImage,%function
.type enviarSingleBeta,%function
.type enviarSingleBias,%function
.type enviarSingleWin,%function

@Rotina para abrir o dev/mem e retornar o endereço base da FPGA
inicializar_hardware:
    PUSH {R4-R7, LR}
    @ 1. Abrir /dev/mem
    MOV R7, #5              @ Syscall open
    LDR R0, =dev_mem
    MOV R1, #2              @ O_RDWR
    MOV R2, #0
    SWI 0
    MOV R4, R0              @ Salva o File Descriptor em R4

    @ 2. Mapear com mmap2
    @ mmap2(start, length, prot, flags, fd, pgoffset)
    MOV R7,#192            @ Syscall mmap2
    MOV R0, #0              @ Deixa o OS escolher o endereço virtual
    LDR R1, =4096           @ Tamanho da página (4KB)
    MOV R2, #3              @ PROT_READ | PROT_WRITE
    MOV R3, #1              @ MAP_SHARED
    @ R4 já tem o FD
    LDR R5, =endereco_base_pgoff       @ Endereço físico / 4096 (pgoffset)
    SWI 0
    POP {R4-R7, PC}

@Rotina para resetar o coprocessador, recebe em R0 o endereço base da FPGA
resetar_fpga:
    MOV R1, #BIT_RESET
    STR R1, [R0, #OFFSET_SIGNALS]
    MOV R1, #0
    STR R1, [R0, #OFFSET_SIGNALS]
    BX LR

@Rotina para limpar o bit done e error no coprocessador, recebe em R0 o endereço base da FPGA
clear_fpga:
    MOV R1, #BIT_CLEAR
    STR R1, [R0, #OFFSET_SIGNALS]
    MOV R1, #0
    STR R1, [R0, #OFFSET_SIGNALS]
    BX LR

@Rotina para enviar o enable para o coprocessador e permitir o envio dos pesos e iniciar a inferência
pulsar_enable:
    MOV R1, #BIT_ENABLE
    STR R1, [R0,#OFFSET_SIGNALS]
    MOV R1, #0
    STR R1, [R0,#OFFSET_SIGNALS]
    BX LR

@Polling para ficar verificando se o resultado da inferência está pronto
loop_polling:
    LDR R1, [R0, #OFFSET_DATA_OUT]
    TST R1, #BIT_ERROR
    BNE poll_exit
    TST R1, #BIT_DONE
    BEQ loop_polling
    B poll_exit

@Saída do pooling
poll_exit:
    MOV R0, R1
    BX LR

@Rotina para verificar se o endereço do peso foi enviado
aguardar_idle:
    LDR R1, [R0, #OFFSET_DATA_OUT]
    TST R1, #BIT_BUSY
    BNE aguardar_idle
    BX LR

@Rotina para enviar a imagem para o coprocessador, a imagem recebida é um vetor
@R0: ENDEREÇO BASE DA FPGA
@R1: ENDEREÇO BASE DA IMAGEM 
enviarImagem:
    PUSH {R4-R7, LR}
    MOV R5, #0
    MOV R3,R1
    B loop_imagem

loop_imagem:
    @Compara R5 == 784, caso seja verdadeiro sai do loop
    CMP R5,#MAX_PIXELS
    BEQ fim_loop_imagem
    
    @Carrega em R4 o valor do pixel no endereço que está em R3 e soma R3 para avançar pro próximo endereço
    MOV R6,#0
    LDRB R4,[R3]
    ADD R3,R3,#1

    @Criação do pacote para enviar pro coprocessador
    ORR R6,R6,#0
    ORR R6,R6,R5, LSL #3
    ORR R6,R6,R4, LSL #13

    @Envia o pacote para o coprocessador
    STR R6,[R0,#OFFSET_DATA_IN]
    MOV R7,R0
    @Envia o enable para permitir a escrita
    BL pulsar_enable
    @Verifica se ja enviou
    BL loop_polling
    MOV R0,R7
    @Limpa a flag de error e done
    BL clear_fpga
    @Soma o contador
    ADD R5,R5,#1
    B loop_imagem

fim_loop_imagem:
    MOV R6,#0
    STR R6,[R0,#OFFSET_SIGNALS]
    POP {R4-R7, PC}

@Rotina para iniciar a inferência, Recebe em R0 o endereço base da FPGA
iniciar_inferencia:
    PUSH {LR}
    MOV R1, #5
    STR R1, [R0, #OFFSET_DATA_IN]
    BL pulsar_enable
    BL loop_polling
    POP {PC}

@Rotina para enviar o bias para o coprocessador, o bias recebido é um vetor
@R0: ENDEREÇO BASE DO FPGA
@R1: ENDEREÇO BASE DO BIAS
enviarBias:
    PUSH {R4-R7, LR}
    MOV R5, #0
    MOV R2,R1
    B loop_bias

loop_bias:
    @Compara R5 == 128, caso seja verdadeiro sai do loop
    CMP R5,#MAX_BIAS
    BEQ fim_loop_bias

    @Carrega em R4 o valor do bias que está no endereço que R2 armazena e soma R2 para ir pro próximo endereço
    MOV R6,#0
    LDRSH R4,[R2]
    ADD R2,R2,#2

    @Criação do pacote para enviar pro coprocessador
    ORR R6,R6,#3                
    ORR R6,R6,R5, LSL #3  
    ORR R6,R6,R4, LSL #10
    
    @Envia o pacote para o coprocessador
    STR R6,[R0,#OFFSET_DATA_IN]
    MOV R7,R0
    BL pulsar_enable
    BL loop_polling
    MOV R0,R7
    BL clear_fpga
    @Soma o contador
    ADD R5,R5,#1
    B loop_bias

fim_loop_bias:
    MOV R6,#0
    STR R6,[R0,#OFFSET_SIGNALS]
    POP {R4-R7, PC}

@Rotina para enviar o beta para o coprocessador, o beta recebido é um vetor
@R0: ENDEREÇO BASE DA FPGA
@R1: ENDEREÇO BASE DO BETA
enviarBeta:
    PUSH {R4-R7, LR}
    MOV R5, #0
    MOV R2,R1
    B loop_beta

loop_beta:
    @Compara R5 == 1280, caso seja verdadeiro sai do loop
    CMP R5,#MAX_BETA
    BEQ fim_loop_beta

    @Carrega em R4 o valor do beta que está no endereço que R2 armazena e soma R2 para ir pro próximo endereço
    MOV R6,#0
    LDRSH R4,[R2]
    ADD R2,R2,#2

    @Criação do pacote para enviar pro coprocessador
    ORR R6,R6,#4
    ORR R6,R6,R5, LSL #3
    ORR R6,R6,R4, LSL #14

    @Envia o pacote para o coprocessador
    STR R6,[R0,#OFFSET_DATA_IN]
    MOV R7,R0
    BL pulsar_enable
    BL loop_polling
    MOV R0,R7
    BL clear_fpga
    @Soma o contador
    ADD R5,R5,#1
    B loop_beta

fim_loop_beta:
    MOV R6,#0
    STR R6,[R0,#OFFSET_SIGNALS]
    POP {R4-R7, PC}

@Rotina para enviar o W_in para o coprocessador, o W_in recebido é um vetor
@R0: ENDEREÇO BASE DA FPGA
@R1: ENDEREÇO BASE DOS PESOS
enviarPesos:
    PUSH {R4-R7, LR}
    MOV R5, #0
    MOV R2,R1
    LDR R7, =MAX_PESOS
    B loop_pesos

loop_pesos:
    @Compara R5 == 100352, caso seja verdadeiro sai do loop
    CMP R5, R7
    BEQ fim_loop_pesos

    @Criação do pacote para enviar pro coprocessador (pacote da parte 1: Endereço)
    MOV R6, #1   
    ORR R6, R6, R5, LSL #3 
    @Envia o pacote para o coprocessador
    STR R6, [R0,#OFFSET_DATA_IN]
    BL pulsar_enable
    @Verifica se enviou
    BL aguardar_idle

    @Carrega em R4 o valor do W_in que está no endereço que R2 armazena e soma R2 para ir pro próximo endereço
    LDRSH R4, [R2]
    ADD R2, R2, #2

    @Criação do pacote para enviar pro coprocessador (pacote da parte 2: Dados)
    MOV R6, #2
    ORR R6, R6, R4, LSL #3
    @Envia o pacote para o coprocessador
    STR R6, [R0,#OFFSET_DATA_IN]
    MOV R3,R0
    @Envia o enable para permitir a escrita
    BL pulsar_enable
    @Verifica se ja enviou
    BL loop_polling
    MOV R0,R3
    BL clear_fpga
    @Soma o contador
    ADD R5, R5, #1
    B loop_pesos

@Sai do loop
fim_loop_pesos:
    MOV R6,#0
    STR R6,[R0,#OFFSET_SIGNALS]
    POP {R4-R7, PC}
