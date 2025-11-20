module conv1_accel_icb (
    input  wire        clk,
    input  wire        rst_n,

    // ICB Slave Interface (连接到 E203 总线)
    input  wire        i_icb_cmd_valid,
    output wire        i_icb_cmd_ready,
    input  wire [31:0] i_icb_cmd_addr, 
    input  wire        i_icb_cmd_read, 
    input  wire [31:0] i_icb_cmd_wdata,
    
    output wire        i_icb_rsp_valid,
    input  wire        i_icb_rsp_ready,
    output wire [31:0] i_icb_rsp_rdata,
    output wire        i_icb_rsp_err
);

    // ===========================================================================
    // 1. ICB 总线握手逻辑
    // ===========================================================================
    assign i_icb_cmd_ready = i_icb_rsp_ready; 
    assign i_icb_rsp_valid = i_icb_cmd_valid;
    assign i_icb_rsp_err   = 1'b0;

    wire icb_trans_active = i_icb_cmd_valid && i_icb_cmd_ready;
    wire icb_wr_en = icb_trans_active && (!i_icb_cmd_read);
    wire icb_rd_en = icb_trans_active && (i_icb_cmd_read);

    // 分配给该外设的空间是 16KB (0x10014000 - 0x10017FFF)
    wire [15:0] addr_offset = i_icb_cmd_addr[15:0] & 16'h3FFF; 

    // ===========================================================================
    // 2. 地址空间解码
    // ===========================================================================
    // 定义控制寄存器地址位于 0xF000，避开 conv1_accel 的数据区 (0x0000-0x6FFF)
    localparam ADDR_CTRL   = 16'hF000; // Write 1 to start
    localparam ADDR_STATUS = 16'hF004; // Read status

    // 判断是否访问控制/状态寄存器
    wire is_csr_access = (addr_offset >= 16'hF000);

    // ===========================================================================
    // 3. 控制寄存器逻辑 (CSR)
    // ===========================================================================
    reg [31:0] csr_rdata;
    wire       accel_start;
    wire       accel_done;
    wire       accel_busy;

    // 生成 Start 脉冲：写 ADDR_CTRL 且数据最低位为 1
    assign accel_start = icb_wr_en && (addr_offset == ADDR_CTRL) && i_icb_cmd_wdata[0];

    // CSR 读逻辑
    always @(*) begin
        case (addr_offset)
            ADDR_CTRL:   csr_rdata = 32'b0; // 控制寄存器只写，读为0
            ADDR_STATUS: csr_rdata = {30'b0, accel_busy, accel_done}; 
            default:     csr_rdata = 32'b0;
        endcase
    end

    // ===========================================================================
    // 4. 存储器接口逻辑 (Memory Interface)
    // ===========================================================================
    // 如果不是访问 CSR，则信号直通给 conv1_accel
    wire        mem_we    = icb_wr_en && (!is_csr_access);
    wire [15:0] mem_addr  = addr_offset;
    wire [31:0] mem_wdata = i_icb_cmd_wdata;
    wire [31:0] mem_rdata; // 来自 conv1_accel 的读数据

    // ===========================================================================
    // 5. 读数据多路复用
    // ===========================================================================
    // 根据地址范围选择返回 CSR 数据还是 Memory 数据
    assign i_icb_rsp_rdata = is_csr_access ? csr_rdata : mem_rdata;

    // ===========================================================================
    // 6. 实例化 LeNet 卷积加速器核心
    // ===========================================================================
    conv1_accel u_conv1_accel (
        .clk        (clk),
        .rst        (~rst_n), // 注意：conv1_accel 使用高电平复位，这里取反
        
        // 控制接口
        .start      (accel_start),
        .done       (accel_done),
        .busy       (accel_busy),

        // 内存映射接口
        .mem_addr   (mem_addr),
        .mem_we     (mem_we),
        .mem_wdata  (mem_wdata),
        .mem_rdata  (mem_rdata)
    );

endmodule