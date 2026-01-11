`timescale 1ns / 1ps
//==============================================================================
// LeNet 完整加速器顶层模块
// 包含:
//   - Conv1: 1x28x28 -> 6x24x24 (5x5 kernel)
//   - FC1:   400 -> 120 (用于演示，实际LeNet需要池化后输入)
//   
// 地址映射:
//   Conv1: 0x10035000 - 0x10038FFF
//   FC1:   0x10039000 - 0x1006AFFF
//==============================================================================
module lenet_accel_top #(
    // Conv1 参数
    parameter CONV1_IN_CH   = 1,
    parameter CONV1_OUT_CH  = 6,
    parameter CONV1_IN_SIZE = 28,
    parameter CONV1_K       = 5,
    
    // FC1 参数 (简化版: 输入400，输出120)
    parameter FC1_IN_SIZE   = 400,
    parameter FC1_OUT_SIZE  = 120
)(
    input  wire        clk,
    input  wire        rst_n,

    // ===========================
    // ICB Slave Interface
    // ===========================
    input  wire        i_icb_cmd_valid,
    output wire        i_icb_cmd_ready,
    input  wire [31:0] i_icb_cmd_addr,
    input  wire        i_icb_cmd_read,
    input  wire [31:0] i_icb_cmd_wdata,
    
    output wire        i_icb_rsp_valid, 
    input  wire        i_icb_rsp_ready,
    output wire [31:0] i_icb_rsp_rdata,  
    output wire        i_icb_rsp_err    
);

    // ===========================
    // 地址范围定义
    // ===========================
    localparam CONV1_BASE = 32'h1003_5000;
    localparam CONV1_END  = 32'h1003_8FFF;
    
    localparam FC1_BASE   = 32'h1003_9000;
    localparam FC1_END    = 32'h1006_AFFF;
    
    // ===========================
    // 地址解码
    // ===========================
    wire addr_is_conv1 = (i_icb_cmd_addr >= CONV1_BASE) && (i_icb_cmd_addr <= CONV1_END);
    wire addr_is_fc1   = (i_icb_cmd_addr >= FC1_BASE)   && (i_icb_cmd_addr <= FC1_END);
    
    // ===========================
    // Conv1 模块信号
    // ===========================
    wire        conv1_cmd_valid = i_icb_cmd_valid && addr_is_conv1;
    wire        conv1_cmd_ready;
    wire        conv1_rsp_valid;
    wire [31:0] conv1_rsp_rdata;
    wire        conv1_rsp_err;
    
    // ===========================
    // FC1 模块信号
    // ===========================
    wire        fc1_cmd_valid = i_icb_cmd_valid && addr_is_fc1;
    wire        fc1_cmd_ready;
    wire        fc1_rsp_valid;
    wire [31:0] fc1_rsp_rdata;
    wire        fc1_rsp_err;
    
    // ===========================
    // 响应仲裁
    // ===========================
    assign i_icb_cmd_ready = addr_is_conv1 ? conv1_cmd_ready :
                             addr_is_fc1   ? fc1_cmd_ready   : 1'b1;
                             
    assign i_icb_rsp_valid = addr_is_conv1 ? conv1_rsp_valid :
                             addr_is_fc1   ? fc1_rsp_valid   : i_icb_cmd_valid;
                             
    assign i_icb_rsp_rdata = addr_is_conv1 ? conv1_rsp_rdata :
                             addr_is_fc1   ? fc1_rsp_rdata   : 32'h0;
                             
    assign i_icb_rsp_err   = addr_is_conv1 ? conv1_rsp_err :
                             addr_is_fc1   ? fc1_rsp_err   : 1'b0;

    // ===========================
    // Conv1 实例化
    // ===========================
    conv1_accel_icb #(
        .IN_CH(CONV1_IN_CH),
        .OUT_CH(CONV1_OUT_CH),
        .IN_SIZE(CONV1_IN_SIZE),
        .K(CONV1_K)
    ) u_conv1 (
        .clk(clk),
        .rst_n(rst_n),
        
        .i_icb_cmd_valid(conv1_cmd_valid),
        .i_icb_cmd_ready(conv1_cmd_ready),
        .i_icb_cmd_addr(i_icb_cmd_addr),
        .i_icb_cmd_read(i_icb_cmd_read),
        .i_icb_cmd_wdata(i_icb_cmd_wdata),
        
        .i_icb_rsp_valid(conv1_rsp_valid),
        .i_icb_rsp_ready(i_icb_rsp_ready),
        .i_icb_rsp_rdata(conv1_rsp_rdata),
        .i_icb_rsp_err(conv1_rsp_err)
    );

    // ===========================
    // FC1 实例化
    // ===========================
    fc_accel_icb #(
        .IN_SIZE(FC1_IN_SIZE),
        .OUT_SIZE(FC1_OUT_SIZE),
        .BASE_ADDR(FC1_BASE)
    ) u_fc1 (
        .clk(clk),
        .rst_n(rst_n),
        
        .i_icb_cmd_valid(fc1_cmd_valid),
        .i_icb_cmd_ready(fc1_cmd_ready),
        .i_icb_cmd_addr(i_icb_cmd_addr),
        .i_icb_cmd_read(i_icb_cmd_read),
        .i_icb_cmd_wdata(i_icb_cmd_wdata),
        
        .i_icb_rsp_valid(fc1_rsp_valid),
        .i_icb_rsp_ready(i_icb_rsp_ready),
        .i_icb_rsp_rdata(fc1_rsp_rdata),
        .i_icb_rsp_err(fc1_rsp_err)
    );

endmodule
