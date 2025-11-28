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

// Lenet 加速器地址 (PWM2 地址)
#define LENET_BASE      0x10035000
#define LENET_CTRL      (*(volatile uint32_t *)(LENET_BASE + 0x0000))
#define LENET_STATUS    (*(volatile uint32_t *)(LENET_BASE + 0x0004))

// 改为 32 位指针,每次写入 4 个字节
#define LENET_INPUT32   ((volatile uint32_t *)(LENET_BASE + 0x0010))
#define LENET_WEIGHT32  ((volatile uint32_t *)(LENET_BASE + 0x1000))
#define LENET_BIAS32    ((volatile uint32_t *)(LENET_BASE + 0x2000))
#define LENET_OUTPUT32  ((volatile uint32_t *)(LENET_BASE + 0x3000))

void test_lenet(void) {
    // 1. 写入输入数据 (每次写 4 个字节,打包成 32 位)
    for(int i=0;i<28*28;i++) {
        // 将 8 位数据打包到 32 位字的低 8 位
        LENET_INPUT32[i] = i & 0xFF;   // 输入
    }

    // 2. 写入权重
    for(int i=0;i<150;i++) {
        LENET_WEIGHT32[i] = 1;         // 权重
    }

    // 3. 写入 bias
    for(int i=0;i<6;i++) {
        LENET_BIAS32[i] = 0;           // bias
    }

    // 4. 启动计算
    LENET_CTRL = 0x1;                  // ★ 启动

    // 5. 等待完成 (添加超时保护)
    uint32_t timeout = 0;
    while((LENET_STATUS & 0x1)==0) {
        if(++timeout > 10000000) {
            break;                     // 防死锁
        }
    }

    // 6. 读取结果
    volatile int32_t r0 = LENET_OUTPUT32[0];
    (void)r0;
}

int main(void) {
    test_lenet();
    while(1);
    return 0;
}