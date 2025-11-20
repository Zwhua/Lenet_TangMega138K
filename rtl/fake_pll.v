module PLL (
    input CLKIN,
    output CLKOUT,
    output CLKOUTP,
    output CLKOUTD,
    output CLKOUTD3,
    output LOCK,
    input RESET,
    input RESET_P,
    input RESET_I,      // 之前报错缺失的端口
    input RESET_S,      // 之前报错缺失的端口
    input CLKFB,
    input [5:0] FBDSEL, // 之前报错位宽不匹配，修正为 [5:0]
    input [5:0] IDSEL,
    input [5:0] ODSEL,
    input [3:0] PSDA,   // 修正为 [3:0]
    input [3:0] DUTYDA, // 修正为 [3:0]
    input [3:0] FDLY    // 修正为 [3:0]
);
    // 忽略所有参数
    parameter integer FCLKIN = 0;
    parameter integer DYN_IDIV_SEL = 0;
    parameter integer IDIV_SEL = 0;
    parameter integer DYN_FBDIV_SEL = 0;
    parameter integer FBDIV_SEL = 0;
    parameter integer DYN_ODIV_SEL = 0;
    parameter integer ODIV_SEL = 0;
    parameter integer PSDA_SEL = 0;
    parameter integer DYN_DA_EN = 0;
    parameter integer DUTYDA_SEL = 0;
    parameter integer CLKOUT_FT_DIR = 0;
    parameter integer CLKOUTP_FT_DIR = 0;
    parameter integer CLKOUT_DLY_STEP = 0;
    parameter integer CLKOUTP_DLY_STEP = 0;
    parameter integer CLKFB_SEL = 0;
    parameter integer CLKOUT_BYPASS = 0;
    parameter integer CLKOUTP_BYPASS = 0;
    parameter integer CLKOUTD_BYPASS = 0;
    parameter integer DYN_SDIV_SEL = 0;
    parameter integer CLKOUTD_SRC = 0;
    parameter integer CLKOUTD3_SRC = 0;
    parameter DEVICE = "";

    // 核心逻辑：直连 (Bypass)
    assign CLKOUT   = CLKIN;
    assign CLKOUTP  = CLKIN;
    assign CLKOUTD  = CLKIN;
    assign CLKOUTD3 = CLKIN;
    assign LOCK     = 1'b1; // 假装 PLL 已经锁定
endmodule

// 保留这个空模块以防万一
module gowin_pll(output clkout, input clkin); 
    assign clkout = clkin; 
endmodule