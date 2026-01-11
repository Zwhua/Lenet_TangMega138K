# Lenet_FPGA v1.1.26
在这里先感谢蒋磊老师的指导！
面向 Gowin TangMega138K FPGA 的 LeNet 卷积神经网络加速器 + E203 RISC-V SoC 工程，实现了硬件加速的神经网络推理系统。项目包含完整的 RTL 设计、固件、仿真环境与 FPGA 综合工程，便于在 Linux 环境下复现软硬件协同开发流程。

## 📋 项目概述

本项目基于蜂鸟 E203 RISC-V 处理器核心，集成了 LeNet-5 卷积神经网络硬件加速器，支持：
- ✅ Conv1 卷积层硬件加速（28×28 输入，5×5 卷积核，6 通道输出）
- ✅ Pool1 池化层硬件加速
- ✅ FC1 全连接层硬件加速（400→120 神经元）
- ✅ CPU 通过内存映射 I/O 控制加速器
- ✅ 完整的仿真验证环境
- ✅ 支持在 TangMega138K 开发板上实现

## 📁 目录结构

```
LENET/
├── README.md                   # 本文档
├── .gitignore                  # Git 忽略规则（已排除大文件）
│
├── rtl/                        # RTL 硬件设计源码
│   ├── core/                   # E203 RISC-V 核心
│   │   ├── e203_cpu*.v        # CPU 核心模块
│   │   ├── e203_exu*.v        # 执行单元
│   │   ├── e203_ifu*.v        # 指令获取单元
│   │   ├── e203_lsu*.v        # 加载存储单元
│   │   └── PLL_138K/          # 时钟 PLL 模块
│   └── ip/                     # IP 核与加速器
│       └── LENET/             # LeNet 加速器
│           ├── conv1_accel*.v  # Conv1 卷积加速器
│           ├── pool1_accel*.v  # Pool1 池化加速器
│           └── fc_accel*.v     # FC1 全连接加速器
│
├── firmware/                   # 软件固件
│   └── hello_world/           # 示例固件工程
│       ├── CMakeLists.txt     # CMake 构建配置
│       ├── src/               # 源代码
│       │   ├── main.c         # 主程序（加速器测试代码）
│       │   └── bsp/           # 板级支持包
│       └── Debug/             # 调试输出目录
│
├── sim/                        # 仿真环境
│   ├── sys_tb_top.sv          # 顶层 testbench
│   ├── sim_sys_tb.sh          # 仿真脚本（Icarus Verilog）
│   ├── input.txt              # 仿真输入数据
│   ├── disasm.txt             # 反汇编输出
│   ├── waveout.vcd            # 波形文件（gitignore）
│   ├── cpu_signals.gtkw       # GTKWave 配置
│   └── python/                # Python 辅助脚本
│
├── sim_lib/                    # 仿真库
│   └── gw2a/                  # Gowin GW2A 原语库
│       └── prim_sim.v         # 仿真原语
│
├── lenet_V003/                 # Gowin IDE 综合工程
│   ├── lenet_V003.gprj        # 工程文件
│   ├── src/                   # 源码链接
│   └── impl/                  # 综合实现输出（gitignore）
│       ├── gwsynthesis/       # 综合结果
│       ├── pnr/               # 布局布线
│       └── temp/              # 临时文件
│
└── tools/                      # 辅助工具
    └── makehex64/             # ELF 转 HEX 工具
        └── makehex64.py       # 转换脚本
```

## 🛠️ 环境要求

### 必需软件

| 软件 | 版本要求 | 用途 |
|------|---------|------|
| **操作系统** | Ubuntu 20.04+ / Debian 11+ | 开发环境 |
| **RISC-V GCC** | riscv64-unknown-elf-gcc | 交叉编译固件 |
| **CMake** | 3.10+ | 固件构建系统 |
| **GNU Make** | 4.0+ | 构建工具 |
| **Python** | 3.6+ | 脚本工具 |
| **Icarus Verilog** | 10.0+ | RTL 仿真 |
| **GTKWave** | 3.3+ | 波形查看 |
| **Gowin EDA** | 1.9.8+ | FPGA 综合与实现 |

### RISC-V 工具链安装

```bash
# 方法 1：使用预编译工具链（推荐）
wget https://github.com/sifive/freedom-tools/releases/download/v2020.12.0/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-linux-ubuntu14.tar.gz
tar -xzf riscv64-unknown-elf-toolchain-*.tar.gz -C /opt/
export PATH=/opt/riscv64-unknown-elf-toolchain-10.2.0/bin:$PATH

# 方法 2：从源码构建
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain
./configure --prefix=/opt/riscv --with-arch=rv32imac --with-abi=ilp32
make
export PATH=/opt/riscv/bin:$PATH
```

### 仿真工具安装

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install iverilog gtkwave

# 验证安装
iverilog -v
gtkwave --version
```

## 🚀 快速开始

### 1. 克隆代码

```bash
git clone https://github.com/Zwhua/Lenet_TangMega138K.git
cd Lenet_TangMega138K/LENET
```

### 2. 编译固件

```bash
cd firmware/hello_world
mkdir -p build && cd build

# 配置并编译
cmake ..
make

# 查看生成的文件
ls -lh *.elf *.bin *.hex
```

生成的文件说明：
- `hello_world.elf`：可执行文件
- `hello_world.bin`：二进制镜像
- `ram.hex`：用于 FPGA/仿真的 HEX 文件

### 3. 运行仿真

```bash
cd ../../../sim

# 运行仿真脚本
./sim_sys_tb.sh

# 查看波形
gtkwave waveout.vcd cpu_signals.gtkw &

# 或使用 VCD 文件
gtkwave waveout.vcd
```

仿真将：
1. 加载固件到内存
2. 启动 E203 CPU 执行程序
3. CPU 配置并启动卷积加速器
4. 生成波形文件 `waveout.vcd`
5. 输出执行日志到终端

### 4. FPGA 综合与实现

#### 使用 Gowin IDE

1. **打开工程**
   ```bash
   # 启动 Gowin IDE
   gw_ide
   
   # 打开工程文件
   # File -> Open -> lenet_V003/lenet_V003.gprj
   ```

2. **配置固件**
   - 复制固件 HEX 文件到工程目录
   ```bash
   cp firmware/hello_world/build/ram.hex lenet_V003/
   ```

3. **综合流程**
   - 点击 **Synthesize**（综合）
   - 等待综合完成
   - 查看资源占用报告

4. **布局布线**
   - 点击 **Place & Route**
   - 等待布线完成
   - 查看时序报告

5. **生成 Bitstream**
   - 点击 **Program Device**
   - 生成 `.fs` 文件

6. **下载到开发板**
   - 连接 TangMega138K 开发板
   - 使用 Gowin Programmer 下载

#### 注意事项
- 综合时间取决于机器性能（通常 5-20 分钟）
- 确保时序约束满足要求
- 生成的大文件（`.pr`、`.db`）已被 `.gitignore` 排除

## 📝 固件开发说明

### 主程序结构

[main.c](firmware/hello_world/src/main.c) 实现了完整的加速器测试流程：

```c
// 1. 初始化加速器
void conv1_init() {
    // 加载输入数据（28×28 图像）
    // 加载卷积核权重（5×5×6）
    // 加载偏置参数
}

// 2. 启动计算
LENET_CTRL = 0x1;  // 启动 Conv1
while (!(LENET_STATUS & 0x1));  // 等待完成

// 3. 读取结果
for (int i = 0; i < OUTPUT_SIZE; i++) {
    int32_t result = LENET_OUTPUT32[i];
}
```

### 内存映射

| 模块 | 基地址 | 寄存器 | 偏移 | 说明 |
|------|--------|--------|------|------|
| **Conv1** | 0x10035000 | CTRL | +0x0000 | 控制寄存器 |
|  |  | STATUS | +0x0004 | 状态寄存器 |
|  |  | INPUT | +0x0010 | 输入数据（784字节）|
|  |  | WEIGHT | +0x1000 | 权重数据（150字节）|
|  |  | BIAS | +0x2000 | 偏置数据（6字节）|
|  |  | OUTPUT | +0x3000 | 输出数据（3456字节）|
| **FC1** | 0x10039000 | CTRL | +0x0000 | 控制寄存器 |
|  |  | STATUS | +0x0004 | 状态寄存器 |
|  |  | INPUT | +0x0010 | 输入数据（400字节）|
|  |  | WEIGHT | +0x1000 | 权重数据（48000字节）|
|  |  | BIAS | +0x30000 | 偏置数据（120字节）|
|  |  | OUTPUT | +0x31000 | 输出数据（120字节）|

### 修改测试数据

编辑 [main.c](firmware/hello_world/src/main.c) 中的数组：

```c
// 输入图像数据（28×28 = 784 像素）
static const int8_t input_data[784] = { /* 你的数据 */ };

// 卷积核权重（6通道 × 1输入通道 × 5×5）
static const int8_t weight_data[150] = { /* 你的权重 */ };

// 偏置参数（6通道）
static const int32_t bias_data[6] = { /* 你的偏置 */ };
```

## 🔍 调试技巧

### 仿真调试

1. **查看 CPU 状态**
   ```bash
   # 查看 CPU 信号定义
   cat sim/CPU状态信号清单.md
   
   # 使用 GTKWave 预设配置
   gtkwave waveout.vcd cpu_signals.gtkw
   ```

2. **查看反汇编**
   ```bash
   # 反汇编 ELF 文件
   riscv64-unknown-elf-objdump -d firmware/hello_world/build/hello_world.elf > disasm.txt
   ```

3. **添加仿真日志**
   在 testbench 中添加：
   ```verilog
   always @(posedge clk) begin
       if (u_e203_soc_top.LENET_CTRL_we) begin
           $display("[%t] Conv1 Start", $time);
       end
   end
   ```

### 硬件调试

1. **使用 UART 输出**
   ```c
   printf("Conv1 result[0] = %d\n", LENET_OUTPUT32[0]);
   ```

2. **LED 指示**
   ```c
   GPIO_OUT = (status & 0x1) << 0;  // LED0 显示加速器状态
   ```

3. **逻辑分析仪**
   - 使用 Gowin 内置 LA
   - 抓取关键信号时序

## 📊 性能指标

### Conv1 层参数
- 输入尺寸：28×28×1
- 卷积核：5×5×6
- 输出尺寸：24×24×6
- 计算量：~115,200 次乘加

### FC1 层参数
- 输入神经元：400
- 输出神经元：120
- 权重数量：48,000
- 计算量：~48,000 次乘加

### 资源占用（TangMega138K）
| 资源 | 使用 | 总量 | 占比 |
|------|------|------|------|
| LUT | ~15K | 138K | ~11% |
| FF | ~8K | 138K | ~6% |
| BRAM | ~500Kb | 6.8Mb | ~7% |
| DSP | ~20 | 298 | ~7% |

## 🐛 常见问题

### Q1: 仿真时找不到 `ram.hex`
**A:** 确保先编译固件，并将 `ram.hex` 复制到仿真目录：
```bash
cp firmware/hello_world/build/ram.hex sim/
```

### Q2: Git 推送失败 "file size limit"
**A:** 大文件已在 `.gitignore` 中排除，如果仍有问题：
```bash
git rm --cached lenet_V003/impl/pnr/*.pr
git commit -m "Remove large files"
```

### Q3: RISC-V 工具链找不到
**A:** 确保已添加到 PATH：
```bash
export PATH=/opt/riscv/bin:$PATH
echo 'export PATH=/opt/riscv/bin:$PATH' >> ~/.bashrc
```

### Q4: 仿真速度慢
**A:** 尝试使用 Verilator（比 Icarus 快 10-100 倍）：
```bash
sudo apt-get install verilator
verilator --cc --exe --build -j 4 sys_tb_top.sv
```

### Q5: Gowin IDE 无法打开工程
**A:** 检查文件路径，确保没有中文字符，工程路径不要太深。

## 🔗 相关资源

### 上游项目
- [E203 Hummingbird Core](https://github.com/SI-RISCV/e200_opensource) - E203 RISC-V 核心
- [HBird SDK](https://github.com/riscv-mcu/hbird-sdk) - 蜂鸟 SDK
- [Gowin Semiconductor](http://www.gowinsemi.com.cn/) - 高云半导体

### 文档
- [RISC-V Spec](https://riscv.org/technical/specifications/) - RISC-V 指令集规范
- [LeNet-5 Paper](http://yann.lecun.com/exdb/lenet/) - LeNet 原始论文
- [Gowin IDE User Guide](http://www.gowinsemi.com.cn/faq.aspx) - IDE 使用手册

### 工具
- [GTKWave](http://gtkwave.sourceforge.net/) - 波形查看器
- [Icarus Verilog](http://iverilog.icarus.com/) - Verilog 仿真器
- [Verilator](https://www.veripool.org/verilator/) - 高性能仿真器



## 📄 许可证

本项目遵循上游 E203 项目的许可协议。部分模块可能有不同的许可证，使用前请确认：
- E203 Core: Apache 2.0 / Mulan PSL v2
- HBird BSP: Apache 2.0
- 自研加速器模块: MIT License

## 📧 联系方式

- **项目维护**: Zwhua
- **仓库地址**: https://github.com/Zwhua/Lenet_TangMega138K
- **Issue**: https://github.com/Zwhua/Lenet_TangMega138K/issues

---

**更新日期**: 2026-01-11  
**版本**: v1.1.27  
