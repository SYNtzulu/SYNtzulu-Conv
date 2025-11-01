#include <stdint.h>
#include "riscv-csr.h"
#include "riscv-interrupts.h"
#include "timer.h"
#include "peripherals.h"
#include "constants.h"

#define DEV_WRITE(addr, val)    (*((volatile uint32_t *)(addr)) = (val))
#define DEV_READ(addr)          (*((volatile uint32_t *)(addr)))

static void irq_entry(void) __attribute__((naked));

static void spi_load_to_mem(uint32_t flash_addr, uint32_t which_mem, uint32_t nbytes);
static void spi_load_sample(uint32_t flash_addr, uint32_t nbits);
static void uart_send(uint32_t data);
static void send_inference(void);

volatile uint32_t sample_addr = 0;

int main(void)
{
    // 1) accendo clock
    DEV_WRITE(CLOCK_GATE_CTRL, 0);

    // 2) disabilito interrupt globali
    clear_csr(mstatus, MSTATUS_MIE_BIT_MASK);
    write_csr(mie, 0);

    // 3) setto vettore irq
    write_csr(mtvec, ((uint_xlen_t) irq_entry));

    // 4) aspetta bottone
    DEV_WRITE(SERVANT_GPIO_ADDR, 0xaaaaaaaa);
    while (DEV_READ(SERVANT_GPIO_ADDR) & 0xf0000000);
    DEV_WRITE(SERVANT_GPIO_ADDR, 0x55555555);

    // 5) carico i pesi da flash via SPI
    spi_load_to_mem(WEIGHT_1_ADDR, 0, WEIGHT_DEPTH*8);   // intmem1
    spi_load_to_mem(WEIGHT_2_ADDR, 1, WEIGHT_DEPTH*8);   // intmem2
    spi_load_to_mem(WEIGHT_3_ADDR, 2, WEIGHT_DEPTH*8);   // intmem3
    spi_load_to_mem(WEIGHT_4_ADDR, 3, WEIGHT_DEPTH*8);   // intmem4

    // 6) carico primo sample nell’input buffer
    spi_load_sample(SAMPLE_ADDR, CHANNELS*8);
    sample_addr = SAMPLE_ADDR + CHANNELS;

    // 7) mando prima inference
    send_inference();

    // 8) timer
    // Setup timer at every sample time 
	mtimer_set_raw_time_cmp(TIME);
    // Enable MIE.MTI
    set_csr(mie, MIE_MTI_BIT_MASK);
    // Global interrupt enable 
    set_csr(mstatus, MSTATUS_MIE_BIT_MASK);

    while (1);
    return 0;
}

static void irq_entry(void)
{
    // riattivo clock
    //DEV_WRITE(CLOCK_GATE_CTRL, 0);

    // carico nuovo sample
    spi_load_sample(sample_addr, CHANNELS*8);
    sample_addr += CHANNELS;

	send_inference();
	
    // turn high-frequency oscillator off
	//DEV_WRITE(CLOCK_GATE_CTRL, 0x00000008);
	//DEV_WRITE(CLOCK_GATE_CTRL, 0x00000010);
	DEV_WRITE(CLOCK_GATE_CTRL, 1);

    asm volatile("wfi");
}

static void spi_load_to_mem(uint32_t flash_addr, uint32_t which_mem, uint32_t nbits)
{
    DEV_WRITE(SPI_ADDR, flash_addr);
    DEV_WRITE(SPI_SEL_MEM_OUT, which_mem); // 0..3
    DEV_WRITE(SPI_READ_SIZE_ADDR, nbits);
    DEV_WRITE(SPI_START_ADDR, 1);

    while (DEV_READ(SPI_VALID_ADDR) == 0) { }
    (void)DEV_READ(SPI_VALID_ADDR);
}

static void spi_load_sample(uint32_t flash_addr, uint32_t nbits)
{
    DEV_WRITE(SPI_ADDR, flash_addr);
    DEV_WRITE(SPI_SEL_MEM_OUT, 4);
    DEV_WRITE(SPI_READ_SIZE_ADDR, nbits);
    DEV_WRITE(SPI_START_ADDR, 1);
    while (DEV_READ(SPI_VALID_ADDR) == 0) { }
    (void)DEV_READ(SPI_VALID_ADDR);
}

inline static void uart_send(uint32_t data) {
	DEV_WRITE(UART_DATA_ADDR, data);
    DEV_WRITE(UART_SEND_ADDR, 1);
    while(!DEV_READ(UART_READY_ADDR));
}

static void send_inference(void)
{
	uint32_t s;
    do { s = DEV_READ(SYNTZULU_CLASS); } 
    	while ((s & 0x01) == 0);
    if((s & 0x2) == 0x2){
    	uint32_t class = s >> 2;
    	uart_send(class);
    }
    DEV_WRITE(SYNTZULU_VALID_RST, 1);
    DEV_WRITE(SYNTZULU_VALID_RST, 0);
}

