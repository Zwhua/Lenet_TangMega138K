`timescale 1ns/1ps

module led (
    output [15:0] led   // 外部 16 个 LED
);

//====================
// 1) 时钟：用 Gowin 内部 OSC
//====================
wire clk_osc;

// 你工程里已有的 Gowin_OSC 模块
Gowin_OSC u_osc (
    .oscout(clk_osc)
);

// 我们就直接把这个当作 “快时钟”
wire clk_16M = clk_osc;

// 分频得到一个“慢时钟”给 RTC/always-on 域
reg [14:0] div_cnt;
reg        clk_32k;

always @(posedge clk_16M) begin
    div_cnt <= div_cnt + 1'b1;
    clk_32k <= div_cnt[14];  // 大概是 clk_16M / 2^14，频率不重要，只要是个慢钟
end

//====================
// 2) 复位：简单上电复位（低有效）
//====================
reg [7:0] rst_cnt = 8'd0;
reg       ck_rst_n = 1'b0;  // 连接到 io_pads_aon_erst_n_i_ival（低有效）

always @(posedge clk_16M) begin
    if (rst_cnt != 8'hFF) begin
        rst_cnt   <= rst_cnt + 1'b1;
        ck_rst_n  <= 1'b0;  // 上电一段时间保持复位
    end else begin
        ck_rst_n  <= 1'b1;  // 之后释放复位
    end
end

//====================
// 3) JTAG：先全部绑死，暂时不用
//====================
wire dut_io_pads_jtag_TCK_i_ival;
wire dut_io_pads_jtag_TMS_i_ival;
wire dut_io_pads_jtag_TDI_i_ival;
wire dut_io_pads_jtag_TDO_o_oval;
wire dut_io_pads_jtag_TDO_o_oe;

assign dut_io_pads_jtag_TCK_i_ival = 1'b0;
assign dut_io_pads_jtag_TMS_i_ival = 1'b1;
assign dut_io_pads_jtag_TDI_i_ival = 1'b0;
// TDO 是 SoC 输出，我们现在不接到引脚，用不到就行

//====================
// 4) GPIO：用 GPIOA[15:0] 驱动 LED
//====================
wire [31:0] gpioA_i;
wire [31:0] gpioA_o;
wire [31:0] gpioA_oe;
wire [31:0] gpioB_i;
wire [31:0] gpioB_o;
wire [31:0] gpioB_oe;

// 没有外部按键输入，就全绑 0
assign gpioA_i = 32'b0;
assign gpioB_i = 32'b0;

// 把 GPIOA[15:0] 映射到板子上的 LED
// 根据实际电路习惯，你可以用 ~ 取反或者不取反
assign led = ~gpioA_o[15:0];  // 如果灯亮灭反了，可以改成 assign led = gpioA_o[15:0];

//====================
// 5) Boot/PMU/Debug 模式脚
//====================
wire dut_io_pads_aon_pmu_vddpaden_o_oval;
wire dut_io_pads_aon_pmu_padrst_o_oval;

wire dut_io_pads_aon_pmu_dwakeup_n_i_ival;
wire dut_io_pads_bootrom_n_i_ival;
wire dut_io_pads_dbgmode0_n_i_ival;
wire dut_io_pads_dbgmode1_n_i_ival;
wire dut_io_pads_dbgmode2_n_i_ival;

// 不用外部唤醒，就绑 1（低有效）
assign dut_io_pads_aon_pmu_dwakeup_n_i_ival = 1'b1;

// bootrom_n = 0：从内部 Boot ROM 启动（0x0000_1000）
// 之后 Boot ROM 里一般会再跳到 QSPI FLASH 区
assign dut_io_pads_bootrom_n_i_ival = 1'b0;

// 禁用 debug mode
assign dut_io_pads_dbgmode0_n_i_ival = 1'b1;
assign dut_io_pads_dbgmode1_n_i_ival = 1'b1;
assign dut_io_pads_dbgmode2_n_i_ival = 1'b1;

//====================
// 6) QSPI：先在 FPGA 里留着，不接到实际引脚
//====================
wire qspi0_sck;
wire qspi0_cs;
wire qspi0_dq0_i, qspi0_dq0_o, qspi0_dq0_oe;
wire qspi0_dq1_i, qspi0_dq1_o, qspi0_dq1_oe;
wire qspi0_dq2_i, qspi0_dq2_o, qspi0_dq2_oe;
wire qspi0_dq3_i, qspi0_dq3_o, qspi0_dq3_oe;

// 输入脚绑 0，代表“没有外部 FLASH”。
// 真正要从 FLASH 跑程序的时候，我们会把这些线接到板子的 QSPI Flash 引脚上，并更新 .cst 约束。
assign qspi0_dq0_i = 1'b0;
assign qspi0_dq1_i = 1'b0;
assign qspi0_dq2_i = 1'b0;
assign qspi0_dq3_i = 1'b0;

//====================
// 7) 例化 e203_soc_top
//   端口名完全参照官方示例
//====================
e203_soc_top u_core (
    // 高频时钟
    .hfextclk(clk_16M),
    .hfxoscen(),                // 外部晶振使能脚（一般接到外部晶振电路），我们不用就空着

    // 低频 RTC 时钟
    .lfextclk(clk_32k),
    .lfxoscen(),                // 同上，先空着

    // JTAG
    .io_pads_jtag_TCK_i_ival(dut_io_pads_jtag_TCK_i_ival),
    .io_pads_jtag_TMS_i_ival(dut_io_pads_jtag_TMS_i_ival),
    .io_pads_jtag_TDI_i_ival(dut_io_pads_jtag_TDI_i_ival),
    .io_pads_jtag_TDO_o_oval(dut_io_pads_jtag_TDO_o_oval),
    .io_pads_jtag_TDO_o_oe  (dut_io_pads_jtag_TDO_o_oe),

    // GPIO A / GPIO B
    .io_pads_gpioA_i_ival(gpioA_i),
    .io_pads_gpioA_o_oval(gpioA_o),
    .io_pads_gpioA_o_oe  (gpioA_oe),

    .io_pads_gpioB_i_ival(gpioB_i),
    .io_pads_gpioB_o_oval(gpioB_o),
    .io_pads_gpioB_o_oe  (gpioB_oe),

    // QSPI0 接口（目前只连到内部 wire）
    .io_pads_qspi0_sck_o_oval (qspi0_sck),
    .io_pads_qspi0_cs_0_o_oval(qspi0_cs),

    .io_pads_qspi0_dq_0_i_ival(qspi0_dq0_i),
    .io_pads_qspi0_dq_0_o_oval(qspi0_dq0_o),
    .io_pads_qspi0_dq_0_o_oe  (qspi0_dq0_oe),

    .io_pads_qspi0_dq_1_i_ival(qspi0_dq1_i),
    .io_pads_qspi0_dq_1_o_oval(qspi0_dq1_o),
    .io_pads_qspi0_dq_1_o_oe  (qspi0_dq1_oe),

    .io_pads_qspi0_dq_2_i_ival(qspi0_dq2_i),
    .io_pads_qspi0_dq_2_o_oval(qspi0_dq2_o),
    .io_pads_qspi0_dq_2_o_oe  (qspi0_dq2_oe),

    .io_pads_qspi0_dq_3_i_ival(qspi0_dq3_i),
    .io_pads_qspi0_dq_3_o_oval(qspi0_dq3_o),
    .io_pads_qspi0_dq_3_o_oe  (qspi0_dq3_oe),

    // 复位 & 电源管理 & Boot & Debug 模式
    .io_pads_aon_erst_n_i_ival        (ck_rst_n),
    .io_pads_aon_pmu_dwakeup_n_i_ival (dut_io_pads_aon_pmu_dwakeup_n_i_ival),
    .io_pads_aon_pmu_vddpaden_o_oval  (dut_io_pads_aon_pmu_vddpaden_o_oval),
    .io_pads_aon_pmu_padrst_o_oval    (dut_io_pads_aon_pmu_padrst_o_oval),

    .io_pads_bootrom_n_i_ival         (dut_io_pads_bootrom_n_i_ival),

    .io_pads_dbgmode0_n_i_ival        (dut_io_pads_dbgmode0_n_i_ival),
    .io_pads_dbgmode1_n_i_ival        (dut_io_pads_dbgmode1_n_i_ival),
    .io_pads_dbgmode2_n_i_ival        (dut_io_pads_dbgmode2_n_i_ival)
);

endmodule
