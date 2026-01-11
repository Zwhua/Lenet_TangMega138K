`timescale 1ns / 1ps
//==============================================================================
// 2x2 Max Pooling 加速器
// 输入: CH × IN_SIZE × IN_SIZE
// 输出: CH × OUT_SIZE × OUT_SIZE (OUT_SIZE = IN_SIZE/2)
//==============================================================================
module pool1_accel #(
    parameter CH       = 6,
    parameter IN_SIZE  = 24,
    parameter OUT_SIZE = IN_SIZE/2
)(
    input wire clk,
    input wire rst,
    input wire start,
    output reg done,

    // CPU 写入 input buffer
    input  wire                      input_we,
    input  wire [$clog2(CH*IN_SIZE*IN_SIZE)-1:0] input_waddr,
    input  wire signed [31:0]        input_wdata,

    // CPU 读取 input buffer (调试用)
    input  wire [$clog2(CH*IN_SIZE*IN_SIZE)-1:0] input_raddr,
    output wire signed [31:0]        input_rdata,

    // CPU 读取输出 buffer
    input  wire [$clog2(CH*OUT_SIZE*OUT_SIZE)-1:0] output_raddr,
    output wire signed [31:0]        output_rdata
);

    localparam integer INPUT_SIZE  = CH*IN_SIZE*IN_SIZE;
    localparam integer OUTPUT_SIZE = CH*OUT_SIZE*OUT_SIZE;

    // ==========================================
    // 内部 Buffer
    // ==========================================
    reg signed [31:0] input_buf [0:INPUT_SIZE-1];
    (* ram_style = "block" *) reg signed [31:0] output_buf [0:OUTPUT_SIZE-1];
    
    reg signed [31:0] output_rdata_reg;
    reg signed [31:0] input_rdata_reg;
    
    // 输出 buffer 同步读
    always @(posedge clk) begin
        if (output_raddr < OUTPUT_SIZE)
            output_rdata_reg <= output_buf[output_raddr];
        else
            output_rdata_reg <= 32'hDEAD_BEEF;
    end
    assign output_rdata = output_rdata_reg;
    
    // 输入 buffer 同步读
    always @(posedge clk) begin
        if (input_raddr < INPUT_SIZE)
            input_rdata_reg <= input_buf[input_raddr];
        else
            input_rdata_reg <= 32'hDEAD_BEEF;
    end
    assign input_rdata = input_rdata_reg;

    // ==========================================
    // 状态机
    // ==========================================
    localparam S_IDLE  = 0;
    localparam S_READ  = 1;
    localparam S_POOL  = 2;
    localparam S_WRITE = 3;
    localparam S_DONE  = 4;

    reg [2:0] state;
    reg [$clog2(CH)-1:0] ch;
    reg [$clog2(OUT_SIZE)-1:0] oy, ox;
    
    reg signed [31:0] win0, win1, win2, win3;
    reg signed [31:0] pool_val;
    reg [$clog2(OUTPUT_SIZE)-1:0] write_addr;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done  <= 0;
            ch <= 0; oy <= 0; ox <= 0;
            win0 <= 0; win1 <= 0; win2 <= 0; win3 <= 0;
            pool_val <= 0;
            write_addr <= 0;
        end else begin
            // CPU 写 input buffer
            if (input_we && (input_waddr < INPUT_SIZE))
                input_buf[input_waddr] <= input_wdata;

            case (state)

            S_IDLE: begin
                done <= 0;
                if (start) begin
                    state <= S_READ;
                    ch <= 0; oy <= 0; ox <= 0;
                end
            end

            S_READ: begin
                // 读取 2x2 窗口的4个值
                win0 <= input_buf[ch*IN_SIZE*IN_SIZE + (2*oy)*IN_SIZE + (2*ox)];
                win1 <= input_buf[ch*IN_SIZE*IN_SIZE + (2*oy)*IN_SIZE + (2*ox+1)];
                win2 <= input_buf[ch*IN_SIZE*IN_SIZE + (2*oy+1)*IN_SIZE + (2*ox)];
                win3 <= input_buf[ch*IN_SIZE*IN_SIZE + (2*oy+1)*IN_SIZE + (2*ox+1)];
                state <= S_POOL;
            end

            S_POOL: begin
                // 2x2 max pooling (分步比较)
                pool_val <= win0;
                if ($signed(win1) > $signed(pool_val)) pool_val <= win1;
                if ($signed(win2) > $signed(pool_val)) pool_val <= win2;
                if ($signed(win3) > $signed(pool_val)) pool_val <= win3;
                
                write_addr <= ch*OUT_SIZE*OUT_SIZE + oy*OUT_SIZE + ox;
                state <= S_WRITE;
            end

            S_WRITE: begin
                output_buf[write_addr] <= pool_val;
                
                // 更新坐标
                if (ox < OUT_SIZE-1) begin
                    ox <= ox + 1;
                end else begin
                    ox <= 0;
                    if (oy < OUT_SIZE-1) begin
                        oy <= oy + 1;
                    end else begin
                        oy <= 0;
                        if (ch < CH-1) begin
                            ch <= ch + 1;
                        end
                    end
                end
                
                // 检查是否完成
                if (write_addr == OUTPUT_SIZE - 1) begin
                    state <= S_DONE;
                end else begin
                    state <= S_READ;
                end
            end

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
