/*
 ============================================================================
 Name        : main.c
 Author      : 
 Version     :
 Copyright   : Your copyright notice
 Description : Hello RISC-V World in C
 ============================================================================
 */

#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <platform.h>
#include "init.h"

//#include "hbird_sdk_soc.h" // 确保包含 SDK 头文件

// 定义外设地址 (基地址 0x10014000)
#define LENET_BASE      0x10014000
#define LENET_REG(off)  (*(volatile uint32_t *)(LENET_BASE + (off)))
#define LENET_BUF(off)  (*(volatile uint8_t  *)(LENET_BASE + (off)))

// 偏移量定义 (与 Verilog 一致)
#define OFF_INPUT       0x0000
#define OFF_CTRL        0xF000
#define OFF_STATUS      0xF004

int main() {
    printf("Simulating LeNet Accelerator...\n");

    // 1. 写入测试数据到 Input Buffer (模拟图片数据)
    // 注意：为了仿真快一点，不要写满所有数据
    LENET_BUF(OFF_INPUT + 0) = 10; 
    LENET_BUF(OFF_INPUT + 1) = 20;

    // 2. 启动加速器
    printf("Starting...\n");
    LENET_REG(OFF_CTRL) = 0x1; // 写 1 启动

    // 3. 轮询等待完成
    // 在仿真中，如果卡在这里，说明 done 信号没产生
    while(1) {
        uint32_t status = LENET_REG(OFF_STATUS);
        if (status & 0x1) { // Bit 0 is Done
            break;
        }
    }

    printf("Computation Done!\n");
    return 0;
}