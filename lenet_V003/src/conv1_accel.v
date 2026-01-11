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

    // CPU 读取 buffer（调试用）
    input  wire [$clog2(IN_CH*IN_SIZE*IN_SIZE)-1:0] input_raddr,
    output wire signed [7:0]         input_rdata,
    
    input  wire [$clog2(OUT_CH*IN_CH*K*K)-1:0]      weight_raddr,
    output wire signed [7:0]         weight_rdata,
    
    input  wire [$clog2(OUT_CH)-1:0] bias_raddr,
    output wire signed [31:0]        bias_rdata,

    // CPU 读取输出 buffer
    input  wire [$clog2(OUT_CH*OUT_SIZE*OUT_SIZE)-1:0] output_raddr,
    output wire signed [31:0]        output_rdata
);

    localparam integer INPUT_SIZE  = IN_CH*IN_SIZE*IN_SIZE;
    localparam integer WEIGHT_SIZE = OUT_CH*IN_CH*K*K;
    localparam integer BIAS_SIZE   = OUT_CH;
    localparam integer OUTPUT_SIZE = OUT_CH*OUT_SIZE*OUT_SIZE;

    // ==========================================
    // 内部 Buffer
    // ==========================================
    // input_buf使用分布式RAM (784字节，不需要BRAM容量)
    reg signed [7:0] input_buf [0:INPUT_SIZE-1];
    // weight_buf使用分布式RAM (150字节，Gowin DPB不支持NO_CHANGE写模式)
    reg signed [7:0]  weight_buf [0:WEIGHT_SIZE-1];
    reg signed [31:0] bias_buf   [0:BIAS_SIZE-1];
    
    // output_buf使用BRAM (3456×32bit = 13.5KB，需要BRAM容量)
    (* ram_style = "block" *) reg signed [31:0] output_buf [0:OUTPUT_SIZE-1];
    reg signed [31:0] output_rdata_reg;
    
    // 输出 buffer 同步读（BRAM需要一周期延迟）
    always @(posedge clk) begin
        if (output_raddr < OUTPUT_SIZE)
            output_rdata_reg <= output_buf[output_raddr];
        else
            output_rdata_reg <= 32'hDEAD_BEEF;
    end
    assign output_rdata = output_rdata_reg;
    
    // ==========================================
    // CPU 读取内部 buffer（调试用，异步读）
    // ==========================================
    assign input_rdata  = input_buf[input_raddr];
    assign weight_rdata = weight_buf[weight_raddr];
    assign bias_rdata   = bias_buf[bias_raddr];

    // ==========================================
    // BRAM 读取寄存器（解决BRAM一周期延迟问题）
    // ==========================================
    reg signed [7:0] input_data_reg;
    reg signed [7:0] weight_data_reg;
    
    // 仿真时预加载真实数据
    `ifdef SIMULATION
        initial begin
            $readmemh("python/npy/input_image.mem", input_buf);     // 分布式RAM
            $readmemh("python/npy/conv1_weight.mem", weight_buf);   // 分布式RAM
            $readmemh("python/npy/conv1_bias.mem", bias_buf);       // 分布式RAM
            $display("[INFO] LeNet Conv1: Loaded real weights from .mem files (Dist-RAM)");
        end
    `endif

    // ==========================================
    // 状态机 (三级流水线: READ -> MAC -> WRITE)
    // ==========================================
    localparam S_IDLE  = 0;
    localparam S_READ  = 1;  // 读取BRAM数据
    localparam S_MAC   = 2;  // 乘加累加
    localparam S_WRITE = 3;  // 写回output_buf
    localparam S_DONE  = 4;

    reg [2:0] state;

    // 状态机计数器
    reg [$clog2(OUT_CH)-1:0]   oc;
    reg [$clog2(IN_CH)-1:0]    ic;
    reg [$clog2(OUT_SIZE)-1:0] out_y, out_x;
    reg [$clog2(K)-1:0]        ky, kx;
    
    // 流水线寄存器：保存当前正在计算的位置信息
    reg first_mac;  // 标记是否是该像素的第一次MAC
    reg last_mac;   // 标记是否是该像素的最后一次MAC
    reg [$clog2(OUT_CH)-1:0]   oc_d;
    reg [$clog2(OUTPUT_SIZE)-1:0] out_index_d;
    
    // 写回地址寄存器
    reg [$clog2(OUTPUT_SIZE)-1:0] write_addr;

    // accumulator
    reg signed [31:0] acc;
    
    // 索引计算（组合逻辑）
    wire [$clog2(INPUT_SIZE)-1:0]  in_index  = ic*IN_SIZE*IN_SIZE + (out_y+ky)*IN_SIZE + (out_x+kx);
    wire [$clog2(WEIGHT_SIZE)-1:0] w_index   = oc*IN_CH*K*K + ic*K*K + ky*K + kx;
    wire [$clog2(OUTPUT_SIZE)-1:0] out_index = oc*OUT_SIZE*OUT_SIZE + out_y*OUT_SIZE + out_x;
    
    // 判断是否是最后一次迭代
    wire is_last_iter = (kx == K-1) && (ky == K-1) && (ic == IN_CH-1);
    wire is_first_iter = (kx == 0) && (ky == 0) && (ic == 0);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done  <= 0;
            oc <= 0; ic <= 0; 
            out_y <= 0; out_x <= 0; 
            ky <= 0; kx <= 0;
            acc <= 0;
            first_mac <= 0;
            last_mac <= 0;
            oc_d <= 0;
            out_index_d <= 0;
            write_addr <= 0;
            input_data_reg <= 0;
            weight_data_reg <= 0;
        end else begin
            // CPU 写 buffer（随时可写，和计算状态机解耦）
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
                    state <= S_READ;
                    oc <= 0; ic <= 0; 
                    out_y <= 0; out_x <= 0; 
                    ky <= 0; kx <= 0;
                    acc <= 0;
                    first_mac <= 0;
                    last_mac <= 0;
                end
            end

            // ==========================================
            // READ：读取BRAM数据，地址锁存后下周期数据有效
            // ==========================================
            S_READ: begin
                // 锁存BRAM读地址（同步读取，数据下周期有效）
                input_data_reg <= input_buf[in_index];
                weight_data_reg <= weight_buf[w_index];
                
                // 记录当前迭代的信息，供MAC阶段使用
                first_mac <= is_first_iter;
                last_mac <= is_last_iter;
                oc_d <= oc;
                out_index_d <= out_index;
                
                // 更新计数器，准备下一次迭代的地址
                if (kx < K-1) begin
                    kx <= kx + 1;
                end else begin
                    kx <= 0;
                    if (ky < K-1) begin
                        ky <= ky + 1;
                    end else begin
                        ky <= 0;
                        if (ic < IN_CH-1) begin
                            ic <= ic + 1;
                        end else begin
                            ic <= 0;
                            // 移动到下一个输出像素
                            if (out_x < OUT_SIZE-1) begin
                                out_x <= out_x + 1;
                            end else begin
                                out_x <= 0;
                                if (out_y < OUT_SIZE-1) begin
                                    out_y <= out_y + 1;
                                end else begin
                                    out_y <= 0;
                                    if (oc < OUT_CH-1) begin
                                        oc <= oc + 1;
                                    end
                                end
                            end
                        end
                    end
                end
                
                state <= S_MAC;
            end

            // ==========================================
            // MAC：使用上周期读取的数据进行乘加
            // ==========================================
            S_MAC: begin
                // 执行乘加（使用上周期锁存的数据）
                if (first_mac) begin
                    acc <= bias_buf[oc_d] + $signed(input_data_reg) * $signed(weight_data_reg);
                end else begin
                    acc <= acc + $signed(input_data_reg) * $signed(weight_data_reg);
                end
                
                // 检查是否完成当前像素
                if (last_mac) begin
                    // 保存写回地址，下周期进入 WRITE 状态
                    write_addr <= out_index_d;
                    state <= S_WRITE;  // 进入写回状态，等待 acc 更新
                end else begin
                    state <= S_READ;
                end
            end

            // ==========================================
            // WRITE：写回 output_buf（等待 acc 更新完成）
            // ==========================================
            S_WRITE: begin
                // 此时 acc 已经是最终值
                output_buf[write_addr] <= acc;
                
                // 检查是否全部完成
                if (write_addr == OUTPUT_SIZE - 1) begin
                    state <= S_DONE;
                end else begin
                    state <= S_READ;
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
