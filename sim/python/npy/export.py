#!/usr/bin/env python3
import numpy as np
from pathlib import Path

script_dir = Path(__file__).resolve().parent
npy_dir    = script_dir / ".numpy"

input_path  = npy_dir / "input_image_int8.npy"
weight_path = npy_dir / "conv1_weight_int8.npy"
bias_path   = npy_dir / "conv1_bias_int8.npy"

def format_c_array_int(vals, c_type, name, per_line=16):
    vals = [int(v) for v in vals]  # 转成 Python int
    lines = []
    line = []
    for i, v in enumerate(vals):
        line.append(str(v))
        if (i + 1) % per_line == 0:
            lines.append(", ".join(line))
            line = []
    if line:
        lines.append(", ".join(line))

    body = ",\n    ".join(lines)
    return f"static const {c_type} {name}[{len(vals)}] = {{\n    {body}\n}};\n"

def main():
    # 输入图像 int8
    inp = np.load(input_path).astype(np.int8).flatten()
    # 权重 int8
    w   = np.load(weight_path).astype(np.int8).flatten()
    # bias 这里是 int8 量化过的，你在 C 里是 int32_t，这里直接提升为 int32
    b   = np.load(bias_path).astype(np.int32).flatten()

    print("// ===== Auto-generated from .npy by export_npy_to_c_arrays.py =====")
    print("#include <stdint.h>\n")
    print("// input_data: int8, length =", len(inp))
    print(format_c_array_int(inp,  "int8_t",  "input_data"))
    print("// weight_data: int8, length =", len(w))
    print(format_c_array_int(w,    "int8_t",  "weight_data"))
    print("// bias_data: int32, length =", len(b))
    print(format_c_array_int(b,    "int32_t", "bias_data"))

if __name__ == "__main__":
    main()