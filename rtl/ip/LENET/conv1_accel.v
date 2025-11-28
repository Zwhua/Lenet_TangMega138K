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

    // 来自 ICB 外设模块的 buffer
    input  wire signed [7:0]  input_buf  [0:IN_CH*IN_SIZE*IN_SIZE-1],
    input  wire signed [7:0]  weight_buf [0:OUT_CH*IN_CH*K*K-1],
    input  wire signed [31:0] bias_buf   [0:OUT_CH-1],
    output reg  signed [31:0] output_buf [0:OUT_CH*OUT_SIZE*OUT_SIZE-1]
);

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
                            output_buf[out_index] = acc;

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
