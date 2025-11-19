// rtl/e203/perips/lenet_accel_icb.v

`include "e203_defines.v"

module lenet_accel_icb (
  input  clk,
  input  rst_n,

  // 来自 ICB 总线的命令
  input                         i_icb_cmd_valid,
  output                        i_icb_cmd_ready,
  input  [`E203_ADDR_SIZE-1:0]  i_icb_cmd_addr,
  input                         i_icb_cmd_read,
  input  [`E203_XLEN-1:0]       i_icb_cmd_wdata,
  input  [`E203_XLEN/8-1:0]     i_icb_cmd_wmask,

  // 返回给 ICB 总线的响应
  output                        i_icb_rsp_valid,
  input                         i_icb_rsp_ready,
  output                        i_icb_rsp_err,
  output [`E203_XLEN-1:0]       i_icb_rsp_rdata,

  // 和真正的 LeNet 计算核的接口（以后你可以接你的计算模块）
  output                        accel_start,
  input                         accel_done,
  output [31:0]                 img_base_addr,
  output [31:0]                 wgt_base_addr,
  output [31:0]                 out_base_addr
);

  // ---------- 寄存器定义 ----------
  reg [31:0] reg_img_addr;
  reg [31:0] reg_wgt_addr;
  reg [31:0] reg_out_addr;
  reg [31:0] reg_ctrl;
  reg [31:0] reg_status;

  // 暂时不用错误机制
  assign i_icb_rsp_err = 1'b0;

  // ICB 我们做成“单周期响应”：只要收到一条命令，下一拍就给 rsp
  reg  cmd_handshake_d;
  wire cmd_fire = i_icb_cmd_valid & i_icb_cmd_ready;

  assign i_icb_cmd_ready = 1'b1;     // 一直 ready
  assign i_icb_rsp_valid = cmd_handshake_d;  // 上一拍有命令，这一拍给响应

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cmd_handshake_d <= 1'b0;
    end else begin
      cmd_handshake_d <= cmd_fire;
    end
  end

  // 地址低几位做寄存器选择（基地址由上层 ICB fabric 决定，这里看 offset 就行）
  wire [7:0] addr_offset = i_icb_cmd_addr[7:0];

  // start 信号做成单周期脉冲
  reg start_pulse;
  assign accel_start = start_pulse;

  // 输出给计算核的 base 地址直接连寄存器
  assign img_base_addr = reg_img_addr;
  assign wgt_base_addr = reg_wgt_addr;
  assign out_base_addr = reg_out_addr;

  // STATUS 中的 busy/done
  localparam STATUS_DONE_BIT = 0;
  localparam STATUS_BUSY_BIT = 1;

  // 写寄存器逻辑
  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_img_addr  <= 32'b0;
      reg_wgt_addr  <= 32'b0;
      reg_out_addr  <= 32'b0;
      reg_ctrl      <= 32'b0;
      reg_status    <= 32'b0;
      start_pulse   <= 1'b0;
    end else begin
      start_pulse <= 1'b0;  // 默认不发 start

      if (cmd_fire & ~i_icb_cmd_read) begin
        case (addr_offset[7:2]) // 按 word 地址解码
          6'h00: reg_img_addr <= i_icb_cmd_wdata;
          6'h01: reg_wgt_addr <= i_icb_cmd_wdata;
          6'h02: reg_out_addr <= i_icb_cmd_wdata;
          6'h03: begin
            reg_ctrl <= i_icb_cmd_wdata;
            if (i_icb_cmd_wdata[0]) begin
              // start 位 = 1
              start_pulse <= 1'b1;
              // 置 busy = 1，清 done
              reg_status[STATUS_BUSY_BIT] <= 1'b1;
              reg_status[STATUS_DONE_BIT] <= 1'b0;
            end
          end
          default: ;
        endcase
      end

      // 计算核回来的 done 信号
      if (accel_done) begin
        reg_status[STATUS_BUSY_BIT] <= 1'b0;
        reg_status[STATUS_DONE_BIT] <= 1'b1;
      end
    end
  end

  // 读寄存器逻辑
  reg [`E203_XLEN-1:0] rdata_r;
  assign i_icb_rsp_rdata = rdata_r;

  always @(*) begin
    case (addr_offset[7:2])
      6'h00: rdata_r = reg_img_addr;
      6'h01: rdata_r = reg_wgt_addr;
      6'h02: rdata_r = reg_out_addr;
      6'h03: rdata_r = reg_ctrl;
      6'h04: rdata_r = reg_status;
      default: rdata_r = 32'h0;
    endcase
  end

endmodule
