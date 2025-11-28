`timescale 1ns / 1ps
module conv1_accel_icb #(
    parameter IN_CH    = 1,
    parameter OUT_CH   = 6,
    parameter IN_SIZE  = 28,
    parameter K        = 5,
    parameter OUT_SIZE = IN_SIZE - K + 1,

    parameter ICB_RW_ADDR_W = 32,
    parameter ICB_RW_DATA_W = 32
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // ===========================
    // ICB Slave Interface
    // ===========================
    input  wire        i_icb_cmd_valid,
    output wire        i_icb_cmd_ready,
    input  wire [31:0] i_icb_cmd_addr,
    input  wire        i_icb_cmd_read,
    input  wire [31:0] i_icb_cmd_wdata,
    
    // ICB 响应通道
    output reg         i_icb_rsp_valid, 
    input  wire        i_icb_rsp_ready,
    output reg  [31:0] i_icb_rsp_rdata,  
    output reg         i_icb_rsp_err    
);

    // ===========================
    // 地址映射
    // ===========================
    localparam ADDR_CTRL      = 32'h0000_0000;
    localparam ADDR_STATUS    = 32'h0000_0004;

    localparam ADDR_INPUT     = 32'h0000_0010;
    localparam ADDR_WEIGHT    = 32'h0000_1000;
    localparam ADDR_BIAS      = 32'h0000_2000;
    localparam ADDR_OUTPUT    = 32'h0000_3000;

    localparam INPUT_SIZE  = IN_CH*IN_SIZE*IN_SIZE;
    localparam WEIGHT_SIZE = OUT_CH*IN_CH*K*K;
    localparam BIAS_SIZE   = OUT_CH;
    localparam OUTPUT_SIZE = OUT_CH*OUT_SIZE*OUT_SIZE;

    // ===========================
    // 内部 Buffer
    // ===========================
    reg signed [7:0]  input_buf  [0:INPUT_SIZE-1];
    reg signed [7:0]  weight_buf [0:WEIGHT_SIZE-1];
    reg signed [31:0] bias_buf   [0:BIAS_SIZE-1];
    reg signed [31:0] output_buf [0:OUTPUT_SIZE-1];

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
    // 写寄存器/写 buffer
    // ===========================
    integer idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_reg <= 0;
        end else if (write_en) begin
            // 写 CTRL
            if (i_icb_cmd_addr == ADDR_CTRL) begin
                start_reg <= i_icb_cmd_wdata[0];
            end

            // 写输入 feature map
            else if (i_icb_cmd_addr >= ADDR_INPUT &&
                    i_icb_cmd_addr <  ADDR_INPUT + INPUT_SIZE*4) begin
                idx = (i_icb_cmd_addr - ADDR_INPUT) >> 2;
                if (idx < INPUT_SIZE)
                    input_buf[idx] <= i_icb_cmd_wdata[7:0];
            end

            // 写权重
            else if (i_icb_cmd_addr >= ADDR_WEIGHT &&
                    i_icb_cmd_addr <  ADDR_WEIGHT + WEIGHT_SIZE*4) begin
                idx = (i_icb_cmd_addr - ADDR_WEIGHT) >> 2;
                if (idx < WEIGHT_SIZE)
                    weight_buf[idx] <= i_icb_cmd_wdata[7:0];
            end

            // 写 bias
            else if (i_icb_cmd_addr >= ADDR_BIAS &&
                    i_icb_cmd_addr <  ADDR_BIAS + BIAS_SIZE*4) begin
                idx = (i_icb_cmd_addr - ADDR_BIAS) >> 2;
                if (idx < BIAS_SIZE)
                    bias_buf[idx] <= i_icb_cmd_wdata;
            end
        end
    end

    // ===========================
    // ICB 读寄存器/读 buffer
    // ===========================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_icb_rsp_valid <= 0;
            i_icb_rsp_rdata <= 0;
            i_icb_rsp_err   <= 0;  // 修复: 初始化
        end else begin
            i_icb_rsp_valid <= read_en;
            i_icb_rsp_err   <= 1'b0;  // 修复: 赋值为0

            if (read_en) begin
                // STATUS 寄存器
                if (i_icb_cmd_addr == ADDR_STATUS) begin
                    i_icb_rsp_rdata <= {31'b0, done_reg};
                end

                // 输出 buffer 读取
                else if (i_icb_cmd_addr >= ADDR_OUTPUT &&
                         i_icb_cmd_addr <  ADDR_OUTPUT + OUTPUT_SIZE*4) begin
                    idx = (i_icb_cmd_addr - ADDR_OUTPUT) >> 2;
                    if (idx < OUTPUT_SIZE)
                        i_icb_rsp_rdata <= output_buf[idx];
                    else
                        i_icb_rsp_rdata <= 32'hDEAD_BEEF;
                end

                else begin
                    i_icb_rsp_rdata <= 32'h0;
                end
            end
        end
    end

    // ===========================
    // 卷积引擎实例化
    // ===========================
    wire accel_done;

    conv1_accel #(
        .IN_CH(IN_CH),
        .OUT_CH(OUT_CH),
        .IN_SIZE(IN_SIZE),
        .K(K)
    ) u_accel (
        .clk(clk),
        .rst(!rst_n),           // 高电平复位
        .start(start_reg),
        .done(accel_done),

        .input_buf(input_buf),
        .weight_buf(weight_buf),
        .bias_buf(bias_buf),
        .output_buf(output_buf)
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
