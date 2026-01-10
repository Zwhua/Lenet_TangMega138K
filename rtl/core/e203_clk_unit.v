

/****************************************************************
========Oooo=========================================Oooo========
=     Copyright ©2015-2018 Gowin Semiconductor Corporation.     =
=                     All rights reserved.                      =
========Oooo=========================================Oooo========

<File Title>: IP file
<gwModGen version>: 1.8.0Beta
<Series, Device, Package, Speed>: GW2A, GW2A-55, PBGA484
<Created Time>: Thu Jun 14 18:00:03 2018
****************************************************************/

module clk_unit (clkout_rtc, reset, clkin, clkout_system, lock);

output clkout_rtc;
input reset;      // reset_n (active-low), 与 e203_soc_demo.v 的 erstn 保持一致
input clkin;      // 板上 USR_CLK_IN: 27MHz
output clkout_system;
output lock;

wire rst;
wire pll_clk;

assign rst = ~reset;

// 138K PLL：由 Gowin IP 生成 (GW5AST-138)，输入 27MHz
Gowin_PLL u_pll (
    .clkin(clkin),
    .init_clk(clkin),
    .clkout0(pll_clk)
);

assign clkout_system = pll_clk;
assign lock = 1'b1;

// 低频时钟：从 30MHz 分频得到约 32.77kHz，供 lfextclk 使用
localparam integer RTC_DIV = 458; // fout ~= 30MHz/(2*458) ≈ 32.75kHz
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
