module clk_unit (clkout_rtc, reset, clkin, clkout_system, clkout_uart, lock);

output clkout_rtc;
input reset;    
input clkin;      // 板上 USR_CLK_IN: 25MHz
output clkout_system;
output clkout_uart;  // UART dedicated 24 MHz clock
output lock;

wire rst;
wire pll_clk;
wire uart_clk;  // 24 MHz for UART

assign rst = ~reset;

// 138K PLL：由 Gowin IP 生成 (GW5AST-138)，输入 25MHz
Gowin_PLL u_pll (
    .clkin(clkin),
    .init_clk(clkin),
    .clkout0(pll_clk),
    .clkout1(uart_clk)  // UART dedicated 24 MHz
);

assign clkout_system = pll_clk;
assign clkout_uart = uart_clk;
// NOTE: The current Gowin_PLL wrapper in this repo does not expose a lock/reset port.
// Keep the interface of clk_unit unchanged to avoid wider refactors.
assign lock = 1'b1;

// 低频时钟：从 25MHz 分频得到约 32.552kHz，供 lfextclk 使用
localparam integer RTC_DIV = 384; // fout ~= 25MHz/(2*384) = 32.552kHz
localparam integer RTC_CNT_W = $clog2(RTC_DIV);

reg [RTC_CNT_W-1:0] rtc_cnt = {RTC_CNT_W{1'b0}};
reg rtc_clk = 1'b0;

always @(posedge clkin or negedge reset) begin
    if (!reset) begin
        rtc_cnt <= {RTC_CNT_W{1'b0}};
        rtc_clk <= 1'b0;
    end else if (rtc_cnt == RTC_DIV - 1) begin
        rtc_cnt <= {RTC_CNT_W{1'b0}};
        rtc_clk <= ~rtc_clk;
    end else begin
        rtc_cnt <= rtc_cnt + 1'b1;
    end
end

assign clkout_rtc = rtc_clk;

endmodule
