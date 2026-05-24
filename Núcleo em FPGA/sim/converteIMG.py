import os
from PIL import Image

def converter_png_para_quartus(caminho_png, bits=8):
    if not os.path.exists(caminho_png):
        print(f"Erro: Arquivo {caminho_png} não encontrado.")
        return

    # Abre a imagem e converte para escala de cinza ('L')
    img = Image.open(caminho_png).convert('L')
    
    # Redimensiona para 28x28 (padrão MNIST, resultando em 784 pixels)
    img = img.resize((28, 28))
    
    # Transforma os pixels em uma lista de números (0-255)
    pixels = list(img.getdata())
    
    base_name = os.path.splitext(os.path.basename(caminho_png))[0]
    depth = len(pixels)  # 784 para uma imagem 28x28

    # --- GERAR .MIF ---
    with open(f"{base_name}.mif", 'w') as f:
        # Cabeçalho obrigatório do Quartus
        f.write(f"WIDTH={bits};\n")
        f.write(f"DEPTH={depth};\n\n")
        f.write("ADDRESS_RADIX=UNS;\n")
        f.write("DATA_RADIX=HEX;\n\n")
        f.write("CONTENT BEGIN\n")
        
        for i, p in enumerate(pixels):
            # Formato: endereço : dado;
            f.write(f"    {i} : {p:02X};\n")
            
        f.write("END;\n")

    # --- GERAR .HEX ---
    with open(f"{base_name}.hex", 'w') as f:
        for p in pixels:
            f.write(f"{p:02X}\n")

    print(f"Sucesso! '{caminho_png}' -> {base_name}.mif e {base_name}.hex")

if __name__ == "__main__":
    # Certifique-se de que a pasta existe
    pasta_imagens = './9'
    if os.path.exists(pasta_imagens):
        for arquivo in os.listdir(pasta_imagens):
            if arquivo.endswith(".png"):
                converter_png_para_quartus(os.path.join(pasta_imagens, arquivo))
    else:
        print(f"Diretório {pasta_imagens} não encontrado.")

if __name__ == "__main__":
    pasta_imagens = './9'
    # Converte todas as imagens PNG da pasta
    for arquivo in os.listdir(pasta_imagens):
        if arquivo.endswith(".png"):
            converter_png_para_quartus(os.path.join(pasta_imagens, arquivo))
