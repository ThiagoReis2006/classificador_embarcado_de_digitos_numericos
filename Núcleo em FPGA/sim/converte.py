import math
import os

def to_hex_twos_complement(val, bits):
    """Converte para hexadecimal em complemento de dois com preenchimento de zeros."""
    if val < 0:
        val = (1 << bits) + val
    # Calcula quantos caracteres hex são necessários (ex: 16 bits = 4 chars)
    hex_chars = math.ceil(bits / 4)
    return format(val, f'0{hex_chars}x').upper()

def generate_files(input_path, word_size=16):
    if not os.path.exists(input_path):
        print(f"Erro: Arquivo '{input_path}' não encontrado.")
        return

    # Extrai o nome do arquivo sem a extensão .txt
    base_name = os.path.splitext(input_path)[0]
    
    try:
        data = []
        with open(input_path, 'r') as f:
            for line in f:
                # Remove o marcador se existir e limpa espaços
                clean_line = line.split(']')[-1].strip()
                if clean_line:
                    data.append(int(clean_line))
    except ValueError as e:
        print(f"Erro ao processar números: {e}")
        return

    depth = len(data)
    
    # --- GERAÇÃO DO ARQUIVO .HEX ---
    hex_filename = f"{base_name}.hex"
    with open(hex_filename, 'w') as f:
        for val in data:
            f.write(to_hex_twos_complement(val, word_size) + '\n')
    
    # --- GERAÇÃO DO ARQUIVO .MIF ---
    mif_filename = f"{base_name}.mif"
    with open(mif_filename, 'w') as f:
        f.write(f"WIDTH={word_size};\n")
        f.write(f"DEPTH={depth};\n\n")
        f.write("ADDRESS_RADIX=UNS;\n")
        f.write("DATA_RADIX=HEX;\n\n")
        f.write("CONTENT BEGIN\n")
        for addr, val in enumerate(data):
            hex_val = to_hex_twos_complement(val, word_size)
            f.write(f"    {addr} : {hex_val};\n")
        f.write("END;\n")

    print(f"Arquivos gerados com sucesso: {hex_filename} e {mif_filename}")

if __name__ == "__main__":
    # Você pode alterar o nome do arquivo aqui ou passar como argumento
    arquivo_alvo = 'beta_q.txt' 
    generate_files(arquivo_alvo, word_size=16)