/**
*/

//=====================================================================
//
// Designer   : Jiang Lei
//
// Description:
//  Example for an e203 icb peripheral
//
// ====================================================================

module my_periph_example(
    input                   clk,
    input                   rst_n,

    input                   i_icb_cmd_valid,
    output                  i_icb_cmd_ready,
    input  [32-1:0]         i_icb_cmd_addr, 
    input                   i_icb_cmd_read, 
    input  [32-1:0]         i_icb_cmd_wdata,

    output                  i_icb_rsp_valid,
    input                   i_icb_rsp_ready,
    output [32-1:0]         i_icb_rsp_rdata,

    output                  io_interrupts_0_0,                
    output                  io_pad_out
);

    //define a 32-bit register for operating your module
    reg [31:0] io_value_reg;

    reg [31:0] icb_data_out;
    reg        icb_rsp_valid;

    wire reset;
    wire clock;
    //read enable signal for register reading, this signal assert when proper address issued.
    wire io_value_reg_rd_en;

    //write enable signal for register writting, this signal assert when proper address issued.
    wire io_value_reg_wr_en;


    assign reset = ~rst_n;
    assign clock = clk;
    
    //judge if register is selected for read, 3'h4 is the offset address of the register
    assign io_value_reg_rd_en = i_icb_cmd_valid && i_icb_cmd_read && (i_icb_cmd_addr[11:0] == 3'h4);
    //for write
    assign io_value_reg_wr_en = i_icb_cmd_valid && (~i_icb_cmd_read) && (i_icb_cmd_addr[11:0] == 3'h4);

    //no wait state, so direct connect valid to ready signal
    assign i_icb_cmd_ready = i_icb_cmd_valid;

    assign i_icb_rsp_valid = i_icb_rsp_ready && icb_rsp_valid;

    assign i_icb_rsp_rdata = icb_data_out;

    //connect io pad to register
    assign io_pad_out = io_value_reg[0];


    always @(posedge clock or posedge reset) begin
        if (reset) begin
            io_value_reg <= 32'h12345678;
            icb_rsp_valid <= 1'b0;
        end 
        else begin
            if (io_value_reg_rd_en) begin
                icb_data_out <= io_value_reg;
                icb_rsp_valid <= 1'b1;
            end
            else begin
                icb_rsp_valid <= 1'b0;
            end

            if(io_value_reg_wr_en) begin
                io_value_reg <= i_icb_cmd_wdata;
                icb_rsp_valid <= 1'b1;
            end
        end
    end

endmodule
