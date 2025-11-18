// See LICENSE for license details.
#include <stdio.h>
#include <stdint.h>
#include "hbird_sdk_soc.h"
#include "lenet_accel.h"

// 先假定三块内存区域的基地址（以后可以根据 SoC 内存映射再调整）
#define IMG_BASE_ADDR  0x80000000u   // 图片数据存放地址（例如一张 28x28 MNIST）
#define WGT_BASE_ADDR  0x80010000u   // 权重数据存放地址
#define OUT_BASE_ADDR  0x80020000u   // 推理结果存放地址

// ===== 软件版 LeNet 的占位函数 =====

// 简单的 3x3 卷积操作示例（现在只是占位，真正的算法以后再填）
void convolution(uint32_t img_addr, uint32_t wgt_addr, uint32_t out_addr)
{
    (void)img_addr;
    (void)wgt_addr;
    (void)out_addr;

    printf("Performing software convolution (placeholder)...\r\n");
    // TODO: 在这里实现真正的卷积运算（定点 or 浮点）
    printf("Software convolution done.\r\n");
}

// 简单的全连接层操作示例（占位）
void fully_connected(uint32_t out_addr)
{
    (void)out_addr;

    printf("Performing software fully-connected layer (placeholder)...\r\n");
    // TODO: 在这里实现真正的全连接计算
    printf("Software fully-connected layer done.\r\n");
}

// 小工具：读系统定时器当前值（直接用 SDK 提供的 SysTimer_GetLoadValue）
static inline uint64_t core_timer_get_value(void)
{
    return SysTimer_GetLoadValue();
}

int main(void)
{
    // 更新系统时钟信息
    SystemCoreClockUpdate();

    printf("\r\n===== LeNet Accelerator Skeleton =====\r\n");
    printf("SystemCoreClock = %u Hz\r\n", SystemCoreClock);
    printf("This is a simplified software framework for LeNet on E203.\r\n");

    printf("IMG_BASE_ADDR = 0x%08X\r\n", IMG_BASE_ADDR);
    printf("WGT_BASE_ADDR = 0x%08X\r\n", WGT_BASE_ADDR);
    printf("OUT_BASE_ADDR = 0x%08X\r\n", OUT_BASE_ADDR);

    // ========== 1. 软件版 LeNet 计时（基线） ==========

    printf("\r\n[SW] Running software LeNet (conv + fc) ...\r\n");

    uint64_t sw_t0 = core_timer_get_value();

    // 目前只是占位：卷积 + 全连接
    convolution(IMG_BASE_ADDR, WGT_BASE_ADDR, OUT_BASE_ADDR);
    fully_connected(OUT_BASE_ADDR);

    uint64_t sw_t1 = core_timer_get_value();
    uint64_t sw_cycles = sw_t1 - sw_t0;

    printf("[SW] Software LeNet took %lu cycles.\r\n",
           (unsigned long)sw_cycles);

    // ========== 2. 硬件加速版 LeNet 调用骨架 ==========

    printf("\r\n[HW] Preparing to start LeNet hardware accelerator...\r\n");

    // 这里假设 IMG/WGT/OUT 三块内存里已经有正确数据
    // 以后可以通过串口/预置数组等方式真正填进去

    // 注意：现在 SoC 里面还没有真正挂上你的 lenet 加速器 IP，
    // 如果在板子上直接 while 等待 done，有可能永远等不到。
    // 所以这里先演示调用流程，把等待部分先注释掉/简化。
    uint64_t hw_t0 = core_timer_get_value();

    lenet_accel_start(IMG_BASE_ADDR, WGT_BASE_ADDR, OUT_BASE_ADDR);
    printf("[HW] lenet_accel_start issued.\r\n");

    // 将来真正接好硬件以后，可以打开下面这段轮询等待：
    /*
    printf("[HW] Waiting for accelerator DONE flag...\r\n");
    while (!lenet_accel_is_done()) {
        // busy wait
    }
    printf("[HW] Accelerator reports DONE.\r\n");
    */

    uint64_t hw_t1 = core_timer_get_value();
    uint64_t hw_cycles = hw_t1 - hw_t0;

    printf("[HW] (TEMP) Hardware path took %lu cycles (without real waiting).\r\n",
           (unsigned long)hw_cycles);
    printf("[INFO] When hardware is ready, measure again with DONE polling enabled.\r\n");

    // ========== 3. 程序结束，停在死循环 ==========
    printf("\r\nLeNet accelerator demo finished, entering idle loop.\r\n");

    while (1) {
        // 以后可以在这里加：通过串口接受命令，触发多次推理
    }

    return 0;
}
