// Memory mapping for slave peripherals
`define DMEM  3'b000
`define UART  3'b001
`define ACC   3'b010
`define BRAM  3'b011
`define TIMER 3'b100
`define SPI   3'b101
`define GPIO  3'b110
`define CLK   3'b111

// Memory mapping for SPI slave interface
`define SPI_ADDR          4'h0 // SPI slave address
`define SPI_SEL_MEM_OUT  4'h1 // Memory to write to
`define SPI_READ_SIZE_ADDR 4'h2 // Number of bytes to read from SPI
`define SPI_START_ADDR   4'h3 // Start address for SPI operations
`define SPI_VALID_ADDR   4'h4 // Valid address for SPI operations
`define SPI_DEBUG_ADDR   4'h5 // Debug address for SPI operations (only for debugging purposes)