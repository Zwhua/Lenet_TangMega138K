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
    localparam ADDR_CTRL      = 32'h1003_5000;
    localparam ADDR_STATUS    = 32'h1003_5004;

    localparam ADDR_INPUT     = 32'h1003_5010;
    localparam ADDR_WEIGHT    = 32'h1003_6000;
    localparam ADDR_BIAS      = 32'h1003_7000;
    localparam ADDR_OUTPUT    = 32'h1003_8000;

    localparam INPUT_SIZE  = IN_CH*IN_SIZE*IN_SIZE;
    localparam WEIGHT_SIZE = OUT_CH*IN_CH*K*K;
    localparam BIAS_SIZE   = OUT_CH;
    localparam OUTPUT_SIZE = OUT_CH*OUT_SIZE*OUT_SIZE;

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
    // 生成写通道（写入 conv1_accel 内部 buffer）
    // ===========================
    localparam integer IN_AW  = $clog2(INPUT_SIZE);
    localparam integer W_AW   = $clog2(WEIGHT_SIZE);
    localparam integer B_AW   = $clog2(BIAS_SIZE);
    localparam integer OUT_AW = $clog2(OUTPUT_SIZE);

    wire addr_is_input  = (i_icb_cmd_addr >= ADDR_INPUT)  && (i_icb_cmd_addr < (ADDR_INPUT  + INPUT_SIZE*4));
    wire addr_is_weight = (i_icb_cmd_addr >= ADDR_WEIGHT) && (i_icb_cmd_addr < (ADDR_WEIGHT + WEIGHT_SIZE*4));
    wire addr_is_bias   = (i_icb_cmd_addr >= ADDR_BIAS)   && (i_icb_cmd_addr < (ADDR_BIAS   + BIAS_SIZE*4));
    wire addr_is_output = (i_icb_cmd_addr >= ADDR_OUTPUT) && (i_icb_cmd_addr < (ADDR_OUTPUT + OUTPUT_SIZE*4));

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
    // 写寄存器/写 buffer
    // ===========================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_reg <= 0;
        end else if (write_en) begin
            // 写 CTRL
            if (i_icb_cmd_addr == ADDR_CTRL) begin
                start_reg <= i_icb_cmd_wdata[0];
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
            i_icb_rsp_err   <= 0;
        end else begin
            i_icb_rsp_valid <= i_icb_cmd_valid;
            i_icb_rsp_err   <= 1'b0;

            if (read_en) begin
                // STATUS 寄存器
                if (i_icb_cmd_addr == ADDR_STATUS) begin
                    i_icb_rsp_rdata <= {31'b0, done_reg};
                end

                // 输出 buffer 读取
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
