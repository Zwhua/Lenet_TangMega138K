import json
import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
from torchvision import datasets, transforms
from pathlib import Path

# =========================
# Step 1. 定义与训练一致的 LeNet
# =========================
class LeNet(nn.Module):
    def __init__(self):
        super(LeNet, self).__init__()
        self.conv1 = nn.Conv2d(1, 6, 5)
        self.conv2 = nn.Conv2d(6, 16, 5)
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.fc2 = nn.Linear(120, 84)
        self.fc3 = nn.Linear(84, 10)

    def forward(self, x):
        x = F.relu(self.conv1(x))
        x = F.max_pool2d(x, 2)
        x = F.relu(self.conv2(x))
        x = F.max_pool2d(x, 2)
        x = torch.flatten(x, 1)
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        x = self.fc3(x)
        return x

# =========================
# Step 2. 读取 manifest.json
# =========================
# 自动定位：脚本所在目录/manifest.json
script_dir = Path(__file__).resolve().parent
manifest_path = script_dir / "manifest.json"
if not manifest_path.exists():
    raise FileNotFoundError(f"未找到 manifest.json: {manifest_path}")

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

layers = manifest["layers"]

# =========================
# Step 3. 加载权重数据并打印统计信息
# =========================
weights_dict = {}
print("=== 权重统计信息 ===")
for layer in layers:
    name = layer["name"]
    npy_path = script_dir / Path(layer["files"]["fp32_npy"]).name  # 同目录下 float32/*.npy
    if not npy_path.exists():
        # 兼容 manifest 中可能包含相对路径
        npy_path = Path(layer["files"]["fp32_npy"])
    arr = np.load(npy_path)
    weights_dict[name] = torch.tensor(arr, dtype=torch.float32)
    print(f"\n[{name}] shape={arr.shape}")
    print(f"  mean: {arr.mean():.6f}  std: {arr.std():.6f}  min: {arr.min():.6f}  max: {arr.max():.6f}")

# =========================
# Step 4. 加载权重到模型
# =========================
model = LeNet()
sd = model.state_dict()
for k in sd.keys():
    if k in weights_dict:
        sd[k] = weights_dict[k]
    else:
        print(f"缺少参数: {k}")
model.load_state_dict(sd)
model.eval()

# =========================
# Step 5. 用一张 MNIST 图片测试推理
# =========================
transform = transforms.Compose([
    transforms.Resize((32, 32)),
    transforms.ToTensor(),
    transforms.Normalize((0.1307,), (0.3081,))
])
test_dataset = datasets.MNIST("./dataset", train=False, download=True, transform=transform)
test_loader = torch.utils.data.DataLoader(test_dataset, batch_size=1, shuffle=True)

images, labels = next(iter(test_loader))
with torch.no_grad():
    outputs = model(images)
    predicted = outputs.argmax(dim=1)

print("\n=== 推理验证结果 ===")
print(f"真实标签: {labels.item()} 预测标签: {predicted.item()}")
print("✅ 正确" if predicted.item() == labels.item() else "⚠️ 不匹配，检查训练脚本与此结构是否一致。")
