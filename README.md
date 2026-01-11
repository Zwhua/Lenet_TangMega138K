# Lenet_FPGA v1.1.26

面向 Gowin TangMega138K FPGA 的 Lenet + E203 SoC 工程，包含 RTL、固件、仿真与综合工程，便于在 Linux 环境下复现软硬件协同流程。

## 目录结构
- `rtl/`：E203 RISC-V 核心、外设、IP 及顶层封装。
- `firmware/hello_world/`：基于 hbird-e200 BSP 的示例固件与构建脚本。
- `sim/`：SystemVerilog testbench、仿真脚本、默认输入/波形输出。
- `sim_lib/`：Gowin GW2A 原语库，用于仿真。
- `gowin_prj/`：Gowin IDE 工程（Linux/Windows 版本）、约束与时序文件。
- `tools/makehex64/`：将 ELF 转换为 64-bit RAM 初始化镜像的脚本。
- `.gitignore`：忽略大体积仿真波形与工具产物，避免推送超限。

## 环境要求
- Ubuntu 20.04+，GNU Make、CMake、Python 3
- RISC-V GCC 工具链（支持 E203）
- Gowin IDE（生成 bitstream）
- Verilator 或 Icarus Verilog（按需替换仿真器）
- Git LFS（追踪 >100 MB 的波形文件）

## 快速开始
1. **获取代码**
   ```bash
   git clone https://github.com/Zwhua/Lenet_TangMega138K.git
   cd Lenet_FPGA/lenet_v1126
   ```
2. **编译固件**
   ```bash
   cd firmware/hello_world
   mkdir -p build && cd build
   cmake ..
   make
   ```
   生成的 `ram.hex` 可被仿真与 FPGA 工程复用。
3. **运行仿真**
   ```bash
   cd ../../sim
   ./sim_sys_tb.sh
   ```
   输出 `waveout/`、`waveout.vcd` 等波形，已在 `.gitignore` 中排除。
4. **综合与实现**
   - 打开 `gowin_prj/e203_hello_world_lnx.gprj`
   - 导入 `firmware/hello_world/build/ram.hex`
   - 运行综合、布局布线，导出 bitstream。

## 常用脚本
- `tools/makehex64/makehex64.py`：将 ELF 转 HEX
- `sim/sim_sys_tb.sh`：批量执行仿真
- `firmware/hello_world/tools/openocd_upload.sh`：下载固件至目标板

## Git 大文件策略
- 所有 `.lxt`、`.vcd` 已在 `.gitignore` 中，若需保留历史请使用 Git LFS：
  ```bash
  git lfs track "sim/*.lxt" "sim/*.vcd"
  git add .gitattributes
  ```

## 许可证
根据上游 E203 项目与 BSP 的许可证分发，请在提交前确认各子模块协议。
