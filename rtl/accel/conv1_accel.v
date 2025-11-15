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
        end else begin
            case (state)

            // ==========================================
            // IDLE：等待 CPU 启动
            // ==========================================
            S_IDLE: begin
                done <= 0;
                if (start) begin
                    state <= S_RUN;
                end
            end

            // ==========================================
            // RUN：核心卷积计算
            // （逐点扫描版本）
            // ==========================================
            S_RUN: begin

                // 遍历 OUT_CH × OUT_SIZE × OUT_SIZE
                for (oc = 0; oc < OUT_CH; oc = oc + 1) begin
                    for (i = 0; i < OUT_SIZE; i = i + 1) begin
                        for (j = 0; j < OUT_SIZE; j = j + 1) begin

                            // 初始化 acc = bias
                            acc = bias_buf[oc];

                            // 卷积 K×K
                            for (ic = 0; ic < IN_CH; ic = ic + 1) begin
                                for (m = 0; m < K; m = m + 1) begin
                                    for (n = 0; n < K; n = n + 1) begin

                                        // input index (HWC → flat)
                                        in_index =
                                            ic*IN_SIZE*IN_SIZE +
                                            (i+m)*IN_SIZE +
                                            (j+n);

                                        // weight index (OICHW → flat)
                                        w_index =
                                            oc*(IN_CH*K*K) +
                                            ic*(K*K) +
                                            m*K +
                                            n;

                                        acc = acc +
                                              input_buf[in_index] *
                                              weight_buf[w_index];
                                    end
                                end
                            end

                            // 写到输出
                            out_index =
                                oc*(OUT_SIZE*OUT_SIZE) +
                                i*OUT_SIZE +
                                j;

                            output_buf[out_index] <= acc;
                        end
                    end
                end

                state <= S_DONE;
            end

            // ==========================================
            // DONE：告诉 CPU 计算完成
            // ==========================================
            S_DONE: begin
                done  <= 1;
                state <= S_IDLE;
            end

            endcase
        end
    end

endmodule
