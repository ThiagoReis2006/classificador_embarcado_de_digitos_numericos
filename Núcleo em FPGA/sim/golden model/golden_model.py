import numpy as np
import os

# --- CONFIGURAÇÕES ---
Q_FRAC = 12 

def load_mif_image(filepath):
    pixels = []
    try:
        with open(filepath, 'r') as f:
            for line in f:
                if ':' in line and ';' in line:
                    hex_val = line.split(':')[1].split(';')[0].strip()
                    pixels.append(int(hex_val, 16))
        return np.array(pixels)
    except Exception as e:
        print(f"Erro ao ler MIF: {e}")
        return None

def sigmoid_pwl_fixed(x_q412):
    """Lógica exata do seu Verilog aplicada a um único valor"""
    NEG4 = -16384 # -4 * 2^12
    NEG2 = -8192  # -2 * 2^12
    POS2 =  8192  #  2 * 2^12
    POS4 =  16384 #  4 * 2^12
    
    x = int(x_q412)
    
    if x <= NEG4:
        return 0
    elif x < NEG2:
        return (x + 16384) >> 4
    elif x < POS2:
        return 2048 + (x >> 3)
    elif x < POS4:
        return 3072 + ((x - 8192) >> 4)
    else:
        return 4096

# Vetorizando a função para que o NumPy aceite arrays
sigmoid_v = np.vectorize(sigmoid_pwl_fixed)

def run_inference(image_pixels, model_data):
    # Carregar e converter para int64 para evitar overflow nas somas 
    W_in = model_data['W_in_q'].astype(np.int64)
    b = model_data['b_q'].astype(np.int64)
    beta = model_data['beta_q'].astype(np.int64)

    # 1. Normalização e Conversão Q4.12
    x_norm = image_pixels / 255.0
    x_q = np.round(x_norm * (2**Q_FRAC)).astype(np.int64)

    # 2. Camada Oculta 
    # Operação de produto escalar com o shift do Datapath 
    dot_in = np.dot(W_in, x_q) >> Q_FRAC
    h_pre = dot_in + b
    
    # 3. Ativação PWL (Agora usando a versão vetorizada)
    h_q = sigmoid_v(h_pre)

    # 4. Camada de Saída [cite: 54]
    y_q = np.dot(h_q, beta) >> Q_FRAC

    prediction = np.argmax(y_q)
    return prediction, y_q

# --- EXECUÇÃO ---
path_npz = 'model_elm_q.npz'
path_mif = 'imagem_4.mif'

if __name__ == "__main__":
    if not os.path.exists(path_npz):
        print(f"Erro: {path_npz} não encontrado.")
    else:
        model = np.load(path_npz, allow_pickle=True)
        pixels = load_mif_image(path_mif)
        
        if pixels is not None:
            pred, scores = run_inference(pixels, model)
            print(f"--- RESULTADO GOLDEN MODEL ---")
            print(f"Imagem: {path_mif}")
            print(f"Classe Predita: {pred}")
            print(f"Scores (y_q412): {scores}")