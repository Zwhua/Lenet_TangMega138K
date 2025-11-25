# Lenet_TangMega138K

基于 **Hummingbird E203** 与 **Tang Mega 138K FPGA** 的 LeNet 加速系统

---

## 📁 项目结构（Project Structure）

```plaintext
Lenet_TangMega138K
├── zwh_hkl_lbr/            # 工程库文件（IP 核、综合配置等）
├── rtl/                    # RTL 硬件设计代码
│   ├── e203/               # 蜂鸟 E203 RISC-V 处理器核心
│   │   ├── core/           # CPU 核心逻辑（取指、译码、执行、内存访问）
│   │   ├── subsys/         # 子系统封装（总线、外设接口）
│   │   └── soc/            # SoC 顶层集成
│   ├── accel/              # LeNet 神经网络加速器（自研）
│   ├── perips/             # 外设模块（UART、GPIO、Timer 等）
│   ├── general/            # 通用 IP（RAM、寄存器、总线转换器）
│   ├── tb_top.v            # 顶层仿真测试台
│   └── e203_soc_top.v      # SoC 系统顶层（CPU + 加速器 + 总线）
├── firmware/               # 嵌入式软件（运行在 E203 上）
│   ├── demo_gpio/          # GPIO 测试程序
│   ├── hello_world/        # 基础串口打印测试
│   └── lenet_driver/       # LeNet 加速器驱动程序
├── simulate/               # 软件仿真环境
│   ├── python/             # Python 模型仿真（验证算法正确性）
│   │   └── lenet_model.py  # LeNet 标准实现（NumPy/PyTorch）
│   └── cpp/                # C++ 高性能仿真
│       └── lenet_ref.cpp   # 参考模型（用于对比 RTL 输出）
├── constraints/            # FPGA 引脚约束文件
│   └── tang_mega_138k.cst  # Tang Mega 138K 引脚定义
├── build/                  # 编译生成文件
│   ├── *.bit               # FPGA Bitstream
│   └── *.log               # 综合/实现日志
└── README.md               # 项目说明文档
```

---

## 🔗 模块关系图（Module Relationship）

```
┌─────────────────────────────────────────────────────────┐
│                    e203_soc_top.v                       │  ← SoC 顶层
│  ┌──────────────┐   ┌──────────────┐   ┌────────────┐ │
│  │  E203 CPU    │←──│  ICB Bus     │──→│ Peripherals│ │
│  │  (RISC-V)    │   │  (System Bus)│   │ (UART/GPIO)│ │
│  └──────┬───────┘   └──────┬───────┘   └────────────┘ │
│         │                  │                            │
│         │                  ↓                            │
│         │          ┌──────────────┐                     │
│         └─────────→│ ITCM/DTCM    │  ← 指令/数据存储器 │
│                    │ (SRAM)       │                     │
│                    └──────────────┘                     │
│                           ↕                             │
│                    ┌──────────────┐                     │
│                    │ LeNet Accel  │  ← 神经网络加速器   │
│                    │ (accel/)     │                     │
│                    └──────────────┘                     │
└─────────────────────────────────────────────────────────┘
                          ↕
               ┌──────────────────────┐
               │   tb_top.v           │  ← 仿真测试台
               │  (Testbench)         │
               │  - 时钟生成          │
               │  - 复位控制          │
               │  - UART 监控         │
               │  - 波形记录(wave.vcd)│
               └──────────────────────┘
```

---

## 📦 核心模块说明（Core Modules）

### 1️⃣ **rtl/e203/** - 蜂鸟 E203 处理器
| 子目录 | 功能 |
|--------|------|
| `core/` | CPU 核心流水线（IFU取指、IDU译码、EXU执行、LSU访存、WB写回） |
| `subsys/` | 子系统封装（时钟复位、总线仲裁、存储器控制器） |
| `soc/` | SoC 顶层集成（连接 CPU、SRAM、外设） |

**关键文件：**
- `e203_cpu_top.v` - CPU 顶层模块
- `e203_itcm_ctrl.v` - 指令紧耦合存储器（ITCM）控制器
- `e203_dtcm_ctrl.v` - 数据紧耦合存储器（DTCM）控制器

---

### 2️⃣ **rtl/accel/** - LeNet 加速器
神经网络推理加速器，负责卷积、池化、全连接层的硬件实现。

**预期接口：**
- 通过 ICB 总线与 CPU 通信
- 寄存器控制（启动、状态查询）
- DMA 访问 SRAM（读取输入数据、写回结果）

---

### 3️⃣ **rtl/tb_top.v** - 仿真测试台
```verilog
tb_top.v
├── 时钟生成 (16MHz)
├── 复位逻辑
├── 实例化 e203_soc_top
├── UART 监控（解码串口输出）
└── 波形记录 (wave.vcd)
```

**核心功能：**
- 模拟 FPGA 的时钟和复位信号
- 强制修复层级路径问题（`force` 语句）
- 实时打印 PC 寄存器变化
- 解码 UART 输出（用于调试固件打印）

---

### 4️⃣ **firmware/** - 嵌入式固件
运行在 E203 CPU 上的 C 语言程序。

| 目录 | 功能 |
|------|------|
| `demo_gpio/` | GPIO 测试（LED 闪烁、按键检测） |
| `hello_world/` | 串口 UART 基础测试 |
| `lenet_driver/` | LeNet 加速器驱动程序 |

**典型流程：**
```c
// 伪代码示例
void main() {
    uart_init();
    printf("Initializing LeNet Accelerator...\n");
    
    lenet_load_weights();      // 加载权重到 SRAM
    lenet_set_input(image);    // 设置输入图像
    lenet_start();             // 启动加速器
    
    while (!lenet_done());     // 等待完成
    
    int result = lenet_get_result();
    printf("Classification: %d\n", result);
}
```

---

### 5️⃣ **simulate/** - 软件仿真
用于验证 LeNet 算法正确性，与 RTL 输出对比。

**Python 仿真：**
```python
# simulate/python/lenet_model.py
import torch
model = LeNet()
output = model(input_image)  # 标准输出
```

**C++ 仿真：**
```cpp
// simulate/cpp/lenet_ref.cpp
float output[10];
lenet_inference(input, weights, output);  // 参考实现
```

**对比流程：**
1. Python/C++ 生成标准输出
2. RTL 仿真生成硬件输出
3. 逐层对比误差（允许定点量化误差）

---

## 🔄 完整工作流程（Workflow）

```
1. 算法验证
   └→ simulate/python/ (验证 LeNet 算法)

2. RTL 设计
   └→ rtl/accel/ (实现加速器硬件)
   └→ rtl/e203/ (集成 CPU)

3. 仿真验证
   └→ rtl/tb_top.v (运行 Verilog 仿真)
   └→ 对比 simulate/cpp/ 的输出

4. 固件开发
   └→ firmware/lenet_driver/ (编写驱动程序)
   └→ 编译生成 .hex 文件加载到 ITCM

5. FPGA 综合
   └→ constraints/ (引脚约束)
   └→ build/ (生成 .bit 文件)

6. 上板调试
   └→ 通过 UART 查看运行结果
```

---

## 🚀 开发目标（Development Goals）

- [x] E203 CPU 基础框架搭建
- [x] 仿真环境建立（tb_top.v）
- [ ] LeNet 加速器 RTL 实现
- [ ] 固件驱动程序编写
- [ ] 端到端仿真验证
- [ ] FPGA 上板测试
- [ ] 性能优化（流水线、并行度）

---

## 📌 注意事项（Notes）

1. **wave.vcd 文件管理**
   - 仿真波形文件体积巨大（>100MB）
   - 已添加到 `.gitignore`，避免上传到 GitHub

2. **仿真层级问题**
   - `tb_top.v` 中使用了大量 `force` 语句修复时钟/复位路径
   - 需要确保模块实例化名称正确

3. **固件编译**
   - 需要 RISC-V GCC 工具链
   - 生成的 `.hex` 文件通过 `$readmemh` 加载到 ITCM

4. **总线协议**
   - 使用蜂鸟的 ICB（Instruction/Data Coupled Bus）
   - 加速器需要实现 ICB Slave 接口

---

## 📖 参考资料（References）

- [蜂鸟 E203 开源处理器](https://github.com/SI-RISCV/e200_opensource)
- [Tang Mega 138K 用户手册](https://tang.sipeed.com)
- [LeNet 论文原文](http://yann.lecun.com/exdb/lenet/)

---
