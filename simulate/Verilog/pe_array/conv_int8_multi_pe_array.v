// ==========================================================
//iverilog -g2012 -o tb_conv_multi_pe_array tb_conv_multi_pe_array.v conv_int8_multi_pe_array.v
//vvp tb_conv_multi_pe_array
//gtkwave tb_conv_multi_pe_array.vcd
// ==========================================================
`timescale 1ns / 1ps
module conv_int8_multi_pe_array #(
    parameter IN_CH   = 2,
    parameter OUT_CH  = 3,
    parameter IN_SIZE = 8,
    parameter K       = 3,
    parameter OUT_SIZE= IN_SIZE - K + 1,
    parameter PE_ROWS = 2,
    parameter PE_COLS = 2
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    output reg  done,

    input  wire signed [7:0] input_fm_flat [0:IN_CH*IN_SIZE*IN_SIZE-1],
    input  wire signed [7:0] weight_flat   [0:OUT_CH*IN_CH*K*K-1],
    output reg  signed [31:0] output_fm_flat[0:OUT_CH*OUT_SIZE*OUT_SIZE-1]
);

    typedef enum logic [1:0] {IDLE, CALC, DONE} state_t;
    state_t state;

    integer oc, ic, i, j, m, n, r, c;
    integer in_idx, wt_idx, out_idx;

    // 动态数组：每个 PE 一个累加器
    reg signed [31:0] acc [0:PE_ROWS*PE_COLS-1];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            done  <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        oc <= 0; i <= 0; j <= 0;
                        state <= CALC;
                    end
                end

                CALC: begin
                    // 初始化并行累加器
                    for (r = 0; r < PE_ROWS*PE_COLS; r = r + 1)
                        acc[r] = 0;

                    // 多输入通道卷积累加
                    for (ic = 0; ic < IN_CH; ic = ic + 1)
                        for (m = 0; m < K; m = m + 1)
                            for (n = 0; n < K; n = n + 1) begin
                                wt_idx = oc*IN_CH*K*K + ic*K*K + m*K + n;

                                // 遍历每个PE的偏移
                                for (r = 0; r < PE_ROWS; r = r + 1)
                                    for (c = 0; c < PE_COLS; c = c + 1) begin
                                        in_idx = ic*IN_SIZE*IN_SIZE +
                                                 (i + r + m)*IN_SIZE + (j + c + n);
                                        acc[r*PE_COLS + c] =
                                            acc[r*PE_COLS + c] + input_fm_flat[in_idx] * weight_flat[wt_idx];
                                    end
                            end

                    // 写回输出
                    for (r = 0; r < PE_ROWS; r = r + 1)
                        for (c = 0; c < PE_COLS; c = c + 1) begin
                            if ((i + r < OUT_SIZE) && (j + c < OUT_SIZE)) begin
                                out_idx = oc*OUT_SIZE*OUT_SIZE +
                                          (i + r)*OUT_SIZE + (j + c);
                                output_fm_flat[out_idx] <= acc[r*PE_COLS + c];
                            end
                        end

                    // 步进逻辑（按阵列大小推进）
                    if (j < OUT_SIZE - PE_COLS) j <= j + PE_COLS;
                    else begin
                        j <= 0;
                        if (i < OUT_SIZE - PE_ROWS) i <= i + PE_ROWS;
                        else begin
                            i <= 0;
                            if (oc < OUT_CH - 1) oc <= oc + 1;
                            else state <= DONE;
                        end
                    end
                end

                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
