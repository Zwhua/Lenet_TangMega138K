`timescale 1ns/10ps

module tb_top;

  reg  clk;
  reg  rst_n;

  // 1. 时钟生成 (16MHz)
  initial begin
    clk = 0;
    forever #31.25 clk = ~clk; 
  end

  // 2. 复位逻辑
  initial begin
    rst_n = 0;
    #2000 rst_n = 1;
  end

  // 3. 信号连接
  wire [31:0] gpioA_out;
  wire [31:0] gpioA_en;
  wire uart0_tx;

  assign uart0_tx = gpioA_out[17];

  e203_soc_top u_soc (
    .hfextclk (clk),
    .hfxoscen (),
    .lfextclk (clk),
    .lfxoscen (),
    .io_pads_jtag_TCK_i_ival (1'b0),
    .io_pads_jtag_TMS_i_ival (1'b0),
    .io_pads_jtag_TDI_i_ival (1'b0),
    .io_pads_jtag_TDO_o_oval (),
    .io_pads_gpioA_i_ival (32'b0),
    .io_pads_gpioA_o_oval (gpioA_out),
    .io_pads_gpioA_o_oe   (gpioA_en),
    .io_pads_qspi0_sck_o_oval (),
    .io_pads_qspi0_cs_0_o_oval (),
    .io_pads_aon_erst_n_i_ival (rst_n)
  );

  // 4. 强力修复与深度诊断
  initial begin
    // 等待层级建立
    #100;
    
    $display("--- APPLYING FORCE FIXES ---");
    // [修复1] 强制 CPU Top 时钟和复位
    force u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.clk = clk;
    force u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.rst_n = rst_n;
    
     // [修复2] 强制 PC 寄存器的时钟
    force u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_ifu.u_e203_ifu_ifetch.pc_dfflr.clk = clk;
    force u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_ifu.u_e203_ifu_ifetch.pc_dfflr.rst_n = rst_n;

    // [修复3] 强制复位向量
    force u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_ifu.u_e203_ifu_ifetch.pc_rtvec = 32'h80000000;
    force u_soc.io_pads_bootrom_n_i_ival = 1'b1; 
    force u_soc.io_pads_dbgmode0_n_i_ival = 1'b1;
    force u_soc.io_pads_dbgmode1_n_i_ival = 1'b1;
    force u_soc.io_pads_dbgmode2_n_i_ival = 1'b1;
    force u_soc.io_pads_aon_pmu_dwakeup_n_i_ival = 1'b1;

    // [修复4 - 终极修正版]
    force u_soc.u_e203_subsys_top.u_e203_subsys_main.core_rst_n = rst_n;
    force u_soc.u_e203_subsys_top.u_e203_subsys_main.bus_rst_n = rst_n;

    // [修正路径]
    // 根据你的代码片段，itcm_ram 直接实例化了 sirv_sim_ram_itcm (没有 gnrl_ram 层)
    // 并且通常 itcm_ram 是在 itcm_ctrl 内部的
    force u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_itcm_ctrl.u_e203_itcm_ram.u_sirv_sim_ram_itcm.clk = clk;

    $display("Forces applied: CPU, ITCM RAM Clock (Path: Ctrl->Ram->Sim), Resets.");
  end

  // 5. 状态监视器
  initial begin
      $display("--- SIMULATION START (16MHz Clock) ---");
      #3000; // 等待复位释放
      
      forever begin
          #10000; // 每 10us 打印一次
          
          // 打印 PC 寄存器的详细状态：输入、输出、使能
          // pc_r: 当前 PC 值
          // dnxt: 下一跳 PC 值 (如果这个是 0，说明逻辑有问题)
          // lden: 加载使能 (如果是 0，PC 不会更新)
          $display("[Time: %0t] PC: %h | Next: %h | Enable: %b | UART: %b", 
            $time, 
            u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_ifu.u_e203_ifu_ifetch.pc_r,
            u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_ifu.u_e203_ifu_ifetch.pc_dfflr.dnxt,
            u_soc.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu.u_e203_core.u_e203_ifu.u_e203_ifu_ifetch.pc_dfflr.lden,
            uart0_tx
          );
      end
  end

  // 6. UART 打印解码器
  parameter UART_BAUD = 115200;
  parameter BIT_PERIOD = 1000000000 / UART_BAUD; 
  reg [7:0] rx_byte;
  initial begin
    forever begin
      @(negedge uart0_tx);
      #(BIT_PERIOD + (BIT_PERIOD / 2));
      rx_byte[0] = uart0_tx; #(BIT_PERIOD);
      rx_byte[1] = uart0_tx; #(BIT_PERIOD);
      rx_byte[2] = uart0_tx; #(BIT_PERIOD);
      rx_byte[3] = uart0_tx; #(BIT_PERIOD);
      rx_byte[4] = uart0_tx; #(BIT_PERIOD);
      rx_byte[5] = uart0_tx; #(BIT_PERIOD);
      rx_byte[6] = uart0_tx; #(BIT_PERIOD);
      rx_byte[7] = uart0_tx; #(BIT_PERIOD);
      $write("%c", rx_byte);
    end
  end

  // 7. 仿真控制
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_top);
    #2000000; 
    $display("\n--- SIMULATION TIMEOUT ---");
    $finish;
  end

endmodule