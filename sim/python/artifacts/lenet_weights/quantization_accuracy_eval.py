import json
import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
from torchvision import datasets, transforms
import matplotlib.pyplot as plt
from pathlib import Path
import warnings
warnings.filterwarnings("ignore", category=UserWarning)

# ----------------------------
# 1) 定义与训练一致的 LeNet
# ----------------------------
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

# ----------------------------
# 2) 读取 manifest 和权重
# ----------------------------
script_dir = Path(__file__).resolve().parent
manifest_path = script_dir / "manifest.json"
if not manifest_path.exists():
    raise FileNotFoundError("未找到 manifest.json")

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)
layers = manifest["layers"]

def load_fp32_model_from_manifest():
    model = LeNet()
    sd = model.state_dict()
    for layer in layers:
        name = layer["name"]                # e.g. 'conv1.weight'
        npy_path = script_dir / Path(layer["files"]["fp32_npy"]).name
        if not npy_path.exists():
            npy_path = Path(layer["files"]["fp32_npy"])
        arr = np.load(npy_path).astype(np.float32)
        sd[name] = torch.from_numpy(arr)
    model.load_state_dict(sd)
    model.eval()
    return model

# ----------------------------
# 3) 量化工具函数
# ----------------------------
def qdq_tensor_per_tensor(x: torch.Tensor, scale: float, qmin=-128, qmax=127):
    if scale == 0:
        return torch.zeros_like(x)
    q = torch.clamp(torch.round(x / scale), qmin, qmax)
    return q * scale

def qdq_weight_per_channel_conv(w: torch.Tensor, scales: torch.Tensor):
    # w: [OC, IC, KH, KW], scales: [OC]
    s = scales.view(-1, 1, 1, 1)
    q = torch.clamp(torch.round(w / s), -128, 127)
    return q * s

def qdq_weight_per_channel_linear(w: torch.Tensor, scales: torch.Tensor):
    # w: [OC, IC], scales: [OC]
    s = scales.view(-1, 1)
    q = torch.clamp(torch.round(w / s), -128, 127)
    return q * s

def fp16_round(x: torch.Tensor):
    return x.half().float()

# ----------------------------
# 4) 校准激活范围（计算每层输入激活的 scale）
# ----------------------------
def get_data_loaders(batch_size_eval=256, batch_size_calib=64, calib_batches=32):
    common_tf = transforms.Compose([
        transforms.Resize((32, 32)),
        transforms.ToTensor(),
        transforms.Normalize((0.1307,), (0.3081,))
    ])
    test_ds = datasets.MNIST("./dataset", train=False, download=True, transform=common_tf)
    test_loader = torch.utils.data.DataLoader(test_ds, batch_size=batch_size_eval, shuffle=False)
    calib_loader = torch.utils.data.DataLoader(test_ds, batch_size=batch_size_calib, shuffle=True)
    return test_loader, calib_loader, calib_batches

def calibrate_activation_scales(model: nn.Module, calib_loader, calib_batches=32):
    model.eval()
    act_max = { }  # per-layer input max abs
    handles = []

    def make_pre_hook(name):
        def hook(module, inputs):
            x = inputs[0].detach()
            m = float(x.abs().max().item())
            act_max[name] = max(act_max.get(name, 0.0), m)
        return hook

    # 需要校准的层
    modules = {
        "conv1": model.conv1,
        "conv2": model.conv2,
        "fc1": model.fc1,
        "fc2": model.fc2,
        "fc3": model.fc3,
    }
    for name, m in modules.items():
        handles.append(m.register_forward_pre_hook(make_pre_hook(name)))

    with torch.no_grad():
        it = iter(calib_loader)
        for _ in range(calib_batches):
            try:
                images, _ = next(it)
            except StopIteration:
                break
            _ = model(images)

    for h in handles:
        h.remove()

    act_scales = {}
    for name, m in act_max.items():
        # 对称量化 scale = max_abs / 127
        act_scales[name] = (m / 127.0) if m > 0 else 1.0
    return act_scales

def get_weight_scales(model: nn.Module):
    # 返回每层权重 per-channel scale
    w_scales = {}
    with torch.no_grad():
        w1 = model.conv1.weight.detach().abs().amax(dim=(1,2,3))  # [6]
        w2 = model.conv2.weight.detach().abs().amax(dim=(1,2,3))  # [16]
        wf1 = model.fc1.weight.detach().abs().amax(dim=1)         # [120]
        wf2 = model.fc2.weight.detach().abs().amax(dim=1)         # [84]
        wf3 = model.fc3.weight.detach().abs().amax(dim=1)         # [10]
        # scale = max_abs / 127
        w_scales["conv1"] = (w1 / 127.0).clamp(min=1e-8)
        w_scales["conv2"] = (w2 / 127.0).clamp(min=1e-8)
        w_scales["fc1"]   = (wf1 / 127.0).clamp(min=1e-8)
        w_scales["fc2"]   = (wf2 / 127.0).clamp(min=1e-8)
        w_scales["fc3"]   = (wf3 / 127.0).clamp(min=1e-8)
    return w_scales

# ----------------------------
# 5) 三种推理路径
# ----------------------------
def eval_fp32(model, test_loader):
    model.eval()
    correct = total = 0
    with torch.no_grad():
        for x, y in test_loader:
            logits = model(x)
            pred = logits.argmax(1)
            total += y.size(0)
            correct += (pred == y).sum().item()
    return 100.0 * correct / total

def eval_fp16_sim(model, test_loader):
    # 对权重和每层输入都做一次 FP16 舍入（再转回 FP32 计算）
    m = LeNet()
    sd = m.state_dict()
    base = model.state_dict()
    for k in sd.keys():
        sd[k] = fp16_round(base[k])
    m.load_state_dict(sd)
    m.eval()

    correct = total = 0
    with torch.no_grad():
        for x, y in test_loader:
            # 输入激活也做半精度舍入
            x = fp16_round(x)
            # 前向里，每层输入再做一次舍入
            x = fp16_round(F.relu(m.conv1(x)))
            x = F.max_pool2d(x, 2)
            x = fp16_round(F.relu(m.conv2(x)))
            x = F.max_pool2d(x, 2)
            x = torch.flatten(x, 1)
            x = fp16_round(F.relu(m.fc1(x)))
            x = fp16_round(F.relu(m.fc2(x)))
            logits = m.fc3(x)  # 输出不再量化
            pred = logits.argmax(1)
            total += y.size(0)
            correct += (pred == y).sum().item()
    return 100.0 * correct / total

def eval_int8_sim(model, test_loader, act_scales, w_scales):
    # 对“每层输入激活 + 权重(按输出通道)”做对称 INT8 假量化
    m = model  # 已经加载了 FP32 权重
    m.eval()
    correct = total = 0

    with torch.no_grad():
        # 预先假量化权重（一次即可）
        w1 = qdq_weight_per_channel_conv(m.conv1.weight, w_scales["conv1"])
        w2 = qdq_weight_per_channel_conv(m.conv2.weight, w_scales["conv2"])
        wf1 = qdq_weight_per_channel_linear(m.fc1.weight, w_scales["fc1"])
        wf2 = qdq_weight_per_channel_linear(m.fc2.weight, w_scales["fc2"])
        wf3 = qdq_weight_per_channel_linear(m.fc3.weight, w_scales["fc3"])

        for x, y in test_loader:
            # 输入到每层前做激活假量化
            x = qdq_tensor_per_tensor(x, act_scales["conv1"])
            x = F.conv2d(x, w1, m.conv1.bias, stride=1, padding=0)
            x = F.relu(x)
            x = qdq_tensor_per_tensor(x, act_scales["conv2"])
            x = F.max_pool2d(x, 2)

            x = F.conv2d(x, w2, m.conv2.bias, stride=1, padding=0)
            x = F.relu(x)
            x = qdq_tensor_per_tensor(x, act_scales["fc1"])
            x = F.max_pool2d(x, 2)

            x = torch.flatten(x, 1)
            x = F.linear(qdq_tensor_per_tensor(x, act_scales["fc1"]), wf1, m.fc1.bias)
            x = F.relu(x)
            x = F.linear(qdq_tensor_per_tensor(x, act_scales["fc2"]), wf2, m.fc2.bias)
            x = F.relu(x)
            logits = F.linear(qdq_tensor_per_tensor(x, act_scales["fc3"]), wf3, m.fc3.bias)

            pred = logits.argmax(1)
            total += y.size(0)
            correct += (pred == y).sum().item()

    return 100.0 * correct / total

# ----------------------------
# 6) 执行评估
# ----------------------------
if __name__ == "__main__":
    torch.manual_seed(0)
    np.random.seed(0)

    model_fp32 = load_fp32_model_from_manifest()
    test_loader, calib_loader, calib_batches = get_data_loaders()

    # 校准激活尺度（使用测试集子集做演示；真实流程建议用训练/校准集）
    act_scales = calibrate_activation_scales(model_fp32, calib_loader, calib_batches)
    w_scales = get_weight_scales(model_fp32)

    acc_fp32 = eval_fp32(model_fp32, test_loader)
    acc_fp16 = eval_fp16_sim(model_fp32, test_loader)
    acc_int8 = eval_int8_sim(model_fp32, test_loader, act_scales, w_scales)

    print(f"float32 精度: {acc_fp32:.2f}%")
    print(f"float16(权重+激活)仿真精度: {acc_fp16:.2f}%")
    print(f"int8(权重per-channel+激活per-tensor)仿真精度: {acc_int8:.2f}%")

    # 英文标签避免中文字体告警
    plt.figure(figsize=(6,4))
    ks = ["float32", "fp16(fake)", "int8(fake)"]
    vs = [acc_fp32, acc_fp16, acc_int8]
    plt.bar(ks, vs, color=['skyblue','orange','lightgreen'])
    for i, v in enumerate(vs):
        plt.text(i, v + 0.5, f"{v:.2f}%", ha='center')
    plt.title("LeNet accuracy under different quantization sims")
    plt.ylabel("Accuracy (%)")
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.tight_layout()
    plt.savefig(script_dir / "quantization_accuracy_comparison.png")
    plt.show()
