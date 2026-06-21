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
CFLAGS  = -Wall -Wextra -O2 -std=c99 -I$(INC_DIR) \
          -D_GNU_SOURCE -D_POSIX_C_SOURCE=199309L -D_DEFAULT_SOURCE

# Flags para assembly (com suporte a pré-processamento de macros/includes)
ASFLAGS = -x assembler-with-cpp -I$(INC_DIR)

# Flags de linkagem
LDFLAGS =
LDLIBS  = -lm -lrt

# Encontra os arquivos fontes com o caminho completo
SRCS_C = $(wildcard $(SRC_DIR)/*.c)
SRCS_S = $(wildcard $(ASM_DIR)/*.s)

# Mapeia os objetos para dentro da pasta obj/
OBJS_C = $(patsubst $(SRC_DIR)/%.c, $(OBJ_DIR)/%.o, $(SRCS_C))
OBJS_S = $(patsubst $(ASM_DIR)/%.s, $(OBJ_DIR)/%.o, $(SRCS_S))
OBJS   = $(OBJS_C) $(OBJS_S)

# Regra principal
all: $(TARGET)

# Linkagem final (LDLIBS no final, após os objetos)
$(TARGET): $(OBJS)
	@echo "Linkando o executável final: $@"
	$(CC) $(LDFLAGS) $^ -o $@ $(LDLIBS)
	@echo "Pronto!"

# Compilação dos arquivos C de src/ para obj/
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR)
	@echo "Compilando arquivo C: $<"
	$(CC) $(CFLAGS) -c $< -o $@

# Compilação dos arquivos Assembly de src/asm/ para obj/
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
