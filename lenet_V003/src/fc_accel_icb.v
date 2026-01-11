`timescale 1ns / 1ps
//==============================================================================
// 全连接层 ICB 接口包装模块
// 将FC加速器连接到SoC的ICB总线
//==============================================================================
module fc_accel_icb #(
    parameter IN_SIZE  = 400,    // 输入向量长度
    parameter OUT_SIZE = 120,    // 输出向量长度
    
    // 基地址 (可配置不同FC层使用不同地址)
    parameter BASE_ADDR = 32'h1003_9000
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
    
    output reg         i_icb_rsp_valid, 
    input  wire        i_icb_rsp_ready,
    output reg  [31:0] i_icb_rsp_rdata,  
    output reg         i_icb_rsp_err    
);

    // ===========================
    // 地址映射 (相对于BASE_ADDR的偏移)
    // ===========================
    // CTRL:   BASE + 0x0000
    // STATUS: BASE + 0x0004
    // INPUT:  BASE + 0x0010  (IN_SIZE * 4 bytes)
    // WEIGHT: BASE + 0x1000  (IN_SIZE * OUT_SIZE * 4 bytes)
    // BIAS:   BASE + 0x30000 (OUT_SIZE * 4 bytes, 给足够空间存放权重)
    // OUTPUT: BASE + 0x31000 (OUT_SIZE * 4 bytes)
    
    localparam ADDR_CTRL   = BASE_ADDR + 32'h0000;
    localparam ADDR_STATUS = BASE_ADDR + 32'h0004;
    localparam ADDR_INPUT  = BASE_ADDR + 32'h0010;
    localparam ADDR_WEIGHT = BASE_ADDR + 32'h1000;
    // 权重大小: IN_SIZE * OUT_SIZE * 4, 例如 400*120*4 = 192000 = 0x2EE00
    // 所以bias需要放在权重之后足够远的位置
    localparam ADDR_BIAS   = BASE_ADDR + 32'h30000;
    localparam ADDR_OUTPUT = BASE_ADDR + 32'h31000;

    localparam WEIGHT_SIZE = IN_SIZE * OUT_SIZE;

    // CTRL/STATUS
    reg start_reg;
    reg done_reg;

    // ===========================
    // ICB 接收握手
    // ===========================
    assign i_icb_cmd_ready = 1'b1;

    wire write_en = i_icb_cmd_valid && !i_icb_cmd_read;
    wire read_en  = i_icb_cmd_valid &&  i_icb_cmd_read;

    // ===========================
    // 地址解码
    // ===========================
    localparam integer IN_AW  = $clog2(IN_SIZE);
    localparam integer W_AW   = $clog2(WEIGHT_SIZE);
    localparam integer B_AW   = $clog2(OUT_SIZE);
    localparam integer OUT_AW = $clog2(OUT_SIZE);

    wire addr_is_input  = (i_icb_cmd_addr >= ADDR_INPUT)  && (i_icb_cmd_addr < (ADDR_INPUT  + IN_SIZE*4));
    wire addr_is_weight = (i_icb_cmd_addr >= ADDR_WEIGHT) && (i_icb_cmd_addr < (ADDR_WEIGHT + WEIGHT_SIZE*4));
    wire addr_is_bias   = (i_icb_cmd_addr >= ADDR_BIAS)   && (i_icb_cmd_addr < (ADDR_BIAS   + OUT_SIZE*4));
    wire addr_is_output = (i_icb_cmd_addr >= ADDR_OUTPUT) && (i_icb_cmd_addr < (ADDR_OUTPUT + OUT_SIZE*4));

    wire input_we  = write_en && addr_is_input;
    wire weight_we = write_en && addr_is_weight;
    wire bias_we   = write_en && addr_is_bias;

    wire [IN_AW-1:0]  input_waddr  = (i_icb_cmd_addr - ADDR_INPUT)  >> 2;
    wire [W_AW-1:0]   weight_waddr = (i_icb_cmd_addr - ADDR_WEIGHT) >> 2;
    wire [B_AW-1:0]   bias_waddr   = (i_icb_cmd_addr - ADDR_BIAS)   >> 2;

    wire signed [7:0]  input_wdata  = i_icb_cmd_wdata[7:0];
    wire signed [7:0]  weight_wdata = i_icb_cmd_wdata[7:0];
    wire signed [31:0] bias_wdata   = i_icb_cmd_wdata;

    wire [OUT_AW-1:0] output_raddr = (i_icb_cmd_addr - ADDR_OUTPUT) >> 2;
    wire signed [31:0] output_rdata;

    // ===========================
    // 写 CTRL 寄存器
    // ===========================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_reg <= 0;
        end else if (write_en) begin
            if (i_icb_cmd_addr == ADDR_CTRL) begin
                start_reg <= i_icb_cmd_wdata[0];
            end
        end
    end

    // ===========================
    // ICB 读响应
    // ===========================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_icb_rsp_valid <= 0;
            i_icb_rsp_rdata <= 0;
            i_icb_rsp_err   <= 0;
        end else begin
            i_icb_rsp_valid <= i_icb_cmd_valid;
            i_icb_rsp_err   <= 1'b0;

            if (read_en) begin
                if (i_icb_cmd_addr == ADDR_STATUS) begin
                    i_icb_rsp_rdata <= {31'b0, done_reg};
                end
                else if (addr_is_output) begin
                    i_icb_rsp_rdata <= output_rdata;
                end
                else begin
                    i_icb_rsp_rdata <= 32'h0;
                end
            end else begin
                i_icb_rsp_rdata <= 32'h0;
            end
        end
    end

    // ===========================
    // FC 引擎实例化
    // ===========================
    wire accel_done;

    fc_accel #(
        .IN_SIZE(IN_SIZE),
        .OUT_SIZE(OUT_SIZE)
    ) u_fc_accel (
        .clk(clk),
        .rst(!rst_n),
        .start(start_reg),
        .done(accel_done),

        .input_we(input_we),
        .input_waddr(input_waddr),
        .input_wdata(input_wdata),

        .weight_we(weight_we),
        .weight_waddr(weight_waddr),
        .weight_wdata(weight_wdata),

        .bias_we(bias_we),
        .bias_waddr(bias_waddr),
        .bias_wdata(bias_wdata),

        .output_raddr(output_raddr),
        .output_rdata(output_rdata)
    );

    // ===========================
    // done 信号
    // ===========================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            done_reg <= 0;
        else 
            done_reg <= accel_done;
    end

endmodule
