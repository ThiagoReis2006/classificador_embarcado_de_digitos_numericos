# Classificador Embarcado de Dígitos Numéricos
Implementação de um algoritmo em um circuito especializado em FPGA com desenvolvimento de driver Linux em Assembly e de uma aplicação em linguagem C para utilizar o algoritmo implementado na FPGA.

Disciplina: TEC 499 — MI Sistemas Digitais

Instituição: Universidade Estadual de Feira de Santana (UEFS)

Integrantes: Thiago Reis, Tairone Lima, Jean Carlos

Tutor: Wild Freitas

# Marco 1 — Co-processador ELM em FPGA

## 1. Definição do Problema

Este projeto implementa, em FPGA, um co-processador para inferência de uma rede neural baseada em Extreme Learning Machine (ELM). O sistema completo do problema é dividido em três partes: um núcleo classificador em FPGA, um driver Linux em ARM com acesso por MMIO e uma aplicação em C. Neste Marco 01, o foco é a construção e validação do IP de inferência em RTL, incluindo simulação e demonstração do funcionamento na placa DE1-SoC. A inferência da ELM foi tratada como uma sequência de quatro etapas: leitura da imagem de entrada, processamento da camada oculta, processamento da camada de saída e cálculo da predição por argmax. O problema especifica que a entrada é uma imagem em escala de cinza de 28×28 pixels, com 784 bytes, e que a saída é um dígito inteiro no intervalo [0,9].

## 2. Levantamento de Requisitos

O Marco 01 exige um coprocessador ELM em Verilog com arquitetura sequencial, contendo:

- FSM de controle.
- Datapath MAC (multiplica-acumula).
- Ativação aproximada (LUT ou piecewise linear).
- Argmax final. 
- Memórias para armazenamento dos dados.
- Banco de registradores.
- Representação em ponto fixo `Q4.12`.
- Estratégia clara para armazenamento e acesso a `W_in, b e β`.

Além disso, o enunciado exige para o repositório do Marco 01:

- RTL Verilog do IP `elm_accel`.
- Testbench com vetores de teste comparando com golden model.
- Diagrama de blocos do datapath e da FSM.
- Uso de recursos FPGA.
- Mapa preliminar de registradores.
- Scripts para automação dos testes.
- READ.ME com detalhamento da solução, ambiente, testes e análise dos resultados.

### E/S
- Receber imagem 28×28 pixels (784 bytes, 8 bits/pixel, escala de cinza).
- Calcular camada oculta: `h = sigmoid(W_in · x + b)`, com 128 neurônios.
- Calcular camada de saída: `y = β · h`, com 10 classes.
- Retornar a predição via `pred = argmax(y)` → inteiro 0..9.
- Sinalizar `busy`, `done` e `error` ao controlador externo.
- Expor contador de ciclos (`cycles`) para medição de desempenho.

---
## 2.1 Fundamentação Teórica

### Extreme Learning Machine (ELM)

A Extreme Learning Machine é um algoritmo de aprendizado para redes neurais de
camada única (Single Layer Feedforward Network — SLFN). Sua principal
característica é que os pesos da camada oculta (W_in) e os bias (b) são gerados
aleatoriamente e permanecem fixos durante todo o processo, sem necessidade de
ajuste iterativo. Apenas os pesos da camada de saída (β) são determinados
analiticamente, por meio da pseudoinversa de Moore-Penrose. Isso torna o
treinamento significativamente mais rápido que redes treinadas por
backpropagation, mantendo capacidade competitiva de generalização.

A inferência na ELM segue quatro estágios sequenciais:

1. **Leitura da entrada:** vetor x com 784 valores (imagem 28×28 pixels em
escala de cinza, normalizada para [0, 1]).
2. **Camada oculta:** `h = activation(W_in · x + b)`, onde W_in é uma matriz
128×784 e b é um vetor de 128 bias. A função de ativação utilizada é a sigmoide, aproximada em hardware por uma função linear por partes (PWL).
3. **Camada de saída:** `y = β · h`, onde β é uma matriz 10×128 que projeta os
128 neurônios ocultos nas 10 classes possíveis.
4. **Predição:** `pred = argmax(y)`, retornando o índice da classe com maior
ativação, correspondendo ao dígito reconhecido (0..9).

### Representação em Ponto Fixo Q4.12

Para implementação eficiente em FPGA, todos os valores são representados no
formato de ponto fixo Q4.12: 1 bit de sinal, 4 bits para a parte inteira e 12
bits para a parte fracionária, totalizando 16 bits. Nesse formato, o valor real
de um número é obtido dividindo o inteiro representado por 2¹² (4096).

Operações de multiplicação entre dois valores Q4.12 produzem um resultado em
Q8.24, sendo necessário um deslocamento aritmético de 12 bits à direita para
retornar ao formato Q4.12. Esse ajuste é realizado explicitamente no datapath
MAC do co-processador.

### Arquitetura do Co-processador

O co-processador segue uma arquitetura sequencial controlada por uma FSM
(Finite State Machine), composta pelos seguintes elementos:

- **FSM de controle:** coordena os estágios de carregamento de dados, computação
da camada oculta, ativação, computação da camada de saída e argmax.
- **Datapath MAC:** unidade de multiplicação e acumulação responsável pelos
produtos escalares W_in·x e β·h.
- **Ativação PWL:** aproximação linear por partes da função sigmoide.
- **Argmax:** circuito que percorre os 10 valores de saída e retorna o índice do
maior valor.
- **Memórias:** RAMs internas para armazenamento da imagem, pesos W_in,
bias b e pesos β.

### Interface Hardware-Software (MMIO)

A comunicação entre o processador ARM (HPS) e o co-processador na FPGA vai ser
realizada futuramente via Memory-Mapped I/O (MMIO), utilizando a bridge HPS-to-FPGA
disponível na plataforma DE1-SoC. Nesse modelo, registradores internos do
co-processador são mapeados em endereços do espaço de memória do ARM, permitindo
que o software controle o hardware por meio de leituras e escritas em memória
convencional, sem necessidade de protocolos de comunicação dedicados.

## 3. Ambiente de Desenvolvimento

### Software
| Ferramenta | Versão | Uso |
|:---|:---|:---|
| **Intel Quartus Prime** | 21.1 Lite | Síntese, place-and-route e análise de recursos. |
| **Icarus Verilog** | 12.0+ | Compilação e simulação funcional do código RTL. |
| **GTKWave** | 3.3+ | Visualização de formas de onda para depuração de sinais. |
| **Python** | 3.10+ | Geração de arquivos MIF/HEX e execução do Golden Model. |
| **NumPy** | 1.24+ | Validação matemática dos resultados de inferência. |

### Hardware

| Componente | Descrição |
|------------|-----------|
| DE1-SoC | Placa com Cyclone V (5CSEMA5F31C6) + ARM Cortex-A9 |
| USB-Blaster | Programação da FPGA via JTAG |


---


## Mapa Preliminar de Registradores para futura interface MMIO (Marco 02)

> Mapa preliminar para referência. A interface MMIO ainda **não está implementada** no Marco 01.
> Nesta etapa, o co-processador é controlado por uma interface compacta de bancada com switches e botões.
> No Marco 02, essa lógica será associada ao acesso via MMIO entre HPS e FPGA.

## 4. Mapa de Registradores (Preliminar)

A comunicação futura via MMIO (Memory-Mapped I/O) poderá utilizar os seguintes registradores para controle pelo processador ARM:

| Endereço Relativo | Nome         | Acesso | Descrição |
|:--:|:-------------|:-----:|:----------|
| `0x00` | `REG_CTRL`   | R/W | Registrador de controle da operação. No Marco 02, deverá concentrar os comandos de controle, como seleção da operação e disparo da execução. |
| `0x04` | `REG_STATUS` | R   | Status do coprocessador: bits de `BUSY`, `DONE`, `ERROR` e campo da predição atual. |
| `0x08` | `REG_ADDR`   | R/W | Endereço para acesso às memórias internas. Será usado para apontar posições de imagem, pesos, bias ou beta. |
| `0x0C` | `REG_WDATA`  | R/W | Dado de escrita para alimentação das memórias internas. |
| `0x10` | `REG_RESULT` | R   | Resultado final da inferência, correspondente à predição `pred`. |
| `0x14` | `REG_CYCLES` | R   | Contador de ciclos de clock da inferência, usado para métricas de latência. |
| `0x18` | `REG_DEBUG`  | R   | Registrador auxiliar de depuração para observação interna do hardware. |

---

## 4.1 Conjunto de Instruções (ISA)

O co-processador implementa **operações controladas por um opcode de 3 bits**.  
No **Marco 01**, essas operações são demonstradas por meio de uma **interface compacta de bancada com switches** e com o banco de registradores preliminar.  
No **Marco 02**, elas serão associadas a uma interface **MMIO**.

| Opcode | Mnemônico      | Código | Descrição |
|:------:|:---------------|:------:|:----------|
| `3'b000` | `NOP`          | 0 | Nenhuma operação. Mantém o estado atual do co-processador. |
| `3'b001` | `STORE_IMG`    | 1 | Armazena um pixel na memória de imagem no endereço especificado. **Na interface atual de bancada**, o dado manual é limitado a **3 bits (0 a 7)** e expandido internamente para 8 bits. A operação é bloqueada se `busy` ou `protect_inference` estiver ativo. |
| `3'b010` | `STORE_WEIGHT` | 2 | Armazena um peso `W_in` na memória de pesos no endereço especificado. **Na interface atual de bancada**, o dado manual de 3 bits é convertido por tabela para um valor reduzido em **Q4.12** antes da escrita. A operação é bloqueada se `busy` ou `protect_inference` estiver ativo. |
| `3'b011` | `STORE_BIAS`   | 3 | Armazena um valor de bias `b` na memória de bias no endereço especificado. **Na interface atual de bancada**, o dado manual de 3 bits é convertido por tabela para **Q4.12** antes da escrita. A operação é bloqueada se `busy` ou `protect_inference` estiver ativo. |
| `3'b100` | `START`        | 4 | Inicia o processamento da inferência com os dados atualmente carregados nas memórias. Ativa o sinal `busy` até a conclusão. |
| `3'b101` | `STATUS`       | 5 | Leitura do estado atual do co-processador. Retorna os bits `busy`, `done` e `error`, além do resultado da predição `(0..9)` codificado em 4 bits no campo `pred` do status. |
| `3'b110` | `STORE_BETA`   | 6 | Armazena um peso `β` na memória de saída no endereço especificado. **Na interface atual de bancada**, o dado manual de 3 bits é convertido por tabela para **Q4.12** antes da escrita. A operação é bloqueada se `busy` ou `protect_inference` estiver ativo. |
| `3'b111` | `RESERVADO`    | 7 | Opcode reservado para extensões futuras da interface. Na implementação atual, não é utilizado como instrução válida da ISA. |


---



## 5. Diagrama de Blocos

O diagrama de blocos do datapath e da FSM está disponível em [`docs/diagrama_blocos.svg`](hardware/docs/Datapah+FSM.drawio.svg).

![Diagrama de Blocos](hardware/docs/Datapah+FSM.drawio.svg)

## 6. Descrição do Funcionamento do Projeto

`img_ram.v`: Esta memória armazena os pixels da imagem de entrada que será classificada pela rede neural. Ela possui 784 posições (referente a uma imagem de 28x28 pixels), largura de dados de 8 bits e um barramento de endereço de 10 bits.

`w_in_ram.v`: É a maior memória do sistema, projetada para armazenar os pesos da camada de entrada da rede neural. Possui 100.352 palavras (que correspondem a 784 entradas multiplicadas por 128 neurônios), largura de 16 bits e requer um barramento de endereço de 17 bits.

`beta_ram.v`: Armazena os pesos da camada de saída, chamados de beta. Esta memória tem 1.280 palavras (128 neurônios ocultos vezes 10 classes de saída), largura de 16 bits e barramento de endereço de 11 bits.

`b_ram.v`: Responsável por armazenar os valores de bias (viés) da camada oculta. Contém 128 posições de memória, largura de dados de 16 bits e um barramento de endereço de 7 bits.

`fxp_mul_q412.v`: É um multiplicador de ponto fixo projetado para o formato Q4.12, que consiste em 1 bit de sinal, 3 bits inteiros e 12 bits fracionários. O módulo recebe dois operandos de 16 bits com sinal e realiza a multiplicação, gerando inicialmente um produto de 32 bits. Para manter a precisão e o formato Q4.12 na saída, ele descarta os 12 bits fracionários excedentes utilizando um deslocamento aritmético para a direita (>>> 12), o que preserva o bit de sinal.

`sigmoid_pwl_q412.v`: Implementa uma aproximação linear por partes (PWL - Piecewise Linear) da função de ativação sigmoide, otimizada para o formato de ponto fixo Q4.12. Ele recebe um valor acumulado de 32 bits e retorna um valor de ativação de 16 bits. A lógica divide a curva sigmoide em cinco regiões: valores de entrada muito baixos resultam em 0 ; valores muito altos resultam no limite máximo de 1.0 (representado como 4096) ; e o centro da curva possui uma região linear principal e duas rampas suaves de transição nas bordas.

`key_fall_pulse.v`: Um detector síncrono de borda de descida para os botões da placa. Como os botões físicos são ativos em zero (key_n), o módulo monitora o sinal de entrada usando um registrador de atraso de um ciclo de clock (key_n_d). Quando identifica a transição de solto para pressionado, ele emite um pulso limpo de apenas um ciclo de clock (pulse), garantindo que comandos manuais sejam executados apenas uma vez por clique.

`hex7seg_de1soc.v`: É um decodificador simples de hexadecimal para display de 7 segmentos. Ele recebe um valor de 4 bits (hex) e, através de uma instrução case, mapeia-o para o padrão correspondente de 7 bits (seg) que acende os LEDs corretos na placa para formar números de 0 a 9 e letras de A a F. Caso o valor seja inválido, o padrão padrão apaga todos os segmentos.

`elm_accel.v`: É o núcleo do processamento do sistema, um acelerador de inferência para uma rede neural Extreme Learning Machine (ELM). A rede possui uma camada oculta mapeando 784 entradas para 128 neurônios, e uma camada de saída que mapeia esses 128 neurônios para 10 classes finais. O módulo expõe portas para que os pesos, imagens e bias sejam gravados externamente nas memórias e emite um erro caso haja tentativa de gravação durante uma inferência ativa. Todo o processo é regido por uma Máquina de Estados Finitos (FSM) complexa que calcula resultados sequencialmente: carrega os biases , processa operações MAC (multiplicação e acumulação) da camada oculta iterando sobre os 784 pixels , aplica a função sigmoide combinacional , calcula a camada de saída e, por fim, aplica uma lógica de argmax para determinar qual das 10 classes obteve a maior pontuação de predição. Ao final, o módulo exibe a classe predita (pred) e o total de ciclos de clock gastos na inferência (cycles).

`de1soc_elm_top.v`: É o módulo Top-Level responsável por integrar o coprocessador ELM aos periféricos físicos e botões da placa de desenvolvimento DE1-SoC. Ele traduz sinais físicos de interruptores (SW) e botões (KEY) em comandos e dados para o acelerador elm_accel. Utilizando os interruptores, o usuário seleciona instruções (Opcodes) como carregar imagens, pesos ou iniciar uma inferência. Para facilitar o teste manual usando poucos botões, ele contém uma função interna (expand_q412_3b) que converte chaves de 3 bits em valores válidos de 16 bits de ponto fixo Q4.12. O top-level também mapeia exaustivamente as saídas do acelerador: LEDs vermelhos indicam busy (ocupado), done (concluído) e erros , enquanto seis displays de 7 segmentos mostram visualmente a predição da rede neural, códigos de status (D para concluído, B para em processamento, E para erro), quantidade de ciclos e os dados sendo inseridos.

## Mapeamento de Entradas e Saídas na Placa

| Elemento | Função |
|---------|--------|
| `KEY[0]` | Reset do sistema |
| `KEY[1]` | Executa a instrução configurada nos switches |
| `LEDR[0]` | Indica estado **busy** (processamento em andamento) |
| `LEDR[1]` | Indica estado **done** (inferência concluída) |
| `LEDR[2]` | Indica estado **error** |
| `LEDR[3]` | Indica proteção ativa (**protect_inference**) |
| `LEDR[6:4]` | Exibe o **opcode atual** |
| `LEDR[9:7]` | Exibe o **endereço atual** |
| `HEX0` | Exibe a predição (**pred**) |
| `HEX1` | Exibe o status do sistema |
| `HEX2` e `HEX3` | Exibem a parte baixa do contador de ciclos (**cycles**) |
| `HEX4` | Mostra o retorno visual da última instrução executada |
| `HEX5` | Mostra o valor bruto dos switches (**data_sw**) |

## 7. Instalação e Configuração do Ambiente

### Especificação do Hardware

Para a validação e testes do co-processador ELM, foi utilizada a plataforma de
desenvolvimento DE1-SoC, que integra um sistema SoC Altera Cyclone V. Esta
arquitetura heterogênea permite a cooperação entre processamento baseado em
software (ARM) e hardware reconfigurável (FPGA).

**Componentes Principais:**

- **FPGA:** Cyclone V 5CSEMA5F31C6
- **Lógica:** 32.070 ALMs (Adaptive Logic Modules)
- **Memória:** 3.971 Kbits de memória embarcada (M10K)
- **DSP:** 87 blocos de hardware para processamento digital de sinais
- **HPS:** Processador ARM Cortex-A9 Dual-Core
- **Interface de Programação:** USB-Blaster integrada para configuração via JTAG

**Periféricos de Interface Utilizados:**

- **Switches (SW[0-9]):** Utilizados para entrada manual de dados, opcodes e
ativação da proteção de escrita de memória.
- **Push-buttons (KEY[0-1]):** Mapeados para as funções de Reset do sistema e
pulso de execução de instruções.
- **Displays de 7 Segmentos (HEX0-5):** Utilizados para monitoramento em tempo
real da predição (argmax), estado da FSM (Busy/Done/Error) e contagem de ciclos
de performance.

---

### Configuração do Ambiente de Desenvolvimento

O processo de configuração do ambiente é dividido entre as ferramentas de síntese
de hardware e as ferramentas de validação por software.

**Requisitos de Software:**

- **Intel Quartus Prime Lite Edition (v21.1 ou superior):** Necessário para
síntese, place-and-route e geração do arquivo de programação (`.sof`) para a FPGA.
- **Golden Model e geração de vetores de teste (`.mif`/`.hex`):** Instale as
dependências com:

```bash
pip install numpy
pip install Pillow
```

**Procedimento de Configuração:**

**1. Clonagem do Repositório:**
```bash
git clone https://github.com/JeanDevBAh/elm_accel_project.git
```

**2. Programação da FPGA:**
1. Abra o projeto `.qpf` no Quartus Prime.
2. Execute a compilação completa para gerar o relatório de uso de recursos.
3. Conecte a placa DE1-SoC via USB e utilize o Programmer para carregar o
co-processador na FPGA.

## 8. Uso de Recursos FPGA



| Recurso | Utilizado | Disponível (Cyclone V) | % |
|---------|-----------|------------------------|---|
| LUTs | 1451 | 32.070 | ~4,5% |
| Flip-Flops | 2576 | 64.140 | ~4.0% |
| DSP Blocks | 2 | 87 | ~2.3% |
| M10K (BRAM) | 202 | 397 | ~50.8% |

---
## 9. Testes e Validação

### Scripts de Apoio

Os scripts utilizados para geração de vetores de teste e validação estão em `hardware/sim/`:

| Script | Descrição |
|--------|-----------|
| `converteIMG.py` | Converte imagens PNG 28×28 para arquivos `.hex/.mif` compatíveis com o testbench |
| `converte.py` | Converte os pesos do modelo (`.txt`) para arquivos `.mif`/`.hex` para inicialização das ROMs |
| `golden_model.py` | Executa a inferência ELM em Python e retorna a predição esperada |

### Golden Model

O `golden_model.py` serve como referência para validação do RTL. Ele replica 
exatamente a lógica de ativação implementada no Verilog — incluindo a aproximação 
PWL (piecewise linear) da sigmoide em ponto fixo Q4.12 — garantindo que qualquer 
divergência entre o resultado do hardware e o golden model indique um erro de 
implementação RTL, e não uma diferença de algoritmo.

### Fluxo de Validação

**1. Converter a imagem de teste:**
```bash
python3 converteIMG.py
```

**2. Gerar os arquivos de pesos:**
```bash
python3 converte.py
```

**3. Obter a predição esperada:**
```bash
python3 golden_model.py
```

**5. Comparar** o resultado obtido na inferência com a saída do golden model.

## 10. Análise dos Resultados

A validação do co-processador foi realizada comparando a predição gerada com a saída do `golden_model.py`,
que replica a mesma lógica de ativação PWL em ponto fixo Q4.12 implementada no RTL.

Os resultados demonstram comportamento satisfatório para a grande maioria dos vetores
de teste: o hardware produz a mesma predição que o golden model, confirmando a
corretude da implementação do datapath MAC, da ativação aproximada e do argmax.

### Comportamento em Imagens Ambíguas

Foi observado que para imagens com características visuais menos definidas — como
dígitos escritos de forma irregular, com ruído ou traços pouco nítidos — o co-processador
pode retornar uma predição incorreta. Esse comportamento, no entanto, **não representa
uma falha de implementação RTL**: a mesma imagem submetida ao `golden_model.py`
produz o mesmo resultado divergente, indicando que a limitação é inerente ao modelo
ELM e à aproximação da função de ativação em ponto fixo, e não a um erro de hardware.

Esse alinhamento entre hardware e golden model é o critério central de validação do
Marco 1: o co-processador é considerado correto quando sua saída coincide com a do
golden model para todos os vetores de teste fornecidos, independentemente de o modelo
acertar ou não o dígito real da imagem.

### Métricas

| Métrica | Valor |
|---|---|
| Ciclos médios por inferência | 610.580 (0x95114) |
| Frequência máxima de operação | 12,2ms por inferência |

## Referência

PATTERSON, David A.; HENNESSY, John L. Computer Organization and Design: The Hardware/Software Interface. ARM® Edition. San Francisco: Morgan Kaufmann, 2016.

---
