`timescale 1ns / 1ps
module conv1_accel #(
    parameter IN_CH    = 1,
    parameter OUT_CH   = 6,
    parameter IN_SIZE  = 28,
    parameter K        = 5,
    parameter OUT_SIZE = IN_SIZE - K + 1
)(
    input wire clk,
    input wire rst,
    input wire start,
    output reg done,

    // CPU 写入 buffer（来自 ICB 外设模块的写通道）
    input  wire                      input_we,
    input  wire [$clog2(IN_CH*IN_SIZE*IN_SIZE)-1:0] input_waddr,
    input  wire signed [7:0]         input_wdata,

    input  wire                      weight_we,
    input  wire [$clog2(OUT_CH*IN_CH*K*K)-1:0]      weight_waddr,
    input  wire signed [7:0]         weight_wdata,

    input  wire                      bias_we,
    input  wire [$clog2(OUT_CH)-1:0] bias_waddr,
    input  wire signed [31:0]        bias_wdata,

    // CPU 读取输出 buffer
    input  wire [$clog2(OUT_CH*OUT_SIZE*OUT_SIZE)-1:0] output_raddr,
    output wire signed [31:0]        output_rdata
);

    localparam integer INPUT_SIZE  = IN_CH*IN_SIZE*IN_SIZE;
    localparam integer WEIGHT_SIZE = OUT_CH*IN_CH*K*K;
    localparam integer BIAS_SIZE   = OUT_CH;
    localparam integer OUTPUT_SIZE = OUT_CH*OUT_SIZE*OUT_SIZE;

    // ==========================================
    // 内部 Buffer (unpacked memory，放在模块内部综合可接受)
    // ==========================================
    reg signed [7:0]  input_buf  [0:INPUT_SIZE-1];
    reg signed [7:0]  weight_buf [0:WEIGHT_SIZE-1];
    reg signed [31:0] bias_buf   [0:BIAS_SIZE-1];
    reg signed [31:0] output_buf [0:OUTPUT_SIZE-1];

    // 输出 buffer 异步读（用于 MMIO 读回）
    assign output_rdata = (output_raddr < OUTPUT_SIZE) ? output_buf[output_raddr] : 32'hDEAD_BEEF;

    // 仿真时预加载真实数据
    `ifdef SIMULATION
        initial begin
            $readmemh("python/npy/input_image.mem", input_buf);
            $readmemh("python/npy/conv1_weight.mem", weight_buf);
            $readmemh("python/npy/conv1_bias.mem", bias_buf);
            $display("[INFO] LeNet Conv1: Loaded real weights from .mem files");
        end
    `endif

    // ==========================================
    // 状态机
    // ==========================================
    localparam S_IDLE = 0;
    localparam S_RUN  = 1;
    localparam S_DONE = 2;

    reg [1:0] state;

    // 卷积 index
    integer oc, ic, i, j, m, n;
    integer out_index;
    integer in_index;
    integer w_index;

    // accumulator
    reg signed [31:0] acc;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done  <= 0;
            oc <= 0; ic <= 0; i <= 0; j <= 0; m <= 0; n <= 0;
        end else begin
            // ==========================================
            // CPU 写 buffer（随时可写，和计算状态机解耦）
            // ==========================================
            if (input_we && (input_waddr < INPUT_SIZE))
                input_buf[input_waddr] <= input_wdata;
            if (weight_we && (weight_waddr < WEIGHT_SIZE))
                weight_buf[weight_waddr] <= weight_wdata;
            if (bias_we && (bias_waddr < BIAS_SIZE))
                bias_buf[bias_waddr] <= bias_wdata;

            case (state)

            // ==========================================
            // IDLE：等待 CPU 启动
            // ==========================================
            S_IDLE: begin
                done <= 0;
                if (start) begin
                    state <= S_RUN;
                    oc <= 0; ic <= 0; i <= 0; j <= 0; m <= 0; n <= 0;
                end
            end

            // ==========================================
            // RUN：核心卷积计算
            // （逐点扫描版本）
            // ==========================================
            S_RUN: begin
                // 卷积计算逻辑 (简化示例,实际需要多周期实现)
                // 这里假设单周期完成所有计算(仅用于快速验证)

                // 遍历所有输出通道和位置
                if (oc < OUT_CH) begin
                    if (i < OUT_SIZE) begin
                        if (j < OUT_SIZE) begin
                            // 计算一个输出
                            acc = bias_buf[oc];
                            for (ic = 0; ic < IN_CH; ic = ic + 1) begin
                                for (m = 0; m < K; m = m + 1) begin
                                    for (n = 0; n < K; n = n + 1) begin
                                        in_index = ic*IN_SIZE*IN_SIZE + (i+m)*IN_SIZE + (j+n);
                                        w_index = oc*IN_CH*K*K + ic*K*K + m*K + n;
                                        acc = acc + input_buf[in_index] * weight_buf[w_index];
                                    end
                                end
                            end
                            out_index = oc*OUT_SIZE*OUT_SIZE + i*OUT_SIZE + j;
                            output_buf[out_index] <= acc;

                            j = j + 1;
                        end else begin
                            j = 0;
                            i = i + 1;
                        end
                    end else begin
                        i = 0;
                        oc = oc + 1;
                    end
                end else begin
                    state <= S_DONE;
                end
            end

            // ==========================================
            // DONE：告诉 CPU 计算完成
            // ==========================================
            S_DONE: begin
                done <= 1;
                if (!start) begin
                    state <= S_IDLE;
                end
            end

            endcase
        end
    end

endmodule
