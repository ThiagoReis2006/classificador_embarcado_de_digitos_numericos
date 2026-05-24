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

---

# Marco 2 - Driver (Linux ARM - Assembly + C)

## Sumário

- [Visão Geral e Levantamento de Requisitos](#visão-geral-e-levantamento-de-requisitos)
- [Arquitetura do Sistema](#arquitetura-do-sistema)
- [Co-processador (FPGA)](#co-processador-fpga)
  - [Máquina de Estados (FSM)](#máquina-de-estados-fsm)
  - [Conjunto de Instruções (ISA)](#conjunto-de-instruções-isa)
  - [Formato dos Pacotes de 32 bits](#formato-dos-pacotes-de-32-bits)
  - [Memórias Internas](#memórias-internas)
  - [Registrador de Saída (`data_out`)](#registrador-de-saída-data_out)
  - [Módulo Top-Level e Integração HPS-FPGA](#módulo-top-level-e-integração-hps-fpga)
- [Driver em Assembly ARMv7](#driver-em-assembly-armv7)
  - [Mapeamento de Memória](#mapeamento-de-memória)
  - [Protocolo de Comunicação](#protocolo-de-comunicação)
  - [Funções Implementadas](#funções-implementadas)
- [API em C](#api-em-c)
- [Interface de Teste (`interface.c`)](#interface-de-teste-interfacec)
- [Estrutura de Arquivos (Abstração para Fins Didáticos)](#estrutura-de-arquivos-abstração-para-fins-didáticos)
- [Como Compilar e Executar](#como-compilar-e-executar)
- [Resultados Alcançados](#resultados-alcançados)
- [Referências](#referências)

---

## Visão Geral e Levantamento de Requisitos

Neste marco, o problema central consiste na integração do IP ao HPS (Hard Processor System). O desafio é estabelecer e validar a comunicação via Memory-Mapped I/O (MMIO) construindo um driver Linux com rotinas críticas em Assembly ARM. A solução deve ser capaz de inicializar o hardware, carregar os parâmetros da rede (pesos e bias), enviar uma imagem e gerenciar a inferência através de polling. Para atestar a estabilidade da conexão, a aplicação deve demonstrar o envio de uma imagem fixa e obter a classificação correta de forma estável e repetida, com métricas e resultados.

O Marco 02 exige a integração HW/Linux via Driver em Assembly para controle via MMIO, devendo permitir à aplicação:

- Inicializar o hardware.
- Enviar a imagem, os pesos e o bias para a FPGA.
- Iniciar a inferência.
- Aguardar a finalização através de *polling* (ou interrupção).
- Ler os resultados e as métricas.
- Garantir a estabilidade da comunicação (enviar 1 imagem fixa e obter classificação correta repetidamente).

Além disso, o enunciado exige para o repositório do Marco 02:

- Projeto Quartus integrando HPS e FPGA (bridges) com o IP mapeado.
- Driver Linux com rotinas críticas em Assembly ARM e API definida.
- Código Assembly comentado.
- Scripts para automação dos testes.
- READ.ME com detalhamento da solução, ambiente, testes e análise dos resultados.
  
---

## Arquitetura do Sistema

O sistema é dividido em três camadas bem definidas e essenciais para o funcionamento correto do projeto:

```
┌──────────────────────────────────────────────────────────────┐
│                     DE1-SoC (Cyclone V SoC)                  │
│                                                              │
│   ┌──────────────────────┐     ┌──────────────────────────┐  │
│   │         HPS          │     │           FPGA           │  │
│   │                      │     │                          │  │
│   │  ┌────────────────┐  │     │  ┌────────────────────┐  │  │
│   │  │  interface.c   │  │     │  │    CoProcessor     │  │  │
│   │  │       (C)      │  │     │  │    (FSM Geral)     │  │  │
│   │  └───────┬────────┘  │     │  └────────┬───────────┘  │  │
│   │          │           │     │           │              │  │
│   │  ┌───────▼────────┐  │     │  ┌────────▼───────────┐  │  │
│   │  │DriverAcelerador│  │     │  │    neural_unit     │  │  │
│   │  │   (Assembly)   │  │     │  │    (Inferência)    │  │  │
│   │  └───────┬────────┘  │     │  └────────┬───────────┘  │  │
│   │          │  MMAP     │     │           │              │  │
│   └──────────┼───────────┘     └───────────┼──────────────┘  │
│              │                             │                 │
│              └─────────── PIO Bridges ─────┘                 │
│                  (data_in / data_out / signals)              │
└──────────────────────────────────────────────────────────────┘
```

A comunicação entre HPS e FPGA é realizada por **três registradores PIO (Parallel I/O)** configurados via Platform Designer (Qsys), mapeados na região de endereçamento de periféricos da FPGA (`0xFF200000`):

| Registrador  | Offset  | Largura | Direção     | Função                                      |
|:-------------|:-------:|:-------:|:-----------:|:--------------------------------------------|
| `signals`    | `0x10`  | 3 bits  | HPS → FPGA  | Controle: `enable[0]`, `clr[1]`, `rst[2]`  |
| `data_in`    | `0x30`  | 32 bits | HPS → FPGA  | Pacote de instrução/dado                   |
| `data_out`   | `0x20`  | 32 bits | FPGA → HPS  | Resultado, flags de status, contador        |

---

## Co-processador (FPGA)

O módulo `CoProcessor` é o núcleo do acelerador. Ele recebe instruções de 32 bits pelo barramento `data_in`, executa operações de escrita em memórias internas e, quando acionado, atribui a inferência ao submódulo `neural_unit`, dentre outras funções.

### Máquina de Estados (FSM)

A máquina de estados do `CoProcessor` controla o recebimento das instruções enviadas pelo HPS, a escrita dos dados nas memórias internas e o início da inferência na unidade neural. Ela também é responsável por manter as flags de controle, como `busy`, `done` e `error`, além de contabilizar os ciclos de clock gastos durante a inferência.

## Máquina de Estados do CoProcessor

```text
 RST
  |
  v
+---------+
| ST_IDLE |
+---------+
     |
     | ENABLE && !BUSY
     v
+-----------+
| ST_DECODE |
+-----------+
   |     |       |
   |     |       +----------------+
   |     |                        |
   |     v                        v
   |   START             INSTRUÇÃO INVÁLIDA
   |     |                        |
   |     v                        v
   | +--------------+        +--------+
   | | ST_INFERENCE |        |  ERRO  |
   | +--------------+        +--------+
   |        |
   |        | DONE
   |        v
   |   +---------+
   |   | ST_IDLE |
   |   +---------+
   |
   | ESCRITA
   v
+-----------+
| ST_MEMORY |
+-----------+
     |
     | DONE
     v
+---------+
| ST_IDLE |
+---------+
```

### Estados da Máquina

| Estado | Função |
|---|---|
| `ST_IDLE` | Estado inicial e de espera. Aguarda o pulso do sinal `enable` para capturar uma nova instrução. Uma nova instrução só é aceita quando o co-processador não está ocupado, evitando sobrescrita ou captura incorreta de dados. |
| `ST_DECODE` | Decodifica a instrução recebida pelo barramento `data_in`. O opcode é obtido pelos bits menos significativos da palavra de entrada, em `data_in[2:0]`. Neste estado também ocorre a validação dos endereços usados nas operações de escrita. Caso um endereço ultrapasse o limite da memória correspondente ou a instrução seja inválida, a flag `error` é ativada. |
| `ST_MEMORY` | Executa operações de escrita nas memórias internas do co-processador, como memória de imagem, pesos, bias e beta. O estado só é finalizado quando a escrita é confirmada, garantindo que o dado foi armazenado corretamente antes do retorno ao estado de espera. |
| `ST_INFERENCE` | Inicia e controla a execução da inferência. Neste estado, o controle dos barramentos de memória é entregue à `neural_unit`, que passa a acessar os dados carregados previamente. O contador de ciclos é incrementado a cada clock enquanto a inferência estiver em execução. A máquina só retorna para `ST_IDLE` quando o sinal `inference_done` é ativado. |


### Conjunto de Instruções (ISA)

O co-processador possui um conjunto de 8 instruções, codificadas nos bits `[2:0]` do pacote de 32 bits:

| Código | Mnemônico             | Descrição                                                         |
|:------:|:----------------------|:------------------------------------------------------------------|
| `000`  | `STORE_IMG`           | Grava um pixel (8 bits) na memória de imagem                     |
| `001`  | `STORE_WEIGHTS_ADDR`  | Define o endereço na memória de pesos para a próxima escrita     |
| `010`  | `STORE_WEIGHTS_VALUE` | Grava o valor (16 bits) no endereço de pesos previamente setado  |
| `011`  | `STORE_BIAS`          | Grava um valor de bias (16 bits) na memória de bias              |
| `100`  | `STORE_BETA`          | Grava um valor de beta (16 bits) na memória de beta              |
| `101`  | `START`               | Dispara a inferência neural e transiciona para ST_INFERENCE       |
| `110`  | `STATUS`              | Leitura de status                                                |
| `111`  | `NOP`                 | Nenhuma operação                                                 |

> **Nota sobre pesos:** A gravação de um peso requer duas instruções consecutivas, o primeiro `STORE_WEIGHTS_ADDR` (que apenas armazena o endereço e volta ao idle), depois `STORE_WEIGHTS_VALUE` (que realmente grava o valor naquele endereço). Isso permite endereços de até 17 bits (100.352 entradas) sem comprometer o espaço do valor de 16 bits dentro de um único pacote de 32 bits.

### Formato dos Pacotes de 32 bits

Cada instrução é codificada em um único pacote de 32 bits enviado ao registrador `data_in`. O layout dos campos varia por instrução:

**STORE_IMG (`000`)**
```
  Bit:  31       21  20     13  12      3   2    0
        ┌──────────┬──────────┬──────────┬────────┐
        │ (não uso)│  pixel   │  endereço│  0 0 0 │
        │          │  [7:0]   │  [9:0]   │        │
        └──────────┴──────────┴──────────┴────────┘
```

**STORE_BIAS (`011`)**
```
  Bit:  31   26  25          10   9       3   2    0
        ┌──────┬──────────────┬────────────┬────────┐
        │(n/u) │  bias [15:0] │ endereço   │  0 1 1 │
        │      │              │  [6:0]     │        │
        └──────┴──────────────┴────────────┴────────┘
```

**STORE_BETA (`100`)**
```
  Bit:  31  30  29          14   13       3   2    0
        ┌────┬──────────────────┬──────────┬────────┐
        │(n/u│  beta [15:0]     │ endereço │  1 0 0 │
        │    │                  │  [10:0]  │        │
        └────┴──────────────────┴──────────┴────────┘
```

**STORE_WEIGHTS_ADDR (`001`)**
```
  Bit:  31   20  19                3   2    0
        ┌──────┬────────────────────┬────────┐
        │(n/u) │  endereço [16:0]   │  0 0 1 │
        └──────┴────────────────────┴────────┘
```

**STORE_WEIGHTS_VALUE (`010`)**
```
  Bit:  31   19  18                3   2    0
        ┌──────┬────────────────────┬────────┐
        │(n/u) │  peso [15:0]       │  0 1 0 │
        └──────┴────────────────────┴────────┘
```

**START (`101`)**, **STATUS (`110`)** e **NOP (`111`)** seguem o mesmo formato, onde os 29 bits restantes são ignorados pelo co-processador:
```
  Bit:  31                          3   2    0
        ┌────────────────────────────┬────────┐
        │         (ignorado)         │ opcode │
        └────────────────────────────┴────────┘
```

### Memórias Internas

Cada tipo de dado possui sua própria memória on-chip, instanciada como `lsu_controller` parametrizado para o dispositivo Cyclone V com tipo `AUTO` (o compilador Quartus seleciona entre M10K e MLAB). Todas operam com 3 ciclos de latência por operação.

| Memória  | Tamanho       | Largura | Capacidade Total | Conteúdo                                   |
|:---------|:-------------:|:-------:|:----------------:|:-------------------------------------------|
| `mem_img`    | 784 posições  | 8 bits  | ~784 B           | Pixels da imagem de entrada (28×28)        |
| `mem_bias`   | 128 posições  | 16 bits | ~256 B           | Vieses da camada oculta (128 neurônios)    |
| `mem_beta`   | 1.280 posições| 16 bits | ~2,5 KB          | Parâmetros beta da camada de saída (128×10)|
| `mem_weight` | 100.352 posições | 16 bits | ~196 KB       | Pesos W_in da camada de entrada (784×128)  |

Durante a inferência, o multiplexador de barramento transfere o controle de todos os sinais de enable e endereço das memórias para a `neural_unit`, que passa a ditar quais endereços ler em qual ordem.

### Registrador de Saída (`data_out`)

O HPS lê o resultado completo num único acesso ao registrador `data_out` de 32 bits:

```
  Bit:  31                    8   7    6      5       4      3    0
        ┌────────────────────────┬──┬──────┬──────┬───────┬──────────┐
        │  contador_ciclos[23:0] │0 │ erro │ busy │  done │  dígito  │
        │                        │  │      │      │       │  [3:0]   │
        └────────────────────────┴──┴──────┴──────┴───────┴──────────┘
```

| Campo              | Bits     | Descrição                                                   |
|:-------------------|:--------:|:------------------------------------------------------------|
| `dígito`           | `[3:0]`  | Dígito predito pela rede (0–9)                              |
| `fl_processor_done`| `[4]`    | Operação concluída com sucesso                              |
| `fl_processor_busy`| `[5]`    | Co-processador ocupado (aguardando conclusão)               |
| `fl_error`         | `[6]`    | Endereço inválido ou instrução desconhecida                 |
| *(reservado)*      | `[7]`    | Sempre 0                                                    |
| `contador_ciclos`  | `[31:8]` | Número de ciclos de clock consumidos pela inferência (24 bits) |

### Módulo Top-Level e Integração HPS-FPGA

O módulo `ghrd_top` integra todos os componentes da plataforma DE1-SoC. O co-processador é conectado diretamente ao clock de 50 MHz do sistema (`CLOCK_50`) e recebe seus três sinais de controle através do registrador PIO `signals`, gerenciado pelo subsistema `soc_system` (Platform Designer):

```verilog
CoProcessor u_cop (
    .clk           ( CLOCK_50   ),
    .rst           ( signals[2] ),
    .clr_operation ( signals[1] ),
    .enable        ( signals[0] ),
    .data_in       ( data_in    ),
    .data_out      ( data_out   )
);
```

O sinal de reset do co-processador (`signals[2]`) é independente do mecanismo de reset do HPS (`hps_fpga_reset_n`), permitindo que o "software" reinicialize o acelerador a qualquer momento sem afetar o restante do sistema.

---

## Driver em Assembly ARMv7

O arquivo `DriverAcelerador.s` implementa todas as funções de comunicação com o co-processador diretamente em Assembly ARMv7.

### Mapeamento de Memória

O acesso aos registradores PIO da FPGA é feito via `/dev/mem` e a chamada de sistema `mmap2`, que mapeia a página física `0xFF200000` no espaço de endereçamento virtual do processo em execução no HPS.

```
Endereço Físico Base (FPGA PIOs leves): 0xFF200000
Page offset para mmap2:                0xFF200  (endereço / 4096)
Tamanho do mapeamento:                 4096 bytes (1 página)
Permissões:                            PROT_READ | PROT_WRITE (flag 3)
Tipo de mapeamento:                    MAP_SHARED (flag 1)
```

A função `inicializar_hardware` retorna o ponteiro virtual resultante em `R0`, que é então passado como primeiro argumento (`base`) para todas as demais funções.

### Protocolo de Comunicação

Toda transação entre HPS e co-processador segue um protocolo de três fases:

```
1. ESCRITA:   STR R6, [R0, #OFFSET_DATA_IN]    → deposita o pacote no registrador data_in
2. PULSO:     BL pulsar_enable                 → sinaliza nova instrução (enable=1, depois 0)
3. POLLING:   BL loop_polling                  → aguarda done=1 ou error=1 em data_out
              BL clear_fpga                    → limpa os flags (clr=1, depois 0)
```

Dois mecanismos de espera são usados conforme o contexto:

- **`loop_polling`**: Lê `data_out` ciclicamente e retorna quando `fl_done` ou `fl_error` estiver setado. Usado após operações que produzem resultado (escrita em memória, inferência).
- **`aguardar_idle`**: Aguarda o bit `fl_busy` ser zerado. Usado entre as duas instruções de envio de peso (`STORE_WEIGHTS_ADDR` → `STORE_WEIGHTS_VALUE`), onde o primeiro pacote não gera `done` — apenas registra o endereço e retorna ao idle.

### Funções Implementadas

#### `inicializar_hardware` → `volatile uint32_t*`
Abre `/dev/mem` via syscall `open`, em seguida chama `mmap2` para mapear a página física da FPGA. Retorna o ponteiro virtual em `R0`.

#### `resetar_fpga(base)`
Escreve `BIT_RESET` (bit 2 de `signals`) e em seguida escreve zero, gerando um pulso de reset síncrono. Reinicializa completamente a FSM e todos os registradores internos do co-processador.

#### `clear_fpga(base)`
Pulsa `BIT_CLEAR` (bit 1 de `signals`). Limpa os flags `fl_processor_done` e `fl_error` sem afetar os dados nas memórias internas, preparando o co-processador para aceitar a próxima instrução.

#### `enviarImagem(base, buffer)`
Itera sobre os 784 pixels do buffer de entrada (`uint8_t[784]`). Para cada pixel, monta o pacote `STORE_IMG` com o endereço (iterador) nos bits `[12:3]` e o valor do pixel nos bits `[20:13]`, envia, espera o `done` e limpa o flag.

```
pacote = (endereco << 3) | (pixel << 13) | 0b000
```

#### `enviarBias(base, buffer)`
Itera sobre 128 valores de bias (`int16_t[128]`). Monta o pacote `STORE_BIAS` com o endereço nos bits `[9:3]` e o valor de 16 bits nos bits `[25:10]`.

```
pacote = 0b011 | (endereco << 3) | (bias << 10)
```

#### `enviarBeta(base, buffer)`
Itera sobre 1.280 valores beta (`int16_t[1280]`). Monta o pacote `STORE_BETA` com o endereço nos bits `[13:3]` e o valor nos bits `[29:14]`.

```
pacote = 0b100 | (endereco << 3) | (beta << 14)
```

#### `enviarPesos(base, buffer)`
Itera sobre 100.352 pesos (`int16_t[100352]`). Para cada peso, são enviadas **duas instruções consecutivas**:

1. **Pacote de endereço** (`STORE_WEIGHTS_ADDR`): `0b001 | (endereco << 3)` — espera apenas `aguardar_idle`.
2. **Pacote de valor** (`STORE_WEIGHTS_VALUE`): `0b010 | (peso << 3)` — espera `loop_polling` e limpa.

Essa separação é necessária porque o endereço de 17 bits não caberia junto com o valor de 16 bits em um único pacote de 32 bits sem que houvesse sobreposição de campos.

#### `iniciar_inferencia(base)` → `int`
Envia o pacote `START` (`0b101`), pulsa enable e bloqueia em `loop_polling` até `fl_done`. Retorna o conteúdo completo de `data_out` diretamente para o C, que extrai o dígito, as flags e o contador de ciclos por deslocamentos de bits.

---

## API em C

O arquivo `APIdriverFPGA.h` declara os protótipos das funções Assembly, tornando-as acessíveis a qualquer programa C compilado junto com o objeto Assembly:

```c
volatile uint32_t* inicializar_hardware(void);
void enviarImagem   (volatile uint32_t *base, const uint8_t  *buffer);
void enviarPesos    (volatile uint32_t *base, const uint16_t *buffer);
void enviarBias     (volatile uint32_t *base, const uint16_t *buffer);
void enviarBeta     (volatile uint32_t *base, const uint16_t *buffer);
int  iniciar_inferencia(volatile uint32_t *base);
void resetar_fpga   (volatile uint32_t *base);
void clear_fpga     (volatile uint32_t *base);
```

O uso de `volatile uint32_t*` é essencial: garante que o compilador C não otimize (em cache ou reordene) os acessos a esses endereços, que correspondem a registradores de hardware com efeitos colaterais imediatos.

---

## Interface de Teste (`interface.c`)

O arquivo `interface.c` demonstra o fluxo completo de utilização do acelerador:

```
inicializar_hardware()
        │
        ▼
resetar_fpga()          ← estado limpo e conhecido
        │
        ▼
enviarBias()            ← 128 valores × 16 bits
enviarBeta()            ← 1.280 valores × 16 bits
enviarPesos()           ← 100.352 valores × 16 bits
        │
        ▼ (loop de testes)
enviarImagem()          ← 784 pixels × 8 bits
        │
        ▼
iniciar_inferencia()    ← retorna data_out compactado
        │
        ▼
Extração dos campos:
  resultado      = retorno & 0x0F
  done           = (retorno >> 4) & 1
  busy           = (retorno >> 5) & 1
  erro           = (retorno >> 6) & 1
  contador_clock = (retorno >> 8) & 0xFFFFFF
```

Os pesos, biases e betas são carregados apenas **uma vez** antes do loop de inferências, refletindo o comportamento real de um sistema embarcado: os parâmetros da rede são fixos e permanecem nas memórias do co-processador durante toda a sessão. Apenas a imagem de entrada é substituída a cada nova inferência.

---

## Estrutura de Arquivos (Abstração para Fins Didáticos)

```
.
├── hardware/
│   ├── ghrd_top.v            # Módulo top-level da DE1-SoC; integra HPS e co-processador
│   └── CoProcessor.v         # Co-processador neural: FSM, memórias, neural_unit
│
├── "software"/
│   ├── DriverAcelerador.s    # Driver de baixo nível em Assembly ARMv7
│   ├── APIdriverFPGA.h       # Declarações C das funções Assembly
│   ├── interface.c           # Programa principal de teste
│   ├── pesos.h               # Pesos, biases e betas da rede neural (vetores C)
│   └── dados_imagem.h        # Imagens de teste do MNIST (dígitos 4, 7, 8, 9)
```

---

## Como Compilar e Executar

### Pré-requisitos

- Acesso SSH à DE1-SoC com Linux rodando no HPS.
- Bitstream da FPGA já gravado com o Platform Designer configurado (PIOs `data_in`, `data_out`, `signals` no endereço `0xFF200000`).
- `gcc` disponível nativamente na placa.

### Compilação e Execução (diretamente na DE1-SoC)

Conecte-se à placa via SSH e eleve seus privilégios através do `sudo su`:

```bash
ssh <usuario>@<IP_DA_PLACA>
sudo su
```

Compile e execute:

```bash
gcc DriverAcelerador.s interface.c -o driver
./driver
```

### Saída Esperada

```
Resetando hardware...
Enviando Bias...
Enviando Betas...
Enviando W_in...

--- Iniciando Execução 0 ---
Enviando imagem...
Iniciando inferência...
 | Resultado: 4
 | Erro: 0
 | Ciclos de clock: XXXX
 | Done: 1
```
### Linguagens

| Linguagem | Uso |
|:----------|:----|
| **Verilog** | Descrição do co-processador e módulo top-level em HDL |
| **Assembly ARMv7** | Driver de baixo nível para comunicação com a FPGA |
| **C** | Interface de teste e API do driver |

### Software
| Ferramenta | Uso |
|:---|:---|
| **Intel Quartus Prime 21.1 Lite** | Síntese, place-and-route e análise de recursos. |
| **GCC (ARM nativo)** | Compilação do driver Assembly e da interface C diretamente na DE1-SoC. |
| **OpenSSH** | Acesso remoto à placa para transferência de arquivos, compilação e execução. |

### Hardware

| Componente | Descrição |
|:-----------|:----------|
| **DE1-SoC** | Placa com FPGA Cyclone V (5CSEMA5F31C6) + ARM Cortex-A9 (HPS) |

## Resultados Alcançados

### Correção da Classificação

O acelerador foi validado com quatro amostras do dataset MNIST disponíveis em `dados_imagem.h`, representando os dígitos **4**, **7**, **8** e **9** como vetores `uint8_t[784]` de pixels em escala de cinza (0–255). Para cada imagem, o campo `resultado` de `data_out[3:0]` deve retornar exatamente o dígito correspondente, e o flag `fl_error` deve permanecer em zero, confirmando que nenhum endereço inválido foi gerado durante o carregamento.

O programa de teste em `interface.c`, na configuração atual, executa a inferência sobre `imagem4` e imprime o resultado diretamente no terminal via SSH. A estrutura de loop permite ampliar facilmente o número de inferências e alternar entre as imagens disponíveis.

### Desempenho e Contador de Ciclos

O co-processador opera a **50 MHz** (período de clock de 20 ns), e o campo `contador_ciclos` de 24 bits em `data_out[31:8]` registra com precisão de um ciclo o tempo decorrido exclusivamente durante a fase de inferência do momento em que a `neural_unit` é ativada até o sinal `inference_done`.
Para contextualizar a escala do problema computacional resolvido em hardware:

| Etapa                        | Operações envolvidas                          |
|:-----------------------------|:----------------------------------------------|
| Carregamento da imagem       | 784 escritas de 8 bits                        |
| Carregamento dos pesos W_in  | 100.352 escritas de 16 bits (2 pacotes cada)  |
| Carregamento do bias         | 128 escritas de 16 bits                       |
| Carregamento do beta         | 1.280 escritas de 16 bits                     |

O carregamento dos parâmetros (pesos, bias, beta) é realizado **uma única vez** por sessão e a partir da segunda inferência em diante, o ciclo se reduz ao envio da imagem (784 pacotes) seguido da execução em hardware, tornando o sistema altamente eficiente para cenários de inferência repetida.

### Flags de Status

| Flag           | Valor esperado | Significado                                                        |
|:---------------|:--------------:|:-------------------------------------------------------------------|
| `fl_done`      | `1`            | Operação concluída com sucesso                                     |
| `fl_error`     | `0`            | Nenhum endereço inválido detectado durante o carregamento          |
| `fl_busy`      | `0`            | Co-processador liberado ao término (retornou a ST_IDLE)            |

Caso `fl_error` seja `1`, a causa mais provável é um índice fora dos limites em uma das funções de envio, por exemplo, tentar escrever além das 784 posições da memória de imagem ou além das 128 posições de bias. A FSM cancela a operação e retorna ao idle sem corromper os dados já gravados.


## Referências

PATTERSON, David A.; HENNESSY, John L. Computer Organization and Design: The Hardware/Software Interface. ARM® Edition. San Francisco: Morgan Kaufmann, 2016.

---
