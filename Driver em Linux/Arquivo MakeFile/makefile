# Nome do executável final
TARGET = driver_fpga

# Compilador e Assembler para ARMv7
CC = gcc
AS = gcc

# Diretórios
INC_DIR = include
SRC_DIR = src
ASM_DIR = src/asm
OBJ_DIR = obj

# Flags de compilação
CFLAGS = -Wall -Wextra -O2 -I$(INC_DIR)
ASFLAGS = -I$(INC_DIR)

# Encontra os arquivos fontes com o caminho completo
SRCS_C = $(wildcard $(SRC_DIR)/*.c)
SRCS_S = $(wildcard $(ASM_DIR)/*.s)

# Mapeia os objetos para dentro da pasta obj/ mantendo a estrutura original
OBJS_C = $(patsubst $(SRC_DIR)/%.c, $(OBJ_DIR)/%.o, $(SRCS_C))
OBJS_S = $(patsubst $(ASM_DIR)/%.s, $(OBJ_DIR)/%.o, $(SRCS_S))
OBJS   = $(OBJS_C) $(OBJS_S)

# Regra principal
all: $(TARGET)

# Linkagem final
$(TARGET): $(OBJS)
	@echo "Linkando o executável final: $@"
	$(CC) $(CFLAGS) $^ -o $@
	@echo "Pronto!"

# Regra CORRIGIDA para os arquivos C de src/ para obj/
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR)
	@echo "Compilando arquivo C: $<"
	$(CC) $(CFLAGS) -c $< -o $@

# Regra CORRIGIDA para os arquivos Assembly de src/asm/ para obj/
$(OBJ_DIR)/%.o: $(ASM_DIR)/%.s | $(OBJ_DIR)
	@echo "Compilando arquivo Assembly: $<"
	$(AS) $(ASFLAGS) -c $< -o $@

# Cria a pasta de objetos se ela não existir
$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

# Limpa os arquivos gerados
clean:
	@echo "Limpando arquivos gerados..."
	rm -rf $(OBJ_DIR) $(TARGET)

.PHONY: all clean