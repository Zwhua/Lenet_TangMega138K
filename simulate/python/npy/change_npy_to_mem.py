import numpy as np

def npy_to_mem(npy_path, mem_path):
    data = np.load(npy_path).flatten()
    with open(mem_path, "w") as f:
        for val in data:
            f.write(f"{val & 0xFF:02x}\n")

npy_to_mem("input_image_int8.npy", "input_image.mem")
npy_to_mem("conv1_weight_int8.npy", "conv1_weight.mem")
npy_to_mem("conv1_bias_int8.npy", "conv1_bias.mem")
