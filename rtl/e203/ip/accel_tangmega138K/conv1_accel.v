`timescale 1ns / 1ps
module conv1_accel #(
    parameter IN_CH    = 1,
    parameter OUT_CH   = 6,
    parameter IN_SIZE  = 28,
    parameter K        = 5,
    parameter OUT_SIZE = IN_SIZE - K + 1
)(
    input wire clk,
    input wire rst, // Active High
    
    // 控制接口
    input wire start,
    output reg done,
    output reg busy,

    // 内存映射接口 (用于读写内部 Buffer)
    input  wire [15:0] mem_addr,  // 字节偏移地址
    input  wire        mem_we,    // 写使能
    input  wire [31:0] mem_wdata, // 写数据
    output reg  [31:0] mem_rdata  // 读数据
);

    // ==========================================
    // 内部存储定义
    // ==========================================
    // 注意：这种全寄存器实现在FPGA上消耗资源巨大，仅适用于小规模演示
    reg signed [7:0]  input_buf  [0:IN_CH*IN_SIZE*IN_SIZE-1];
    reg signed [7:0]  weight_buf [0:OUT_CH*IN_CH*K*K-1];
    reg signed [31:0] bias_buf   [0:OUT_CH-1];
    reg signed [31:0] output_buf [0:OUT_CH*OUT_SIZE*OUT_SIZE-1];

    // ==========================================
    // 地址映射定义 (偏移量)
    // ==========================================
    // 0x0000 - 0x0FFF: Input Buffer  (8-bit, 4-byte aligned access)
    // 0x1000 - 0x1FFF: Weight Buffer (8-bit, 4-byte aligned access)
    // 0x2000 - 0x2FFF: Bias Buffer   (32-bit)
    // 0x3000 - 0x3FFF: Output Buffer (32-bit)
    
    localparam ADDR_INPUT_BASE  = 16'h0000;
    localparam ADDR_WEIGHT_BASE = 16'h1000;
    localparam ADDR_BIAS_BASE   = 16'h2000;
    localparam ADDR_OUTPUT_BASE = 16'h3000;

    // ==========================================
    // 内存读写逻辑
    // ==========================================
    wire [15:0] addr_offset;
    
    always @(posedge clk) begin
        if (mem_we) begin
            if (mem_addr >= ADDR_INPUT_BASE && mem_addr < ADDR_WEIGHT_BASE) begin
                // 简化处理：每次写32位数据的低8位到对应索引
                input_buf[(mem_addr - ADDR_INPUT_BASE) >> 2] <= mem_wdata[7:0];
            end
            else if (mem_addr >= ADDR_WEIGHT_BASE && mem_addr < ADDR_BIAS_BASE) begin
                weight_buf[(mem_addr - ADDR_WEIGHT_BASE) >> 2] <= mem_wdata[7:0];
            end
            else if (mem_addr >= ADDR_BIAS_BASE && mem_addr < ADDR_OUTPUT_BASE) begin
                bias_buf[(mem_addr - ADDR_BIAS_BASE) >> 2] <= mem_wdata;
            end
        end
    end

    always @(*) begin
        mem_rdata = 32'b0;
        if (mem_addr >= ADDR_OUTPUT_BASE) begin
            mem_rdata = output_buf[(mem_addr - ADDR_OUTPUT_BASE) >> 2];
        end
        // 可以添加读取 input/weight 的逻辑用于调试
    end

    // ==========================================
    // 卷积计算状态机
    // ==========================================
    localparam S_IDLE = 0;
    localparam S_RUN  = 1;
    localparam S_DONE = 2;

    reg [1:0] state;
    
    // 卷积 index
    integer oc, ic, i, j, m, n;
    integer out_index, in_index, w_index;
    reg signed [31:0] acc;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done  <= 0;
            busy  <= 0;
        end else begin
            case (state)
            S_IDLE: begin
                done <= 0;
                if (start) begin
                    state <= S_RUN;
                    busy  <= 1;
                end
            end

            S_RUN: begin
                // 警告：此处的嵌套循环会在一个时钟周期内生成巨大的组合逻辑
                // 可能导致时序违例。在实际工程中应改为流水线或多周期计算。
                for (oc = 0; oc < OUT_CH; oc = oc + 1) begin
                    for (i = 0; i < OUT_SIZE; i = i + 1) begin
                        for (j = 0; j < OUT_SIZE; j = j + 1) begin
                            acc = bias_buf[oc];
                            for (ic = 0; ic < IN_CH; ic = ic + 1) begin
                                for (m = 0; m < K; m = m + 1) begin
                                    for (n = 0; n < K; n = n + 1) begin
                                        in_index = ic*IN_SIZE*IN_SIZE + (i+m)*IN_SIZE + (j+n);
                                        w_index  = oc*(IN_CH*K*K) + ic*(K*K) + m*K + n;
                                        acc = acc + input_buf[in_index] * weight_buf[w_index];
                                    end
                                end
                            end
                            out_index = oc*(OUT_SIZE*OUT_SIZE) + i*OUT_SIZE + j;
                            output_buf[out_index] <= acc;
                        end
                    end
                end
                state <= S_DONE;
            end

            S_DONE: begin
                done  <= 1;
                busy  <= 0;
                state <= S_IDLE;
            end
            endcase
        end
    end

endmodule