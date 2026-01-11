`timescale 1ns / 1ps
//==============================================================================
// 全连接层硬件加速器 (Fully Connected Layer Accelerator)
// 等效于 PyTorch 的 nn.Linear()
// 
// 计算: output[j] = bias[j] + sum(input[i] * weight[j][i]) for i in [0, IN_SIZE)
//==============================================================================
module fc_accel #(
    parameter IN_SIZE  = 400,    // 输入向量长度
    parameter OUT_SIZE = 120     // 输出向量长度
)(
    input wire clk,
    input wire rst,
    input wire start,
    output reg done,

    // CPU 写入 buffer
    input  wire                              input_we,
    input  wire [$clog2(IN_SIZE)-1:0]        input_waddr,
    input  wire signed [7:0]                 input_wdata,

    input  wire                              weight_we,
    input  wire [$clog2(IN_SIZE*OUT_SIZE)-1:0] weight_waddr,
    input  wire signed [7:0]                 weight_wdata,

    input  wire                              bias_we,
    input  wire [$clog2(OUT_SIZE)-1:0]       bias_waddr,
    input  wire signed [31:0]                bias_wdata,

    // CPU 读取输出 buffer
    input  wire [$clog2(OUT_SIZE)-1:0]       output_raddr,
    output wire signed [31:0]                output_rdata
);

    localparam integer WEIGHT_SIZE = IN_SIZE * OUT_SIZE;

    // ==========================================
    // 内部 Buffer (使用BRAM推断)
    // ==========================================
    (* ram_style = "block" *) reg signed [7:0] input_buf [0:IN_SIZE-1];
    (* ram_style = "block" *) reg signed [7:0] weight_buf [0:WEIGHT_SIZE-1];
    reg signed [31:0] bias_buf [0:OUT_SIZE-1];
    
    (* ram_style = "block" *) reg signed [31:0] output_buf [0:OUT_SIZE-1];
    reg signed [31:0] output_rdata_reg;
    
    // 输出 buffer 同步读
    always @(posedge clk) begin
        if (output_raddr < OUT_SIZE)
            output_rdata_reg <= output_buf[output_raddr];
        else
            output_rdata_reg <= 32'hDEAD_BEEF;
    end
    assign output_rdata = output_rdata_reg;

    // ==========================================
    // BRAM 读取寄存器（解决BRAM一周期延迟问题）
    // ==========================================
    reg signed [7:0] input_data_reg;
    reg signed [7:0] weight_data_reg;

    // ==========================================
    // 状态机
    // ==========================================
    localparam S_IDLE = 0;
    localparam S_READ = 1;  // 读取BRAM数据
    localparam S_MAC  = 2;  // 乘加累加
    localparam S_DONE = 3;

    reg [1:0] state;

    // 计数器
    reg [$clog2(OUT_SIZE)-1:0] out_idx;  // 当前输出神经元
    reg [$clog2(IN_SIZE)-1:0]  in_idx;   // 当前输入索引
    
    // 流水线寄存器
    reg first_mac;  // 是否是该神经元的第一次MAC
    reg last_mac;   // 是否是该神经元的最后一次MAC
    reg [$clog2(OUT_SIZE)-1:0] out_idx_d;  // 延迟的输出索引
    
    // 写回标志
    reg write_pending;
    reg [$clog2(OUT_SIZE)-1:0] write_addr;

    // 累加器
    reg signed [31:0] acc;
    
    // 权重索引计算: weight[out_idx][in_idx] = weight_buf[out_idx * IN_SIZE + in_idx]
    wire [$clog2(WEIGHT_SIZE)-1:0] w_index = out_idx * IN_SIZE + in_idx;
    
    // 判断是否是最后一次迭代
    wire is_last_iter = (in_idx == IN_SIZE - 1);
    wire is_first_iter = (in_idx == 0);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done  <= 0;
            out_idx <= 0;
            in_idx <= 0;
            acc <= 0;
            first_mac <= 0;
            last_mac <= 0;
            out_idx_d <= 0;
            write_pending <= 0;
            write_addr <= 0;
            input_data_reg <= 0;
            weight_data_reg <= 0;
        end else begin
            // ==========================================
            // 延迟写output_buf
            // ==========================================
            if (write_pending) begin
                output_buf[write_addr] <= acc;
                write_pending <= 0;
            end
            
            // ==========================================
            // CPU 写 buffer
            // ==========================================
            if (input_we && (input_waddr < IN_SIZE))
                input_buf[input_waddr] <= input_wdata;
            if (weight_we && (weight_waddr < WEIGHT_SIZE))
                weight_buf[weight_waddr] <= weight_wdata;
            if (bias_we && (bias_waddr < OUT_SIZE))
                bias_buf[bias_waddr] <= bias_wdata;

            case (state)

            // ==========================================
            // IDLE：等待 CPU 启动
            // ==========================================
            S_IDLE: begin
                done <= 0;
                if (start) begin
                    state <= S_READ;
                    out_idx <= 0;
                    in_idx <= 0;
                    acc <= 0;
                    first_mac <= 0;
                    last_mac <= 0;
                end
            end

            // ==========================================
            // READ：读取BRAM数据
            // ==========================================
            S_READ: begin
                // 锁存BRAM读地址
                input_data_reg <= input_buf[in_idx];
                weight_data_reg <= weight_buf[w_index];
                
                // 记录当前迭代信息
                first_mac <= is_first_iter;
                last_mac <= is_last_iter;
                out_idx_d <= out_idx;
                
                // 更新计数器
                if (in_idx < IN_SIZE - 1) begin
                    in_idx <= in_idx + 1;
                end else begin
                    in_idx <= 0;
                    // 移动到下一个输出神经元
                    if (out_idx < OUT_SIZE - 1) begin
                        out_idx <= out_idx + 1;
                    end
                end
                
                state <= S_MAC;
            end

            // ==========================================
            // MAC：乘加
            // ==========================================
            S_MAC: begin
                // 执行乘加
                if (first_mac) begin
                    acc <= bias_buf[out_idx_d] + $signed(input_data_reg) * $signed(weight_data_reg);
                end else begin
                    acc <= acc + $signed(input_data_reg) * $signed(weight_data_reg);
                end
                
                // 检查是否完成当前神经元
                if (last_mac) begin
                    // 标记需要写回
                    write_pending <= 1;
                    write_addr <= out_idx_d;
                    
                    // 检查是否全部完成
                    if (out_idx_d == OUT_SIZE - 1) begin
                        state <= S_DONE;
                    end else begin
                        state <= S_READ;
                    end
                end else begin
                    state <= S_READ;
                end
            end

            // ==========================================
            // DONE：计算完成
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
