import numpy as np
from pathlib import Path

def npy_to_mem(npy_path, mem_path):
    """
    将 NumPy 数组转换为 Verilog $readmemh 格式
    - int8:  输出 2 位十六进制 (00~ff)
    - int32: 输出 8 位十六进制 (00000000~ffffffff)
    """
    data = np.load(npy_path).flatten()
    print(f"Converting {npy_path}: shape={data.shape}, dtype={data.dtype}")
    
    with open(mem_path, "w") as f:
        for val in data:
            # 转为 Python int，避免 NumPy 类型溢出
            val_int = int(val)
            
            if data.dtype == np.int32:
                # 32-bit signed → unsigned hex (8 digits)
                unsigned = val_int & 0xFFFFFFFF
                f.write(f"{unsigned:08x}\n")
            else:
                # 8-bit signed → unsigned hex (2 digits)
                unsigned = val_int & 0xFF
                f.write(f"{unsigned:02x}\n")
    
    print(f"  → {mem_path} (lines: {len(data)})\n")

# 转换文件
script_dir = Path(__file__).parent
npy_dir = script_dir / ".numpy"

npy_to_mem(npy_dir / "input_image_int8.npy", script_dir / "input_image.mem")
npy_to_mem(npy_dir / "conv1_weight_int8.npy", script_dir / "conv1_weight.mem")
npy_to_mem(npy_dir / "conv1_bias_int8.npy", script_dir / "conv1_bias.mem")

print("✅ All .mem files generated successfully!")
