// ==========================================================
// Multi-Input INT8 Convolution Module (Flattened port version)
// Compatible with Icarus Verilog
// ==========================================================
`timescale 1ns / 1ps
module conv_int8_multi_flat #(
    parameter IN_CH = 2,
    parameter OUT_CH = 3,
    parameter IN_SIZE = 8,
    parameter K = 3,
    parameter OUT_SIZE = IN_SIZE - K + 1
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 start,
    output reg                  done,

    // 展平后的端口：全部是一维数组
    input  wire signed [7:0] input_fm_flat [0:IN_CH*IN_SIZE*IN_SIZE-1],
    input  wire signed [7:0] weight_flat   [0:OUT_CH*IN_CH*K*K-1],
    input  wire signed [31:0] bias_flat [0:OUT_CH-1],
    output reg  signed [31:0] output_fm_flat[0:OUT_CH*OUT_SIZE*OUT_SIZE-1]
);

    typedef enum logic [1:0] {IDLE, CALC, DONE} state_t;
    state_t state;

    integer oc, ic, i, j, m, n;
    integer in_idx, wt_idx, out_idx;
    reg signed [31:0] acc;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            done  <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        oc <= 0; ic <= 0; i <= 0; j <= 0;
                        state <= CALC;
                    end
                end

                CALC: begin
                    acc = 0;
                    // 多输入通道卷积累加
                    for (ic=0; ic<IN_CH; ic=ic+1)
                        for (m=0; m<K; m=m+1)
                            for (n=0; n<K; n=n+1) begin
                                in_idx = ic*IN_SIZE*IN_SIZE + (i+m)*IN_SIZE + (j+n);
                                wt_idx = oc*IN_CH*K*K + ic*K*K + m*K + n;
                                acc = acc + input_fm_flat[in_idx] * weight_flat[wt_idx] ;
                            end
                    acc = acc + bias_flat[oc];
                    out_idx = oc*OUT_SIZE*OUT_SIZE + i*OUT_SIZE + j;
                    output_fm_flat[out_idx] <= acc;

                    // 遍历计数
                    if (j < OUT_SIZE-1) j <= j + 1;
                    else begin
                        j <= 0;
                        if (i < OUT_SIZE-1) i <= i + 1;
                        else begin
                            i <= 0;
                            if (oc < OUT_CH-1) oc <= oc + 1;
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
