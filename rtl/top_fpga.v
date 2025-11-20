module top_fpga(
    input   clk_50m,      // 板载 50MHz 晶振
    input   rst_n_board,  // 板载复位按键
    input   uart_rx,      // USB-TTL RX
    output  uart_tx,      // USB-TTL TX
    // ... 其他引脚
);

    wire clk_16m;
    wire pll_lock;

    // 实例化 PLL
    Gowin_PLL u_pll (
        .clkin    (clk_50m),   // 板载 50MHz 晶振
        .init_clk (clk_50m),   // 初始化时钟，直接连 50MHz 即可
        .lock     (pll_lock),  // 连接到 lock 信号
        .clkout0  (clk_16m)    // 输出给 E203 的 16MHz
    );

    // 生成系统复位信号：只有当 板载复位按键没按下(1) 且 PLL锁定(1) 时，系统才工作
    // 也就是：任何一个为 0，系统就复位
    wire sys_rst_n = rst_n_board & pll_lock;

    // 3. 实例化 E203 SoC Top
    e203_soc_top u_soc_top(
        .hfext_clk(clk_16m),   // 使用 PLL 输出的 16MHz
        .hfxosc_en(1'b1),
        .rst_n(sys_rst_n),     // 使用带 PLL 保护的复位信号
        // ...其他信号
        .io_pads_uart0_rxd_i_ival(uart_rx),
        .io_pads_uart0_txd_o_oval(uart_tx)
    );

endmodule