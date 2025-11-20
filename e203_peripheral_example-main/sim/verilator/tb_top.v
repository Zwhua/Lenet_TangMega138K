
`timescale 1ns/10ps


module tb_top(
    input clk;
    input lfextclk;
    input rst;

    output uart_tx;
);




    wire hfclk = clk;
    wire uart_rx;
    wire [31:0] gpio; 
    assign uart_rx = gpio[17];


  //uart rx period
  int uart_rx_period = 8750; //8.75us
  reg [7:0] uart_rx_byte;
//receive uart data
  task uart_rx_data(output bit [7:0] rx_data);
    reg [7:0] rx_tmp;
    //1 bit start bit
    @(negedge uart_rx);
    #uart_rx_period;

    // 8 bit data: LSB first
    for(int i=0; i<8; i++)
    begin
      #(uart_rx_period/2);        
      rx_tmp[i] = uart_rx;
      #(uart_rx_period/2);          
    end

    //1 bit stop bit
    #(uart_rx_period/2);
    rx_data = rx_tmp;

  endtask

// receive data from e203 core
initial begin
  int j = 0;

  #5ms;

  forever begin
    uart_rx_data(uart_rx_byte);
    //$display("rx_data[%x] = %x", j, uart_rx_byte);    
  end

end  


    e203_soc_demo uut (
        .clk_in              (clk),  

        .tck                 (), 
        .tms                 (), 
        .tdi                 (), 
        .tdo                 (),  

        .gpio_in             (),
        .gpio_out            (gpio),
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
