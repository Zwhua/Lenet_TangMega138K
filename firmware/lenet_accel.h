#ifndef LENET_ACCEL_H
#define LENET_ACCEL_H

#include <stdint.h>

/*
 * 先假定 LeNet 加速器挂在这个基地址（以后和 Verilog 对齐就行）
 * 0x1001_0000 只是占位，后面硬件同学可以改成一致的值
 */
#define LENET_BASE_ADDR   0x10042000

/* 寄存器偏移 */
#define LENET_REG_CTRL    0x00u  // 控制寄存器：bit0 = start
#define LENET_REG_STATUS  0x04u  // 状态寄存器：bit0 = done, bit1 = busy（可选）
#define LENET_REG_IMGADDR 0x08u  // 输入图片地址
#define LENET_REG_WGTADDR 0x0Cu  // 权重地址
#define LENET_REG_OUTADDR 0x10u  // 输出结果地址

/* 方便读写的宏（内存映射寄存器） */
#define LENET_CTRL        (*(volatile uint32_t *)(LENET_BASE_ADDR + LENET_REG_CTRL))
#define LENET_STATUS      (*(volatile uint32_t *)(LENET_BASE_ADDR + LENET_REG_STATUS))
#define LENET_IMG_ADDR    (*(volatile uint32_t *)(LENET_BASE_ADDR + LENET_REG_IMGADDR))
#define LENET_WGT_ADDR    (*(volatile uint32_t *)(LENET_BASE_ADDR + LENET_REG_WGTADDR))
#define LENET_OUT_ADDR    (*(volatile uint32_t *)(LENET_BASE_ADDR + LENET_REG_OUTADDR))

/* CTRL 寄存器位定义 */
#define LENET_CTRL_START  (1u << 0)   // 写 1 触发一次计算（硬件看到后可以自动清 0）

/* STATUS 寄存器位定义 */
#define LENET_STATUS_DONE (1u << 0)   // 计算完成
#define LENET_STATUS_BUSY (1u << 1)   // 正在计算（可选，有就用）

/* 启动一次推理：告诉加速器图片/权重/输出地址，然后拉 start */
static inline void lenet_accel_start(uint32_t img, uint32_t wgt, uint32_t out)
{
    LENET_IMG_ADDR = img;
    LENET_WGT_ADDR = wgt;
    LENET_OUT_ADDR = out;
    LENET_CTRL     = LENET_CTRL_START;
}

/* 轮询是否完成 */
static inline int lenet_accel_is_done(void)
{
    return (LENET_STATUS & LENET_STATUS_DONE) != 0u;
}

/* 可选：查询是否 busy */
static inline int lenet_accel_is_busy(void)
{
    return (LENET_STATUS & LENET_STATUS_BUSY) != 0u;
}

#endif /* LENET_ACCEL_H */
