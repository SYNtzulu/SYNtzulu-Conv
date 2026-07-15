#define WEIGHT_DEPTH 768
#define CHANNELS 256
#define TIME 0
#define SAMPLE_ADDR 1048576

// Pesi in flash, contigui dopo i campioni (500*256 = 128000 byte).
// Ogni banco = WEIGHT_DEPTH (768) word da 16 bit = 1536 byte.
#define WEIGHT_1_ADDR 1176576   // 0x11F400  (SAMPLE_ADDR + 128000)
#define WEIGHT_2_ADDR 1178112   // 0x11FA00  (+1536)
#define WEIGHT_3_ADDR 1179648   // 0x120000  (+1536)
#define WEIGHT_4_ADDR 1181184   // 0x120600  (+1536)