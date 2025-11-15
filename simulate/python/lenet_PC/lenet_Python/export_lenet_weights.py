import argparse
import json
import os
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

# 定义与训练一致的 LeNet 结构（结构名与参数名需一致）
class LeNet(nn.Module):
    def __init__(self):
        super(LeNet, self).__init__()
        self.conv1 = nn.Conv2d(1, 6, 5)
        self.relu = nn.ReLU()
        self.maxpool1 = nn.MaxPool2d(2, 2)
        self.conv2 = nn.Conv2d(6, 16, 5)
        self.maxpool2 = nn.MaxPool2d(2, 2)
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.fc2 = nn.Linear(120, 84)
        self.fc3 = nn.Linear(84, 10)

    def forward(self, x):
        x = self.conv1(x); x = self.relu(x); x = self.maxpool1(x)
        x = self.conv2(x); x = self.relu(x); x = self.maxpool2(x)
        x = x.view(-1, 16 * 5 * 5)
        x = F.relu(self.fc1(x)); x = F.relu(self.fc2(x))
        x = self.fc3(x)
        return x

def quantize_int8_symmetric(arr: np.ndarray):
    max_abs = float(np.max(np.abs(arr)))
    if max_abs == 0.0:
        scale = 1.0
        q = np.zeros_like(arr, dtype=np.int8)
    else:
        scale = max_abs / 127.0
        q = np.clip(np.round(arr / scale), -128, 127).astype(np.int8)
    return q, scale

def main():
    parser = argparse.ArgumentParser(description="Export LeNet weights/biases to npy/bin with manifest.")
    parser.add_argument("--weights", type=str, default="lenet_mnist.pth", help="模型参数文件路径（state_dict）")
    parser.add_argument("--out", type=str, default="artifacts/lenet_weights", help="导出目录")
    parser.add_argument("--formats", nargs="+", default=["npy", "bin"], choices=["npy", "bin", "txt"], help="导出格式")
    parser.add_argument("--quantize", type=str, default="none", choices=["none", "int8"], help="是否导出 INT8 量化权重（偏置保持 FP32）")
    args = parser.parse_args()

    out_dir = Path(args.out)
    (out_dir / "float32").mkdir(parents=True, exist_ok=True)
    if args.quantize == "int8":
        (out_dir / "int8").mkdir(parents=True, exist_ok=True)

    # 加载模型与参数
    device = torch.device("cpu")
    model = LeNet().to(device)
    ckpt = torch.load(args.weights, map_location=device)
    # 支持两种保存方式：直接 state_dict 或 {'state_dict': ...}
    state_dict = ckpt["state_dict"] if isinstance(ckpt, dict) and "state_dict" in ckpt else ckpt
    model.load_state_dict(state_dict)

    manifest = {
        "model": "LeNet",
        "dtype": "float32",
        "quantize": args.quantize,
        "layers": []
    }

    # 导出所有参数（权重与偏置）
    for name, tensor in model.named_parameters():
        arr = tensor.detach().cpu().numpy().astype(np.float32)
        safe_name = name.replace(".", "_")
        entry = {
            "name": name,
            "safe_name": safe_name,
            "shape": list(arr.shape),
            "files": {}
        }

        # FP32 导出
        if "npy" in args.formats:
            np.save(out_dir / "float32" / f"{safe_name}.npy", arr)
            entry["files"]["fp32_npy"] = str((out_dir / "float32" / f"{safe_name}.npy").as_posix())
        if "bin" in args.formats:
            arr.astype("<f4").tofile(out_dir / "float32" / f"{safe_name}.bin")
            entry["files"]["fp32_bin"] = str((out_dir / "float32" / f"{safe_name}.bin").as_posix())
        if "txt" in args.formats:
            # 文本仅用于查看，保持原始形状逐行展开
            with open(out_dir / "float32" / f"{safe_name}.txt", "w", encoding="utf-8") as f:
                f.write("# shape: " + "x".join(map(str, arr.shape)) + "\n")
                f.write(" ".join(map(str, arr.flatten().tolist())) + "\n")
            entry["files"]["fp32_txt"] = str((out_dir / "float32" / f"{safe_name}.txt").as_posix())

        # INT8 对称量化（仅对 weight 张量，bias 仍导出 FP32）
        if args.quantize == "int8" and name.endswith("weight"):
            q, scale = quantize_int8_symmetric(arr)
            q.tofile(out_dir / "int8" / f"{safe_name}.bin")
            np.save(out_dir / "int8" / f"{safe_name}.npy", q)
            entry["int8"] = {
                "scale": scale,
                "files": {
                    "int8_bin": str((out_dir / "int8" / f"{safe_name}.bin").as_posix()),
                    "int8_npy": str((out_dir / "int8" / f"{safe_name}.npy").as_posix())
                }
            }

        manifest["layers"].append(entry)

    # 写 manifest.json
    with open(out_dir / "manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    print(f"导出完成，目录: {out_dir.resolve()}")
    print("包含层参数:", ", ".join(l['name'] for l in manifest["layers"]))

if __name__ == "__main__":
    main()