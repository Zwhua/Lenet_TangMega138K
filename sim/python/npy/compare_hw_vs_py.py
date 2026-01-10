import numpy as np
from pathlib import Path
import argparse

script_dir = Path(__file__).resolve().parent
mem_input  = script_dir / "input_image.mem"
mem_weight = script_dir / "conv1_weight.mem"
mem_bias   = script_dir / "conv1_bias.mem"
hw_txt     = script_dir / "hw_conv1_out.txt"
ref_npy    = script_dir / "ref_conv1_out.npy"   # float32 参考（可选）

def read_mem_signed(path: Path, width_bits: int):
    if not path.exists():
        raise FileNotFoundError(f"mem not found: {path}")
    vals = []
    with open(path, "r") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("//"):
                continue
            try:
                v = int(s, 16)   # $readmemh 十六进制
            except ValueError:
                v = int(s, 10)   # 兼容十进制
            if width_bits > 0:
                sign_bit = 1 << (width_bits - 1)
                mask = (1 << width_bits) - 1
                v &= mask
                if v & sign_bit:
                    v -= (1 << width_bits)
            vals.append(v)
    return np.array(vals, dtype=np.int64)

def infer_shapes(inp_len, w_len, b_len, in_ch=1):
    OUT_CH = b_len
    per_oc = w_len // OUT_CH
    # 猜 K（常见 3/5/7/9）
    K = None
    for cand in [1, 3, 5, 7, 9, 11]:
        if per_oc % (cand*cand) == 0 and (per_oc // (cand*cand)) == in_ch:
            K = cand
            break
    if K is None:
        K = int(round(np.sqrt(per_oc // in_ch)))
    IN_SIZE = int(round(np.sqrt(inp_len // in_ch)))
    OUT_SIZE = IN_SIZE - K + 1
    return OUT_CH, K, IN_SIZE, OUT_SIZE

def compare_int32():
    inp_q = read_mem_signed(mem_input, 8)
    w_q   = read_mem_signed(mem_weight, 8)
    b_q   = read_mem_signed(mem_bias, 32)
    hw    = np.loadtxt(hw_txt, dtype=np.int64)
    OUT_CH, K, IN_SIZE, OUT_SIZE = infer_shapes(len(inp_q), len(w_q), len(b_q), in_ch=1)

    inp_q = inp_q.reshape(1, IN_SIZE, IN_SIZE)
    w_q   = w_q.reshape(OUT_CH, 1, K, K)

    out_ref = np.zeros((OUT_CH, OUT_SIZE, OUT_SIZE), dtype=np.int64)
    for oc in range(OUT_CH):
        for i in range(OUT_SIZE):
            for j in range(OUT_SIZE):
                acc = np.int64(0)
                for m in range(K):
                    for n in range(K):
                        acc += np.int64(inp_q[0, i+m, j+n]) * np.int64(w_q[oc, 0, m, n])
                acc += np.int64(b_q[oc])
                out_ref[oc, i, j] = acc

    hw = hw.flatten()
    out_ref = out_ref.flatten()
    m = min(hw.size, out_ref.size)
    hw, out_ref = hw[:m], out_ref[:m]

    diff = hw - out_ref
    mse = np.mean(diff.astype(np.float64)**2)
    l1  = np.mean(np.abs(diff))
    eq  = float(np.sum(diff==0))/m
    cos = np.dot(hw, out_ref) / (np.linalg.norm(hw)*np.linalg.norm(out_ref) + 1e-12)

    print("=== Conv1 HW vs Python (INT32 domain) ===")
    print(f"shape: {m}, OUT_CH={OUT_CH}, K={K}, OUT_SIZE={OUT_SIZE}")
    print(f"MSE   : {mse:.2f}")
    print(f"L1    : {l1:.2f}")
    print(f"CosSim: {cos:.6f}")
    print(f"Exact match ratio: {eq*100:.2f}%")

def compare_float(sx_path: Path, wscales_path: Path):
    if not ref_npy.exists():
        raise FileNotFoundError(f"ref float not found: {ref_npy}")
    if not sx_path.exists() or not wscales_path.exists():
        raise FileNotFoundError("s_x.npy 或 w_scales.npy 未找到，请在量化时保存两个文件。")

    s_x = float(np.load(sx_path))
    w_scales = np.load(wscales_path).astype(np.float32)  # 形如 [OUT_CH]

    b_q = read_mem_signed(mem_bias, 32)
    hw  = np.loadtxt(hw_txt, dtype=np.int64)
    OUT_CH = len(b_q)

    # 反量化：每个通道使用 s_x*w_scales[oc]
    ref = np.load(ref_npy).astype(np.float32)
    # 推断 OUT_SIZE 用于 reshape
    out_spatial = ref.size // OUT_CH
    OUT_SIZE = int(np.sqrt(out_spatial))

    hw = hw.reshape(OUT_CH, OUT_SIZE, OUT_SIZE).astype(np.float32)
    for oc in range(OUT_CH):
        hw[oc] *= (s_x * float(w_scales[oc]))  # bias 已在 int32 域相加，无需再加 b_fp32

    hw = hw.flatten()
    ref = ref.flatten()
    m = min(hw.size, ref.size)
    hw, ref = hw[:m], ref[:m]

    mse = np.mean((hw - ref)**2)
    l1  = np.mean(np.abs(hw - ref))
    cos = np.dot(hw, ref) / (np.linalg.norm(hw)*np.linalg.norm(ref) + 1e-12)

    print("=== Conv1 HW (dequant) vs Float reference ===")
    print(f"shape: {m}, OUT_CH={OUT_CH}, OUT_SIZE={OUT_SIZE}")
    print(f"MSE   : {mse:.6f}")
    print(f"L1    : {l1:.6f}")
    print(f"CosSim: {cos:.6f}")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["int32","float"], default="int32",
                    help="对比方式：int32 域精确比对 或 反量化后与 float 参考比对")
    ap.add_argument("--sx", default=str(script_dir/"s_x.npy"),
                    help="输入量化 scale 的 npy 路径（mode=float 使用）")
    ap.add_argument("--wscales", default=str(script_dir/"w_scales.npy"),
                    help="权重量化 per-OC scales 的 npy 路径（mode=float 使用）")
    args = ap.parse_args()

    if args.mode == "int32":
        compare_int32()
    else:
        compare_float(Path(args.sx), Path(args.wscales))
