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
static void read_sample_mem();
static void read_spike_mem();
//static void check_and_load_next_instr(void);

/* === Instruction streaming parameters === */
/*
#define SPI_MEM_OUT_INSTR   (4u)     // servant_spi: 3'b100
#define INSTR_BYTES         (10u)    // 80 bit = 10 byte
#define INSTR_BLOCK_BYTES   (40u)    // 4 istruzioni = 40 byte
*/
/* Stato runtime */
//static uint32_t instr_base = INSTR_ADDR;
//static uint32_t instr_ptr  = INSTR_ADDR;
volatile uint32_t sample_addr = 0;

/* === MAIN === */
int main(void)
{
    DEV_WRITE(CLOCK_GATE_CTRL, 0);
    clear_csr(mstatus, MSTATUS_MIE_BIT_MASK);
    write_csr(mie, 0);
    write_csr(mtvec, ((uint_xlen_t) irq_entry));

    DEV_WRITE(SERVANT_GPIO_ADDR, 0xaaaaaaaa);
    while (DEV_READ(SERVANT_GPIO_ADDR) & 0xf0000000);
    DEV_WRITE(SERVANT_GPIO_ADDR, 0x55555555);
    
    uart_send(6);
    uart_send(7);
    uart_send(7);
    uart_send(6);

    // carico pesi
    //spi_load_to_mem(WEIGHT_1_ADDR, 0, WEIGHT_DEPTH*8);
    //spi_load_to_mem(WEIGHT_2_ADDR, 1, WEIGHT_DEPTH*8);
    //spi_load_to_mem(WEIGHT_3_ADDR, 2, WEIGHT_DEPTH*8);
    //spi_load_to_mem(WEIGHT_4_ADDR, 3, WEIGHT_DEPTH*8);
/*
    // preload 2 istruzioni 
    spi_load_to_mem(INSTR_ADDR, SPI_MEM_OUT_INSTR, INSTR_BYTES*8);
    instr_ptr += INSTR_BYTES;

    spi_load_to_mem(instr_ptr, SPI_MEM_OUT_INSTR, INSTR_BYTES*8);
    instr_ptr += INSTR_BYTES;*/

    // primo sample
    spi_load_sample(SAMPLE_ADDR, CHANNELS*8);
    sample_addr = SAMPLE_ADDR + CHANNELS;

    send_inference();

    mtimer_set_raw_time_cmp(TIME);
    set_csr(mie, MIE_MTI_BIT_MASK);
    set_csr(mstatus, MSTATUS_MIE_BIT_MASK);

    while (1) {
        // polling leggero e reattivo
        //check_and_load_next_instr();
    }
}

/* === IRQ === */
static void irq_entry(void)
{
    spi_load_sample(sample_addr, CHANNELS*8);
    sample_addr += CHANNELS;

    send_inference();
    DEV_WRITE(CLOCK_GATE_CTRL, 1);
    asm volatile("wfi");
}

/* === SPI helpers === */
static void spi_load_to_mem(uint32_t flash_addr, uint32_t which_mem, uint32_t nbytes)
{
    DEV_WRITE(SPI_ADDR, flash_addr);
    DEV_WRITE(SPI_SEL_MEM_OUT, which_mem);
    DEV_WRITE(SPI_READ_SIZE_ADDR, nbytes);   // *** BYTE ***
    DEV_WRITE(SPI_START_ADDR, 1);
    while (DEV_READ(SPI_VALID_ADDR) == 0);
    (void)DEV_READ(SPI_VALID_ADDR);
}

static void spi_load_sample(uint32_t flash_addr, uint32_t nbits)
{
    DEV_WRITE(SPI_ADDR, flash_addr);
    DEV_WRITE(SPI_SEL_MEM_OUT, 5);           // input buffer
    DEV_WRITE(SPI_READ_SIZE_ADDR, nbits);    // qui sono bit (come avevi)
    DEV_WRITE(SPI_START_ADDR, 1);
    while (DEV_READ(SPI_VALID_ADDR) == 0);
    (void)DEV_READ(SPI_VALID_ADDR);
}

/* === UART === */
inline static void uart_send(uint32_t data)
{
    DEV_WRITE(UART_DATA_ADDR, data);
    DEV_WRITE(UART_SEND_ADDR, 1);
    while (!DEV_READ(UART_READY_ADDR));
}

/* === Inferenza === */
static void send_inference(void)
{
    uint32_t s;
    do {
        s = DEV_READ(SYNTZULU_CLASS);
    } while ((s & 0x01) == 0);

    uart_send(s >> 1);
        
    //read_spike_mem();
        
    DEV_WRITE(SYNTZULU_VALID_RST, 1);
    DEV_WRITE(SYNTZULU_VALID_RST, 0);
}

static void read_spike_mem(){
	DEV_WRITE(SYNTZULU_SPIKE_MEM, 1);
    uint32_t i, spike_mem;
    for(i=0; i<4*4; i=i+4){
    	spike_mem = DEV_READ(0x40130000+i);
    	uart_send(spike_mem>>8);
    	uart_send(spike_mem);
    }
}
/*
static void read_sample_mem() {
	uint32_t k,dummy; 
		for(k=0;k<8*4;k=k+4) {
			dummy = DEV_READ(SAMPLE_MEM+k);
			uart_send(dummy>>8);
			uart_send(dummy); 
		}
}*/

/* === Gestione istruzioni  === *//*
static void check_and_load_next_instr(void)
{
    static uint32_t prev_free = 0;
    uint32_t free = DEV_READ(SYNTZULU_INSTR_FREE) & 1;

    if (free && !prev_free) {
        DEV_WRITE(SPI_ADDR, instr_ptr);
        DEV_WRITE(SPI_SEL_MEM_OUT, 4);
        DEV_WRITE(SPI_READ_SIZE_ADDR, INSTR_BYTES*8);
        DEV_WRITE(SPI_START_ADDR, 1);

        instr_ptr += INSTR_BYTES;
        if (instr_ptr >= instr_base + INSTR_BLOCK_BYTES)
            instr_ptr = instr_base;
    }

    prev_free = free;
}
*/

