`timescale 1ns/10ps

module tb_top;

  reg  clk;
  reg  rst_n; // 低电平复位

  // 1. 时钟生成 (50MHz)
  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end

  // 2. 复位逻辑
  initial begin
    rst_n = 0;
    #200 rst_n = 1;
  end

  // 3. 实例化 SoC 顶层
  // 注意：根据你的 top_fpga.v 或 e203_soc_top.v 的端口进行连接
  // 这里假设实例化 e203_soc_top
  
  wire uart0_tx;
  
  e203_soc_top u_soc (
    .hfextclk (clk),   // 外部高频时钟
    .hfxoscen (),      // 晶振使能 (仿真可忽略)
    .lfextclk (clk),   // 低频时钟 (复用)
    .lfxoscen (),
    
    .io_pads_jtag_TCK_i_ival (1'b0),
    .io_pads_jtag_TMS_i_ival (1'b0),
    .io_pads_jtag_TDI_i_ival (1'b0),
    //.io_pads_jtag_TRST_n_i_ival (1'b1),
    .io_pads_jtag_TDO_o_oval (),

    .io_pads_gpioA_i_ival (32'b0),
    .io_pads_gpioA_o_oval (),
    .io_pads_gpioA_o_oe   (),

    .io_pads_qspi0_sck_o_oval (),
    .io_pads_qspi0_cs_0_o_oval (),
    // ... 其他端口根据需要连接，未用到的输出悬空，输入接地 ...
    
    .io_pads_aon_erst_n_i_ival (rst_n) // 核心复位信号
  );

  // 4. 加载固件到 ITCM
  initial begin
    // 这里的路径必须指向你编译生成的 hex 文件
    // 如果没有编译好的文件，仿真将无法执行有效代码
    $display("Loading firmware...");
    // 路径根据实际情况修改，E203 ITCM 通常是 64位宽
    // 注意：你需要找到 e203_itcm_ram.v 里的 reg 定义路径
    // 通常 E203 的 ITCM 路径比较深，如下：
    // $readmemh("firmware/app/Debug/e203.verilog", u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_itcm_ctrl.u_e203_itcm_ram.mem_r);
  end

  // 5. 监控输出
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_top);
    // 运行一段时间后停止
    #1000000 $finish;
  end


endmodule