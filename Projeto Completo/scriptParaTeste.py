import os

# Defina aqui o caminho da pasta principal onde estão as subpastas de 0 a 9
diretorio_base = "src/dataset_teste"
arquivo_saida = "dataset.txt"

# Lista de extensões de imagens suportadas pela stb_image
extensoes_validas = (".png", ".jpg", ".jpeg")

# Limite máximo de imagens por dígito/classe
LIMITE_POR_CLASSE = 200

print(f"Iniciando a busca de imagens (limite de {LIMITE_POR_CLASSE} por classe) em: {diretorio_base}")

try:
    with open(arquivo_saida, "w", encoding="utf-8") as f:
        # Percorre as pastas de 0 a 9 de forma ordenada
        for classe in range(10):
            pasta_classe = os.path.join(diretorio_base, str(classe))
            
            # Verifica se a pasta do dígito existe
            if os.path.exists(pasta_classe):
                # Lista e ordena os arquivos dentro da pasta
                arquivos = sorted(os.listdir(pasta_classe))
                
                contador_pasta = 0
                for arquivo in arquivos:
                    # Se já atingiu o limite de 100 para esta classe, interrompe o loop da pasta
                    if contador_pasta >= LIMITE_POR_CLASSE:
                        break
                        
                    # Verifica se o arquivo é uma imagem suportada
                    if arquivo.lower().endswith(extensoes_validas):
                        # Monta o caminho completo do arquivo
                        caminho_completo = os.path.join(pasta_classe, arquivo)
                        
                        # Garante o uso de barras invertidas (\) exigido para o seu ambiente
                        caminho_formatado = caminho_completo.replace("/", "\\")
                        
                        # Escreve no arquivo: caminho_da_imagem classe
                        f.write(f"{caminho_formatado} {classe}\n")
                        contador_pasta += 1
                
                print(f"Pasta [{classe}]: {contador_pasta} imagens adicionadas.")
            else:
                print(f"Aviso: A pasta {pasta_classe} não foi encontrada.")

    print(f"\nSucesso! Arquivo '{arquivo_saida}' gerado com até {LIMITE_POR_CLASSE} imagens por número.")

except Exception as e:
    print(f"Erro ao gerar o arquivo: {e}")