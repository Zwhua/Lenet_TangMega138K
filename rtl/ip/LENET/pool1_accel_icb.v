`timescale 1ns / 1ps
//==============================================================================
// 池化层 ICB 总线适配器
//==============================================================================
module pool1_accel_icb #(
    parameter CH       = 6,
    parameter IN_SIZE  = 24,
    parameter OUT_SIZE = IN_SIZE/2,

    parameter ICB_RW_ADDR_W = 32,
    parameter ICB_RW_DATA_W = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // ICB Slave Interface
    input  wire        i_icb_cmd_valid,
    output wire        i_icb_cmd_ready,
    input  wire [31:0] i_icb_cmd_addr,
    input  wire        i_icb_cmd_read,
    input  wire [31:0] i_icb_cmd_wdata,
    
    output reg         i_icb_rsp_valid, 
    input  wire        i_icb_rsp_ready,
    output reg  [31:0] i_icb_rsp_rdata,  
    output reg         i_icb_rsp_err    
);

    // ===========================
    // 地址映射
    // ===========================
    localparam ADDR_CTRL      = 32'h1004_0000;
    localparam ADDR_STATUS    = 32'h1004_0004;
    localparam ADDR_INPUT     = 32'h1004_1000;
    localparam ADDR_OUTPUT    = 32'h1004_5000;

    localparam INPUT_SIZE  = CH*IN_SIZE*IN_SIZE;
    localparam OUTPUT_SIZE = CH*OUT_SIZE*OUT_SIZE;

    reg start_reg;
    reg done_reg;

    // ===========================
    // ICB 接收握手
    // ===========================
    assign i_icb_cmd_ready = 1'b1;

    wire write_en = i_icb_cmd_valid && !i_icb_cmd_read;
    wire read_en  = i_icb_cmd_valid &&  i_icb_cmd_read;

    // ===========================
    // 地址解码
    // ===========================
    localparam integer IN_AW  = $clog2(INPUT_SIZE);
    localparam integer OUT_AW = $clog2(OUTPUT_SIZE);

    wire addr_is_input  = (i_icb_cmd_addr >= ADDR_INPUT)  && (i_icb_cmd_addr < (ADDR_INPUT  + INPUT_SIZE*4));
    wire addr_is_output = (i_icb_cmd_addr >= ADDR_OUTPUT) && (i_icb_cmd_addr < (ADDR_OUTPUT + OUTPUT_SIZE*4));

    wire input_we = write_en && addr_is_input;

    wire [IN_AW-1:0]  input_waddr  = (i_icb_cmd_addr - ADDR_INPUT)  >> 2;
    wire signed [31:0] input_wdata = i_icb_cmd_wdata;

    wire [IN_AW-1:0]  input_raddr  = (i_icb_cmd_addr - ADDR_INPUT)  >> 2;
    wire [OUT_AW-1:0] output_raddr = (i_icb_cmd_addr - ADDR_OUTPUT) >> 2;
    
    wire signed [31:0] input_rdata;
    wire signed [31:0] output_rdata;

    // ===========================
    // 写寄存器
    // ===========================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_reg <= 0;
        end else if (write_en) begin
            if (i_icb_cmd_addr == ADDR_CTRL) begin
                start_reg <= i_icb_cmd_wdata[0];
            end
        end
    end

    // ===========================
    // 读寄存器/buffer
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
                if (i_icb_cmd_addr == ADDR_CTRL) begin
                    i_icb_rsp_rdata <= {31'b0, start_reg};
                end
                else if (i_icb_cmd_addr == ADDR_STATUS) begin
                    i_icb_rsp_rdata <= {31'b0, done_reg};
                end
                else if (addr_is_output) begin
                    i_icb_rsp_rdata <= output_rdata;
                end
                else if (addr_is_input) begin
                    i_icb_rsp_rdata <= input_rdata;
                end
                else begin
                    i_icb_rsp_rdata <= 32'hDEAD_BEEF;
                end
            end else begin
                i_icb_rsp_rdata <= 32'h0;
            end
        end
    end

    // ===========================
    // 池化引擎实例化
    // ===========================
    wire accel_done;

    pool1_accel #(
        .CH(CH),
        .IN_SIZE(IN_SIZE)
    ) u_accel (
        .clk(clk),
        .rst(!rst_n),
        .start(start_reg),
        .done(accel_done),

        .input_we(input_we),
        .input_waddr(input_waddr),
        .input_wdata(input_wdata),

        .input_raddr(input_raddr),
        .input_rdata(input_rdata),

        .output_raddr(output_raddr),
        .output_rdata(output_rdata)
    );

    // done 信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            done_reg <= 0;
        else 
            done_reg <= accel_done;
    end

endmodule
