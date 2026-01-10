#include <stdint.h>
#include <stdio.h>
#include "bsp/hbird-e200/env/platform.h"
// platform.h 未声明 get_cpu_freq()，这里补一个前置声明避免隐式声明警告
unsigned long get_cpu_freq(void);
// System clock: ~19.23 MHz (50MHz * 40 / 104 = 19.23 MHz)
#define UART_CLK_HZ 19230769u
// Default CPU clock used for other timing fallback 
#define CPU_HZ_DEFAULT 19230769u

static uint32_t cpu_hz_get_sane(void)
{
    uint32_t hz = (uint32_t)get_cpu_freq();
    // If CLINT/mtime isn't ticking yet, get_cpu_freq() can be wrong/zero.
    if ((hz < 1000000u) || (hz > 500000000u)) {
        hz = CPU_HZ_DEFAULT;
    }
    return hz;
}

static void uart0_force_init(uint32_t baud)
{
    // Select IOF0 for UART0 pins and enable IOF on GPIO16/17
    GPIO_REG(GPIO_IOF_SEL) &= ~IOF0_UART0_MASK;
    GPIO_REG(GPIO_IOF_EN)  |=  IOF0_UART0_MASK;

    // 计算 UART 分频：DIV = (uart_clk / baud) - 1
    // UART 使用专用的 24 MHz 时钟，可精确整除 115200 (24000000/115200=208.33)
    {
        uint32_t uart_freq = UART_CLK_HZ;  
        uint32_t div;
        if (baud == 0u) {
            div = 0u;
        } else if (uart_freq >= baud) {
            div = (uart_freq / baud) - 1u;  
        } else {
            div = 0u;
        }
        UART0_REG(UART_REG_DIV) = div;
    }
    UART0_REG(UART_REG_TXCTRL) |= UART_TXEN;
    UART0_REG(UART_REG_RXCTRL) |= UART_RXEN;
}

static void led0_init(void)
{
    // gpio_out[0] is constrained to LED0 in CST
    GPIO_REG(GPIO_OUTPUT_EN) |= 0x1u;
}

static void led0_toggle(void)
{
    //printf("LED TOGGLE\n");
    GPIO_REG(GPIO_OUTPUT_XOR) = 0x1u;
}

static void delay_loops(volatile uint32_t loops)
{
    while (loops--) {
        __asm__ volatile ("nop");
    }
}

// --- UART RX helpers (SiFive-style UART FIFO) ---
static int uart0_try_getc(uint8_t *out)
{
    uint32_t r = UART0_REG(UART_REG_RXFIFO);
    if (r & 0x80000000u) {
        return 0; // empty
    }
    *out = (uint8_t)(r & 0xFFu);
    return 1;
}

static uint8_t uart0_getc_blocking(void)
{
    uint8_t ch;
    while (!uart0_try_getc(&ch)) {
        // spin
    }
    return ch;
}

static void uart0_putc_blocking(uint8_t ch)
{
    while (UART0_REG(UART_REG_TXFIFO) & 0x80000000u) {
        // spin
    }
    UART0_REG(UART_REG_TXFIFO) = ch;
}

static void uart0_write(const uint8_t *buf, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++) {
        uart0_putc_blocking(buf[i]);
    }
    printf("UART: wrote %u bytes\n", len);
}

// Protocol:
//   Host -> board: 'L''N' + fmt(1B) + payload(784B) + checksum_u16_le
//     fmt: 0 = uint8(0..255), 1 = int8 bytes (two's complement)
//     checksum: sum(payload bytes) mod 65536
//   Board -> host: one ASCII line starting with "R "
#define UART_MAGIC0 'L'
#define UART_MAGIC1 'N'
// 注意：此函数位于尺寸宏定义之前，所以这里用固定的 784 字节常量，避免依赖 INPUT_SIZE
#define UART_IMG_BYTES 784u
static int uart_recv_lenet_frame(uint8_t payload[UART_IMG_BYTES], uint8_t *fmt_out)
{
    // Find magic sequence in the stream
    for (;;) {
        uint8_t b0 = uart0_getc_blocking();
        if (b0 != (uint8_t)UART_MAGIC0) {
            continue;
        }
        uint8_t b1 = uart0_getc_blocking();
        if (b1 != (uint8_t)UART_MAGIC1) {
            continue;
        }
        break;
    }

    uint8_t fmt = uart0_getc_blocking();
    if (fmt_out) {
        *fmt_out = fmt;
    }

    uint32_t sum = 0;
    for (uint32_t i = 0; i < UART_IMG_BYTES; i++) {
        uint8_t v = uart0_getc_blocking();
        payload[i] = v;
        sum += v;
    }
    uint8_t c0 = uart0_getc_blocking();
    uint8_t c1 = uart0_getc_blocking();
    uint16_t rx_ck = (uint16_t)c0 | ((uint16_t)c1 << 8);
    uint16_t cal_ck = (uint16_t)(sum & 0xFFFFu);
    if (rx_ck != cal_ck) {
        return -1;
    }
    // fmt is informational (payload bytes are written as-is to low 8 bits)
    (void)fmt;
    printf("UART: received frame, checksum OK (0x%04X)\n", cal_ck);
    return 0;
}

// Lenet 加速器地址 (PWM2 地址)
#define LENET_BASE      0x10035000
#define LENET_CTRL      (*(volatile uint32_t *)(LENET_BASE + 0x0000))
#define LENET_STATUS    (*(volatile uint32_t *)(LENET_BASE + 0x0004))

// 改为 32 位指针,每次写入 4 个字节
#define LENET_INPUT32   ((volatile uint32_t *)(LENET_BASE + 0x0010))
#define LENET_WEIGHT32  ((volatile uint32_t *)(LENET_BASE + 0x1000))
#define LENET_BIAS32    ((volatile uint32_t *)(LENET_BASE + 0x2000))
#define LENET_OUTPUT32  ((volatile uint32_t *)(LENET_BASE + 0x3000))

// 和 RTL 保持一致的尺寸
#define IN_CH       1
#define OUT_CH      6
#define IN_SIZE     28
#define K           5
#define OUT_SIZE    (IN_SIZE - K + 1)

#define INPUT_SIZE   (IN_CH*IN_SIZE*IN_SIZE)      // 784
#define WEIGHT_SIZE  (OUT_CH*IN_CH*K*K)           // 150
#define BIAS_SIZE    (OUT_CH)                     // 6
#define OUTPUT_SIZE  (OUT_CH*OUT_SIZE*OUT_SIZE)   // 3456

// ========= 上板用：需要你自己填真实数据 =========
static const int8_t input_data[784] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 41, 92, 79, 75, 29, 17,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 110, 126, 126, 126, 126, 120, 98, 98, 98, 98,
    98, 98, 98, 98, 84, 25, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 33, 56, 35, 56, 81, 113, 126, 112, 126, 126, 126, 124, 114, 126,
    126, 69, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 8, 32, 6, 33, 33, 33, 29, 10, 117, 126, 52, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 41, 126, 104, 8, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 10, 116, 127, 41, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 126, 118,
    21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 29, 124, 126, 30, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 66, 126, 93, 2, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4,
    102, 123, 28, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 62, 126, 90, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 37, 125, 119, 28, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 9, 110, 126, 82, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 101, 126, 109,
    17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 18, 126, 126, 38, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 15, 111, 126, 57, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 66,
    126, 126, 25, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 30, 120, 126, 126, 25, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 60, 126, 126, 109, 19, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 60, 126, 103, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

// weight_data: int8, length = 150
static const int8_t weight_data[150] = {
    -16, 7, -30, -25, 3, -28, -7, 24, 6, 23, -18, -1, 37, 22, -15, 6,
    31, 0, -23, 2, 15, 12, -13, -2, 6, 19, 27, -5, -14, -33, 22, 4,
    27, -7, -38, 12, 26, -15, -39, -37, 34, 29, 13, 5, 3, -11, 33, -11,
    -6, -11, 9, 31, -16, -21, -8, 19, -2, -5, -5, -4, -5, -10, -33, -29,
    -35, -12, 26, -16, -10, -7, 19, 13, 34, 56, 53, 20, 9, -25, 0, -16,
    -16, 22, 26, -18, -35, -7, 37, 19, 1, -28, -27, 13, 32, 23, 11, -6,
    -12, 14, 0, 21, 2, 0, 15, -26, 0, 2, -1, -2, 31, 10, 25, 5,
    22, 17, 24, 8, 10, -12, 0, 26, 7, 8, -29, -43, -24, -48, -1, -3,
    18, 24, -16, -8, 0, 32, 30, -15, 14, 27, 17, 33, -15, -8, 12, 20,
    -7, -10, 24, -3, -13, -38
};

// bias_data: int32, length = 6
static const int32_t bias_data[6] = {
    7, 14, 9, -33, 8, -9
};
// =================================================

void test_lenet(void) {
    printf("\n[LENET] test start\n");
    const uint32_t cpu_hz = cpu_hz_get_sane();
    printf("[LENET] cpu_hz=%u\n", cpu_hz);

    uint64_t t0 = get_cycle_value();

    // 写输入 feature map（每个元素用低 8bit）
    for (uint32_t i = 0; i < INPUT_SIZE; i++) {
        uint8_t v = (uint8_t)input_data[i];
        LENET_INPUT32[i] = (uint32_t)v;
    }

    // 写权重
    for (uint32_t i = 0; i < WEIGHT_SIZE; i++) {
        uint8_t v = (uint8_t)weight_data[i];
        LENET_WEIGHT32[i] = (uint32_t)v;
    }

    // 写 bias（本来就是 32bit）
    for (uint32_t i = 0; i < BIAS_SIZE; i++) {
        LENET_BIAS32[i] = (uint32_t)bias_data[i];
    }

    uint64_t t1 = get_cycle_value();
    printf("[LENET] load done, cycles=%llu\n", (unsigned long long)(t1 - t0));

    // 启动加速器（先清再置位，FSM 需看到上升沿）
    printf("[LENET] CONV START\n");
    LENET_CTRL = 0x0;
    LENET_CTRL = 0x1;

    // 轮询等待 done
    uint32_t timeout = 0;
    while ((LENET_STATUS & 0x1) == 0) {
        if (++timeout > 100000000) {
            printf("[LENET] TIMEOUT waiting done\n");
            break;
        }
    }

    uint64_t t2 = get_cycle_value();
    const uint64_t conv_cycles = t2 - t1;
    const uint64_t conv_us = (cpu_hz == 0) ? 0 : (conv_cycles * 1000000ull) / cpu_hz;
    printf("[LENET] done=%u, conv_cycles=%llu, conv_us=%llu\n",
           (unsigned)(LENET_STATUS & 1u),
           (unsigned long long)conv_cycles,
           (unsigned long long)conv_us);

    // 读取输出摘要：前 16 个 + 全部求和（便于和 Python/参考模型对比）
    int64_t sum = 0;
    printf("[LENET] y[0..15]=");
    for (uint32_t i = 0; i < 16; i++) {
        int32_t y = (int32_t)LENET_OUTPUT32[i];
        sum += y;
        printf("%ld%s", (long)y, (i == 15) ? "\n" : ",");
    }
    for (uint32_t i = 16; i < OUTPUT_SIZE; i++) {
        sum += (int32_t)LENET_OUTPUT32[i];
    }
    printf("[LENET] output_sum=%lld\n", (long long)sum);
}

static void run_lenet_with_input_bytes(const uint8_t input_bytes[INPUT_SIZE])
{
    const uint32_t cpu_hz = cpu_hz_get_sane();

    uint64_t t0 = get_cycle_value();

    // Write input (low 8-bit)
    for (uint32_t i = 0; i < INPUT_SIZE; i++) {
        LENET_INPUT32[i] = (uint32_t)input_bytes[i];
    }

    // Keep weights/bias from compiled-in arrays
    for (uint32_t i = 0; i < WEIGHT_SIZE; i++) {
        uint8_t v = (uint8_t)weight_data[i];
        LENET_WEIGHT32[i] = (uint32_t)v;
    }
    for (uint32_t i = 0; i < BIAS_SIZE; i++) {
        LENET_BIAS32[i] = (uint32_t)bias_data[i];
    }

    uint64_t t1 = get_cycle_value();

    // Pulse start: deassert then assert to let FSM return to IDLE between runs
    printf("[LENET] CONV START\n");
    LENET_CTRL = 0x0;
    LENET_CTRL = 0x1;

    uint32_t timeout = 0;
    while ((LENET_STATUS & 0x1u) == 0u) {
        if (++timeout > 100000000u) {
            break;
        }
    }

    uint64_t t2 = get_cycle_value();
    const uint64_t load_cycles = t1 - t0;
    const uint64_t conv_cycles = t2 - t1;
    const uint64_t conv_us = (cpu_hz == 0) ? 0 : (conv_cycles * 1000000ull) / cpu_hz;

    int64_t sum = 0;
    int32_t y0 = (int32_t)LENET_OUTPUT32[0];
    int32_t y1 = (int32_t)LENET_OUTPUT32[1];
    int32_t y15 = (int32_t)LENET_OUTPUT32[15];
    int32_t y_last = (int32_t)LENET_OUTPUT32[OUTPUT_SIZE - 1];
    for (uint32_t i = 0; i < OUTPUT_SIZE; i++) {
        sum += (int32_t)LENET_OUTPUT32[i];
    }

    // Response: single line, easy to parse
    // Example: R done=1 load_cycles=... conv_cycles=... conv_us=... sum=... y0=... y1=... y15=... ylast=...
    printf("R done=%u load_cycles=%llu conv_cycles=%llu conv_us=%llu sum=%lld y0=%ld y1=%ld y15=%ld ylast=%ld\n",
           (unsigned)(LENET_STATUS & 1u),
           (unsigned long long)load_cycles,
           (unsigned long long)conv_cycles,
           (unsigned long long)conv_us,
           (long long)sum,
           (long)y0, (long)y1, (long)y15, (long)y_last);
}

int main(void) {
    //uart0_force_init(57600);
    _init();
    //led0_init();
    //led0_toggle();
    
    // Print clock info so we know what freq to use
    const uint32_t measured_hz = cpu_hz_get_sane();
    //printf("HELLO RISC-V WORLD!\n");
    //uart0_write("HELLO\r\n", 7);
    printf("CPU freq: %u Hz\n", measured_hz);
    // Heartbeat so you can see CPU is running even if UART isn't visible yet
    // for (int i = 0; i < 3; i++) {
    //     led0_toggle();
    //     delay_loops(2000000u);
    // }
    static uint8_t rx_img[INPUT_SIZE];
    // printf("[UART] Send frame: 'L''N' + fmt(1B) + 784B + checksum_u16_le\n");
    // printf("[UART] fmt=0(uint8) or 1(int8 bytes). checksum=sum(payload)%%65536\n");
    while (1) {
        uint8_t fmt = 0;
        int rc = uart_recv_lenet_frame(rx_img, &fmt);
        if (rc != 0) {
            const char msg[] = "E checksum\n";
            uart0_write((const uint8_t*)msg, (uint32_t)(sizeof(msg) - 1));
            continue;
        }
        
        const char ack[] = "OK\n";
        uart0_write((const uint8_t*)ack, (uint32_t)(sizeof(ack) - 1));
        (void)fmt;

        run_lenet_with_input_bytes(rx_img);
        printf("CONV DONE\n");
        //led0_toggle();
    }

    return 0;
}