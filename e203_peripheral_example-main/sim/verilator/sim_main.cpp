#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "Vtb_top.h"
#include <verilated.h>

#define CONFIG_FST_WAVE_TRACE 1

VerilatedContext *contextp = new VerilatedContext;

Vtb_top *top = new Vtb_top{contextp};


#if CONFIG_FST_WAVE_TRACE
#include "verilated_fst_c.h"
VerilatedFstC *tfp = new VerilatedFstC;
#endif

int main(int argc, char **argv)
{
    contextp->commandArgs(argc, argv);

#if CONFIG_FST_WAVE_TRACE
    contextp->traceEverOn(true);
    top->trace(tfp, 99)long
    tfp->open("build/logs/wave.fst");
#endif

    top->clk = 0;
    top->rst = 0;

    uint64_t cycle = 10*1000*1000*1000;

    while(cycle)
    {
        
        top->eval();
        
        contextp->timeInc(1);

#if CONFIG_FST_WAVE_TRACE
        tfp->dump(contextp->time());
#endif

        cycle--;
    }



}
