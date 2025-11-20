`timescale 1ns / 1ps
module tb_conv_multi_flat();
    parameter IN_CH   = 1;
    parameter OUT_CH  = 6;
    parameter IN_SIZE = 28;
    parameter K       = 5;
    parameter OUT_SIZE = IN_SIZE - K + 1;

    reg clk, rst, start;
    wire done;

    // 展平后的信号
    reg  signed [7:0]  input_fm_flat [0:IN_CH*IN_SIZE*IN_SIZE-1];
    reg  signed [7:0]  weight_flat   [0:OUT_CH*IN_CH*K*K-1];
    wire signed [31:0] output_fm_flat[0:OUT_CH*OUT_SIZE*OUT_SIZE-1];
    reg signed [31:0] bias_flat [0:OUT_CH-1];


    initial begin
        $readmemh("input_image.mem", input_fm_flat);
        $readmemh("conv1_weight.mem", weight_flat);
        $readmemh("conv1_bias.mem", bias_flat);
    end

    integer fout;
    initial begin
        fout = $fopen("hw_conv1_out.txt", "w");
        if (fout == 0) begin
            $display("ERROR: 无法打开 hw_conv1_out.txt");
            $finish;
        end
    end

    always @(posedge done) begin : WRITE_OUT
        integer i;
        for (i = 0; i < OUT_CH*OUT_SIZE*OUT_SIZE; i = i + 1)
            $fwrite(fout, "%0d\n", output_fm_flat[i]);
        $fclose(fout);
    end

    conv_int8_multi_flat #(
        .IN_CH(IN_CH), .OUT_CH(OUT_CH),
        .IN_SIZE(IN_SIZE), .K(K)
    ) uut (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .input_fm_flat(input_fm_flat),
        .weight_flat(weight_flat),
        .bias_flat(bias_flat),            // 连接 bias 端口
        .output_fm_flat(output_fm_flat)
    );
        

    
    integer i;
    reg [63:0] t0, t1;

    initial begin
        $dumpfile("tb_conv_multi_flat.vcd");
        $dumpvars(0, tb_conv_multi_flat);
        clk = 0; rst = 1; start = 0;
        #20 rst = 0;

        // 若使用 $readmemh，请注释掉下面随机初始化，避免覆盖
        /*
        for (i = 0; i < IN_CH*IN_SIZE*IN_SIZE; i = i + 1)
            input_fm_flat[i] = $random % 8;
        for (i = 0; i < OUT_CH*IN_CH*K*K; i = i + 1)
            weight_flat[i] = $random % 5;
        */

        #10 start = 1; t0 = $time;
        #10 start = 0;
        wait (done);

        // 可选：检测 X/Z
        for (i = 0; i < OUT_CH*OUT_SIZE*OUT_SIZE; i = i + 1) begin
            if ((^output_fm_flat[i]) === 1'bx) begin
                $display("ERROR: output_fm_flat[%0d] 含有未知值 X/Z", i);
            end
        end

        // 写文件（十进制）
        for (i = 0; i < OUT_CH*OUT_SIZE*OUT_SIZE; i = i + 1)
            $fwrite(fout, "%0d\n", output_fm_flat[i]);
        $fclose(fout);

        t1 = $time;
        $display("Multi-channel convolution done in %0dns", t1 - t0);
        $display("output[0]=%0d output[last]=%0d",
                 output_fm_flat[0],
                 output_fm_flat[OUT_CH*OUT_SIZE*OUT_SIZE-1]);
        #50 $finish;
    end

    always #5 clk = ~clk;
endmodule
