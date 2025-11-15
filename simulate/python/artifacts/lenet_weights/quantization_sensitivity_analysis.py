import json
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

# =========================
# Step 1. 读取 manifest.json
# =========================
script_dir = Path(__file__).resolve().parent
manifest_path = script_dir / "manifest.json"

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

layers = manifest["layers"]

# =========================
# Step 2. 定义量化与余弦函数
# =========================
def quantize_dequantize(t, bits=8, per_channel=False):
    """
    模拟量化 + 反量化（INT8仿真）
    per_channel=True 时对卷积层的输出通道独立量化
    """
    t = t.astype(np.float32)
    qmin, qmax = -2 ** (bits - 1), 2 ** (bits - 1) - 1

    if not per_channel:
        scale = np.max(np.abs(t)) / qmax if np.max(np.abs(t)) > 0 else 1.0
        t_q = np.clip(np.round(t / scale), qmin, qmax)
        return t_q * scale

    # per-channel量化（针对卷积层输出通道）
    out_channels = t.shape[0]
    t_deq = np.zeros_like(t)
    for i in range(out_channels):
        w = t[i]
        scale = np.max(np.abs(w)) / qmax if np.max(np.abs(w)) > 0 else 1.0
        w_q = np.clip(np.round(w / scale), qmin, qmax)
        t_deq[i] = w_q * scale
    return t_deq


def cosine_similarity(a, b):
    """纯 numpy 实现余弦相似度"""
    a = a.flatten().astype(np.float64)
    b = b.flatten().astype(np.float64)
    dot = np.dot(a, b)
    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)
    return dot / (norm_a * norm_b + 1e-12)


# =========================
# Step 3. 层级误差分析
# =========================
mse_dict = {}
cos_dict = {}

for layer in layers:
    name = layer["name"]
    if "weight" not in name:
        continue  # 忽略 bias

    npy_path = script_dir / Path(layer["files"]["fp32_npy"]).name
    if not npy_path.exists():
        npy_path = Path(layer["files"]["fp32_npy"])
    arr = np.load(npy_path)

    # 判断卷积层与全连接层
    per_channel = (len(arr.shape) == 4)

    arr_q = quantize_dequantize(arr, bits=8, per_channel=per_channel)

    # 计算 MSE 与 Cosine
    mse = np.mean((arr - arr_q) ** 2)
    cos = cosine_similarity(arr, arr_q)

    mse_dict[name] = mse
    cos_dict[name] = cos

# =========================
# Step 4. 打印结果
# =========================
print("=== 层级量化敏感度分析结果 ===")
print(f"{'Layer':25s} {'MSE':>12s} {'CosineSim':>12s}")
for k in mse_dict.keys():
    print(f"{k:25s} {mse_dict[k]:12.6e} {cos_dict[k]:12.6f}")

# =========================
# Step 5. 可视化结果
# =========================
layers_list = list(mse_dict.keys())
mse_vals = np.array(list(mse_dict.values()))
cos_vals = np.array(list(cos_dict.values()))

plt.figure(figsize=(10,4))
plt.subplot(1,2,1)
plt.barh(layers_list, mse_vals, color='tomato')
plt.title("Layer-wise MSE (Quantization Error)")
plt.xlabel("MSE")
plt.gca().invert_yaxis()

plt.subplot(1,2,2)
plt.barh(layers_list, cos_vals, color='skyblue')
plt.title("Layer-wise Weight Cosine Similarity")
plt.xlabel("Cosine Similarity")
plt.gca().invert_yaxis()

plt.tight_layout()
plt.savefig("layerwise_quantization_sensitivity_npy.png")
plt.show()

print("\n✅ Analysis done. Figure saved as 'layerwise_quantization_sensitivity_npy.png'")