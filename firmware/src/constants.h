#define WEIGHT_DEPTH 768
#define CHANNELS 256
/*
 * Periodo del timer di sistema, in tick del prescaler di clk_gen_wb
 * (SLOW_DIV = 2400 a 24 MHz -> un tick ogni 100 us). Dal riarmo alla
 * successiva o_irq passano circa (TIME+1) tick, quindi 20 -> ~2.1 ms.
 *
 * NON PUO' ESSERE 0. servant_slow_timer.v:72 fa "o_irq <= (mtimeslice >=
 * mtimecmp)": con mtimecmp = 0 il confronto unsigned e' sempre vero, o_irq
 * resta alta per sempre e clk_gen_wb non arriva mai ad abbassare clk_en.
 * Era questa la ragione per cui il clock gating non entrava mai.
 *
 * Il limite inferiore e' il tempo di una ISR (caricamento SPI del campione +
 * inferenza + UART): sotto quello il core non fa in tempo a tornare in idle e
 * la finestra di gating sparisce.
 */
#define TIME 20
#define SAMPLE_ADDR 1048576

// Pesi in flash, contigui dopo i campioni (500*256 = 128000 byte).
// Ogni banco = WEIGHT_DEPTH (768) word da 16 bit = 1536 byte.
#define WEIGHT_1_ADDR 1176576   // 0x11F400  (SAMPLE_ADDR + 128000)
#define WEIGHT_2_ADDR 1178112   // 0x11FA00  (+1536)
#define WEIGHT_3_ADDR 1179648   // 0x120000  (+1536)
#define WEIGHT_4_ADDR 1181184   // 0x120600  (+1536)

// Soglie delta mem: 256 word da 16 bit {delta, prev_init}, subito dopo weight_4.
#define DELTA_ADDR  1182720     // 0x120C00  (WEIGHT_4_ADDR + 1536)
#define DELTA_WORDS 256

// Istruzioni SNN: 25 word da 16 bit, slot fisso 512 B dopo la delta.
// (Il firmware CPU sta a 0x121000, caricato dalla boot ROM.)
#define INSTR_ADDR      1183232 // 0x120E00  (DELTA_ADDR + 512)
#define INSTR_MEM_WORDS 25      // LAYERS*INSTR_WIDTH/16 = 5*5