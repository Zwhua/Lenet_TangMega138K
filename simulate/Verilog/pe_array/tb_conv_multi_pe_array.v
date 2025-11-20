`timescale 1ns / 1ps
module tb_conv_multi_pe_array();
    parameter IN_CH = 2;
    parameter OUT_CH = 3;
    parameter IN_SIZE = 8;
    parameter K = 3;
    parameter OUT_SIZE = IN_SIZE - K + 1;
    //=========================================================
    parameter PE_ROWS = 5;
    parameter PE_COLS = 5;
    //=========================================================

    reg clk, rst, start;
    wire done;

    reg  signed [7:0]  input_fm_flat [0:IN_CH*IN_SIZE*IN_SIZE-1];
    reg  signed [7:0]  weight_flat   [0:OUT_CH*IN_CH*K*K-1];
    wire signed [31:0] output_fm_flat[0:OUT_CH*OUT_SIZE*OUT_SIZE-1];

    conv_int8_multi_pe_array #(
        .IN_CH(IN_CH), .OUT_CH(OUT_CH),
        .IN_SIZE(IN_SIZE), .K(K),
        .PE_ROWS(PE_ROWS), .PE_COLS(PE_COLS)
    ) uut (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .input_fm_flat(input_fm_flat),
        .weight_flat(weight_flat),
        .output_fm_flat(output_fm_flat)
    );

    integer i;
    reg [63:0] t0, t1;

    initial begin
        $dumpfile("tb_conv_multi_pe_array.vcd");
        $dumpvars(0, tb_conv_multi_pe_array);
        clk = 0; rst = 1; start = 0;
        #20 rst = 0;

        // 初始化输入/权重
        for (i = 0; i < IN_CH*IN_SIZE*IN_SIZE; i = i + 1)
            input_fm_flat[i] = $random % 8;
        for (i = 0; i < OUT_CH*IN_CH*K*K; i = i + 1)
            weight_flat[i] = $random % 5;

        #10 start = 1; t0 = $time;
        #10 start = 0;
        wait(done);
        t1 = $time;

        $display("✅ PE_ARRAY %0dx%0d convolution done in %0dns", PE_ROWS, PE_COLS, t1 - t0);
        $display("output[0]=%0d output[last]=%0d",
                 output_fm_flat[0],
                 output_fm_flat[OUT_CH*OUT_SIZE*OUT_SIZE-1]);
        #50 $finish;
    end

    always #5 clk = ~clk; // 100MHz
endmodule
