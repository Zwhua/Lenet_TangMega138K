#  Lenet_TangMega138K

基于 **Hummingbird E203** 与 **Tang Mega 138K FPGA** 的 LeNet 加速系统
---

## 📁 项目结构（Project Structure）

```plaintext
Lenet_TangMega138K
├── zwh_hkl_lbr/            
├── rtl/                    # RTL 主要代码
│   ├── e203/               # 蜂鸟 E203 SoC 搭建
│   ├── accel/              # LeNet 加速器模块
│   └── soc/                # SOC 顶层封装
├── firmware/               # 固件控制（C 语言）
├── simulate/               # 仿真环境
│   ├── python/             # Python 端 LeNet 仿真
│   └── cpp/                # C++ 端 LeNet 仿真
├── constraints/            # （待建设）FPGA 引脚约束
├── build/                  # （待建设）构建生成文件
└── README.md
```
---
## 模块说明（Modules Description）
### 🔹 **rtl/**
RTL 逻辑模块，包含系统最核心的硬件设计：

* **e203/**
  用于构建 RISC-V 蜂鸟 E203 处理器子系统
* **accel/**
  自研 LeNet 神经网络加速器
* **soc/**
  将 CPU、加速器、SRAM、外设、ICB 总线进行系统级封装
---
### 🔹 **firmware/**
使用 C 语言编写的固件，用于控制：
* 加速器启动
* 内存读写
* 测试与验证流程
* 与 E203 CPU 的交互
---
### 🔹 **simulate/**
软件级仿真环境，用于验证 LeNet 功能与 RTL 的一致性：
* **python/**：Python 模型仿真（如 NumPy/torch 版本 LeNet）
* **cpp/**：C++ 高性能仿真
* 后续可以扩展 co-sim（软硬协同仿真）
---
### 🔹 **constraints/**（待建设）
存放 FPGA 引脚约束文件（如 `.xdc`、`.pcf`）。
---
### 🔹 **build/**（待建设）
生成文件目录，包括：
* bitstream (`.bit`)
* 编译日志
* 中间文件
---
## 🚀 开发目标（Development Goals）

* 在 Tang Mega 138K FPGA 上跑通 **端到端 LeNet 推理**
* 实现 **E203 + 自定义加速器** 的 SoC 架构
* 支持 **软件/硬件协同调试**
* 最终可运行 firmware → 驱动加速器 → 输出分类结果
---


