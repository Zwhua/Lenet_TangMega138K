
`timescale 1ns/1ns
`define USING_IVERILOG


module sys_tb_top();

  reg  clk;
  reg  lfextclk;
  reg  rst_n;

  wire hfclk = clk;

`ifdef USING_IVERILOG
  initial begin
    $dumpfile("waveout.vcd");
    $dumpvars(0, sys_tb_top);
  end
 `endif

`ifdef USING_VCS
  initial begin
    $fsdbDumpfile("test.fsdb");
    $fsdbDumpvars;
  end
`endif

  initial begin
    #200ms;
    $finish;
  end


  initial begin

    clk        <=0;
    lfextclk   <=0;
    rst_n      <=0;
    #320us rst_n <=1;
  end


  always
  begin 
     #18.52 clk <= ~clk;
  end

  always
  begin 
     #33 lfextclk <= ~lfextclk;
  end

//--------------UART data transfer--------------//  


  //uart tx signal
  reg [31:0] gpio_in; // default value bit 16 (uart_tx) should be 1
  //uart rx signal
  reg [31:0] gpio_out;  // bit 17 is uart rx. 




    e203_soc_demo uut (
        .clk_in              (clk),  

        .tck                 (), 
        .tms                 (), 
        .tdi                 (), 
        .tdo                 (),  

        .gpio_in             (gpio_in),
        .gpio_out            (gpio_out),
        .qspi_in             (),
        .qspi_out            (),      
        .qspi_sck            (),  
        .qspi_cs             (),   

        .erstn               (rst_n), 

        .dbgmode0_n          (1'b1), 
        .dbgmode1_n          (1'b1),
        .dbgmode3_n          (1'b1),
  
        .bootrom_n           (1'b0), 
  
        .aon_pmu_dwakeup_n   (), 
        .aon_pmu_padrst      (),    
        .aon_pmu_vddpaden    () 
    );

endmodule
