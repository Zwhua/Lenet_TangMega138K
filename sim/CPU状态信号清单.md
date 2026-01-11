# CPU 状态波形信号清单

## 快速加载方法

### 方法1：使用预配置文件（推荐）
```bash
cd /home/zwh/workspace/Lenet_FPGA/LENET/sim
gtkwave waveout.vcd cpu_signals.gtkw
```

### 方法2：手动添加信号
```bash
gtkwave waveout.vcd
```
然后在左侧信号树中按以下列表逐个添加。

---

## 信号层级与说明

### 1️⃣ 顶层时钟与复位
```
路径：sys_tb_top
信号：
  clk              - 系统主时钟 (27MHz, 周期37.04ns)
  rst_n            - 复位信号 (低有效，320us后释放)
  gpio_in[31:0]    - GPIO 输入端口
  gpio_out[31:0]   - GPIO 输出端口 (bit17=UART_RX, bit16=UART_TX)
```

**观察要点**：
- `rst_n` 在 320us 时从 0→1
- `clk` 持续翻转
- `gpio_out` 可观察 UART 数据输出（如有 printf）

---

### 2️⃣ CPU 核心状态
```
路径：sys_tb_top.uut.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_exu.u_e203_exu_commit

信号：
  cmt_ena          - 指令提交使能 (1=有指令执行完成)
  cmt_mret         - mret 指令提交 (从中断/异常返回)
  cmt_pc[31:0]     - 当前提交的指令 PC 地址
```

**观察要点**：
- `cmt_ena=1` 时，CPU 正在执行指令
- `cmt_pc` 的值变化表示程序执行流
- 若 `cmt_pc` 停在某个地址循环，可能卡死或在等待

---

### 3️⃣ 取指单元 (IFU - Instruction Fetch Unit)
```
路径：sys_tb_top.uut.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_ifu

信号：
  ifu_o_valid      - 取指有效 (1=IFU取到指令)
  ifu_o_ready      - 下游准备好接收
  ifu_o_ir[31:0]   - 取到的指令码 (RISC-V 指令)
  ifu_o_pc[31:0]   - 取指 PC 地址
```

**观察要点**：
- `ifu_o_valid=1 && ifu_o_ready=1` 时握手成功，指令传递
- `ifu_o_pc` 应递增（顺序执行）或跳变（分支/跳转）
- `ifu_o_ir` 可对照 RISC-V 指令集判断当前指令类型

---

### 4️⃣ LSU 访存单元 (Load-Store Unit)
```
路径：sys_tb_top.uut.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_lsu

信号：
  lsu_o_valid      - LSU 结果有效
  lsu_o_ready      - 下游准备好
  lsu_o_wbck_wdat[31:0] - 写回数据 (load 指令结果)
```

**观察要点**：
- 当执行 `lw`/`lb` 等 load 指令时，`lsu_o_valid=1`
- `lsu_o_wbck_wdat` 是从内存读回的数据

---

### 5️⃣ BIU 总线接口 (Bus Interface Unit)
```
路径：sys_tb_top.uut.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_biu

命令通道：
  biu_icb_cmd_valid    - BIU 发起访问请求
  biu_icb_cmd_ready    - 总线准备好
  biu_icb_cmd_addr[31:0] - 访问地址（关键！）
  biu_icb_cmd_read     - 1=读，0=写
  biu_icb_cmd_wdata[31:0] - 写数据

响应通道：
  biu_icb_rsp_valid    - 总线返回有效
  biu_icb_rsp_ready    - CPU准备接收
  biu_icb_rsp_rdata[31:0] - 读回数据
```

**观察要点**：
- `biu_icb_cmd_addr` 是 CPU 访问的所有地址（内存+外设）
- 当地址在 `0x10035000-0x1003AFFF` 范围时，在访问卷积加速器
- 通过 `biu_icb_cmd_read` 区分读/写操作

---

### 6️⃣ PWM2/卷积加速器 ICB 总线（外设侧）
```
路径：sys_tb_top.uut.u_e203_subsys_top.u_e203_subsys_main.u_e203_subsys_perips

命令通道：
  pwm2_icb_cmd_valid     - 外设总线有效
  pwm2_icb_cmd_ready     - 加速器准备好
  pwm2_icb_cmd_addr[31:0] - 外设地址
  pwm2_icb_cmd_read      - 读/写
  pwm2_icb_cmd_wdata[31:0] - 写数据

响应通道：
  pwm2_icb_rsp_valid     - 加速器响应有效
  pwm2_icb_rsp_ready     - 外设总线准备接收
  pwm2_icb_rsp_rdata[31:0] - 读回数据
```

**观察要点**：
- 这是 **BIU 到加速器** 的最后一级总线
- `pwm2_icb_cmd_addr` 应出现 `0x10035000`/`0x10036000` 等地址
- 若这组信号全为 0，说明 CPU 未运行到加速器测试代码

---

### 7️⃣ 卷积加速器内部状态
```
路径：sys_tb_top.uut.u_e203_subsys_top.u_e203_subsys_main.u_e203_subsys_perips.u_lenet_accel

控制寄存器：
  start_reg    - 启动信号 (CPU写CTRL后置1)
  done_reg     - 完成信号 (计算完成后置1)

路径：.u_lenet_accel.u_accel

状态机：
  state[2:0]   - 0=IDLE, 1=READ, 2=MAC, 3=WRITE, 4=DONE
  oc[2:0]      - 输出通道计数 (0-5)
  out_y[4:0]   - 输出行坐标 (0-23)
  out_x[4:0]   - 输出列坐标 (0-23)
```

**观察要点**：
- `start_reg=1` 时，加速器被 CPU 启动
- `state` 循环变化（1→2→3）表示正在计算
- `done_reg=1` 时，CPU 可读取结果

---

## 典型波形分析场景

### 场景1：CPU 是否在运行？
**观察信号**：
- `cmt_ena` - 应频繁为 1
- `cmt_pc` - 应持续变化
- `biu_icb_cmd_addr` - 应有地址访问活动

**异常现象**：
- `cmt_ena` 长期为 0 → CPU 可能卡死或未启动
- `cmt_pc` 停在固定地址 → 可能在等待循环（WFI 或轮询）

---

### 场景2：CPU 是否访问了加速器？
**观察信号**：
- `biu_icb_cmd_addr` 或 `pwm2_icb_cmd_addr`

**成功标志**：
- 地址出现 `0x10035000`（CTRL寄存器）
- 地址出现 `0x10035010-0x10035C1F`（输入 buffer）
- 地址出现 `0x10036000-0x10036095`（权重 buffer）

**失败标志**：
- `pwm2_icb_cmd_valid` 始终为 0
- `biu_icb_cmd_addr` 从未进入 `0x10035xxx` 范围

---

### 场景3：加速器是否在计算？
**观察信号**：
- `start_reg` - 是否被置 1
- `state` - 是否在 1/2/3 之间循环
- `oc`, `out_y`, `out_x` - 计数器是否递增

**成功标志**：
- `state` 从 0→1→2→3 循环变化
- `oc` 从 0 递增到 5
- 最终 `done_reg=1`

---

## 调试命令速查

### 在波形中搜索关键事件
```tcl
# GTKWave TCL 命令（在 GTKWave 控制台输入）
gtkwave::setMarker -100000  # 设置标记
gtkwave::searchNext "pwm2_icb_cmd_addr" "10035000"  # 搜索地址
```

### 导出波形数据
```bash
# 使用 vcd2fst 转换为更高效的 FST 格式
vcd2fst waveout.vcd waveout.fst
gtkwave waveout.fst cpu_signals.gtkw
```

### 截取特定时间段
```bash
# 假设卷积开始时间在 5ms
gtkwave waveout.vcd -S cpu_signals.gtkw -T 5ms
```

---

## 汇报建议

### 展示截图1：CPU 正在执行指令
- 显示 `clk`, `cmt_ena`, `cmt_pc`
- 标注 PC 地址变化，证明程序在运行

### 展示截图2：CPU 访问加速器
- 显示 `biu_icb_cmd_addr` 在 `0x10035xxx` 范围
- 标注 "CPU 写入输入数据" 或 "CPU 启动加速器"

### 展示截图3：加速器计算过程
- 显示 `state`, `oc`, `out_y`, `out_x`
- 标注状态机循环和计数器递增

### 展示截图4：计算完成
- 显示 `done_reg=1`
- 显示 CPU 读取 `STATUS` 寄存器（`pwm2_icb_cmd_addr=0x10035004`）

---

**总结**：通过观察 BIU 和 PWM2 总线的地址信号（`biu_icb_cmd_addr` 和 `pwm2_icb_cmd_addr`），可以明确判断 CPU 是否访问了加速器。若这些地址始终为 0，说明 CPU 固件未运行到测试代码，需检查固件编译或复位时序。
