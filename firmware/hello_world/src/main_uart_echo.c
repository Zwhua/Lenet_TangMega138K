// Minimal UART echo/handshake firmware for e203 + UART0 on GPIO16/17 (IOF0)
// Purpose: verify TX/RX path and frame parser before integrating conv1_accel.
// Build: riscv-none-elf-gcc (see CMakeLists), link to ITCM/DTIM as in your flow.

#include <stdint.h>
#include "bsp/hbird-e200/env/platform.h"

// platform.h 未声明 get_cpu_freq()，补一个前置声明避免隐式声明警告
unsigned long get_cpu_freq(void);

#define CPU_HZ_DEFAULT 30000000u

#define UART_MAGIC0 'L'
#define UART_MAGIC1 'N'
#define UART_IMG_BYTES 784u

static void uart0_force_init(uint32_t baud)
{
    // 选择 IOF0: GPIO16=RX, GPIO17=TX
    GPIO_REG(GPIO_IOF_SEL) &= ~IOF0_UART0_MASK;
    GPIO_REG(GPIO_IOF_EN)  |=  IOF0_UART0_MASK;

    uint32_t cpu_hz = (uint32_t)get_cpu_freq();
    if ((cpu_hz < 1000000u) || (cpu_hz > 500000000u)) {
        cpu_hz = CPU_HZ_DEFAULT; // Fallback 30MHz
    }

    if (baud == 0u) {
        baud = 115200u;
    }
    UART0_REG(UART_REG_DIV) = cpu_hz / baud - 1u;
    UART0_REG(UART_REG_TXCTRL) |= UART_TXEN;
    UART0_REG(UART_REG_RXCTRL) |= UART_RXEN;
}

static inline void uart0_putc(uint8_t ch)
{
    while (UART0_REG(UART_REG_TXFIFO) & 0x80000000u) {
    }
    UART0_REG(UART_REG_TXFIFO) = ch;
}

static void uart_write_str(const char *s)
{
    while (*s) {
        uart0_putc((uint8_t)*s++);
    }
}

static int uart_try_getc(uint8_t *out)
{
    uint32_t r = UART0_REG(UART_REG_RXFIFO);
    if (r & 0x80000000u) {
        return 0; // empty
    }
    *out = (uint8_t)(r & 0xFFu);
    return 1;
}

static uint8_t uart_getc_blocking(void)
{
    uint8_t ch;
    while (!uart_try_getc(&ch)) {
    }
    return ch;
}

static void uart_write_hex16(uint16_t v)
{
    const char hex[16] = "0123456789ABCDEF";
    uart0_putc(hex[(v >> 12) & 0xF]);
    uart0_putc(hex[(v >> 8) & 0xF]);
    uart0_putc(hex[(v >> 4) & 0xF]);
    uart0_putc(hex[v & 0xF]);
}

static int uart_recv_lenet_frame(uint8_t payload[UART_IMG_BYTES], uint8_t *fmt_out, uint16_t *ck_out)
{
    // 寻找帧头 "LN"
    for (;;) {
        uint8_t b0 = uart_getc_blocking();
        if (b0 != (uint8_t)UART_MAGIC0) {
            continue;
        }
        uint8_t b1 = uart_getc_blocking();
        if (b1 != (uint8_t)UART_MAGIC1) {
            continue;
        }
        break;
    }

    uint8_t fmt = uart_getc_blocking();
    if (fmt_out) {
        *fmt_out = fmt;
    }

    uint32_t sum = 0;
    for (uint32_t i = 0; i < UART_IMG_BYTES; i++) {
        uint8_t v = uart_getc_blocking();
        payload[i] = v;
        sum += v;
    }
    uint8_t c0 = uart_getc_blocking();
    uint8_t c1 = uart_getc_blocking();
    uint16_t rx_ck = (uint16_t)c0 | ((uint16_t)c1 << 8);
    uint16_t cal_ck = (uint16_t)(sum & 0xFFFFu);
    if (ck_out) {
        *ck_out = cal_ck;
    }
    return (rx_ck == cal_ck) ? 0 : -1;
}

int main(void)
{
    uart0_force_init(115200u);
    uart_write_str("\r\n[E203] UART0 ready. Send LN frame.\r\n");

    // Quick echo for manual test: type any char, it bounces back.
    uart_write_str("[E203] Echo test: typing below will be echoed.\r\n");
    for (int i = 0; i < 4; i++) {
        uint8_t c = uart_getc_blocking();
        uart0_putc(c);
    }
    uart_write_str("\r\n[OK] Link looks alive.\r\n");

    // Frame loop
    uint8_t payload[UART_IMG_BYTES];
    for (;;) {
        uint8_t fmt = 0;
        uint16_t ck = 0;
        int rc = uart_recv_lenet_frame(payload, &fmt, &ck);
        if (rc == 0) {
            uart_write_str("R OK fmt=");
            uart0_putc((uint8_t)('0' + (fmt & 0x0F))); // fmt 为 0/1 时可读
            uart_write_str(" ck=0x");
            uart_write_hex16(ck);
            uart_write_str("\r\n");
        } else {
            uart_write_str("R BAD_CHECKSUM\r\n");
        }
    }
}
