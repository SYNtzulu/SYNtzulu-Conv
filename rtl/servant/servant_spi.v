`include "rtl/servant/memory_mapping.v"

module servant_spi(
    // ---------------- Wishbone Interface ----------------
    input               i_wb_clk,
    input               i_wb_rst,
    input  [31:0]       i_wb_spi_adr,
    input  [31:0]       i_wb_spi_dat,
    input               i_wb_spi_we,
    input               i_wb_spi_cyc,
    output reg [31:0]   o_wb_spi_rdt,
    output              o_wb_spi_ack,
    // ---------------- SPI Slave interface ----------------
    output              o_flash_sck,
    output              o_flash_ss,
    output              o_flash_mosi,
    input               i_flash_miso,
    // ---------------- SPRAM Signals ----------------
    output wire wen_intmem1,
    output wire [13:0] wr_addr_intmem1,
    output wire [15:0] wr_data_intmem1,
    output wire wen_intmem2,
    output wire [13:0] wr_addr_intmem2,
    output wire [15:0] wr_data_intmem2,
    output wire wen_intmem3,
    output wire [13:0] wr_addr_intmem3,
    output wire [15:0] wr_data_intmem3,
    output wire wen_intmem4,
    output wire [13:0] wr_addr_intmem4,
    output wire [15:0] wr_data_intmem4,
    // ---------------- Delta mem signals (SPI_SEL_MEM_OUT == 6) ----------------
    output wire wen_delta,
    output wire [9:0]  wr_addr_delta,
    output wire [15:0] wr_data_delta,
    // ---------------- CPU RAM / firmware boot (SPI_SEL_MEM_OUT == 7) ----------
    output wire        wen_ram_boot,
    output wire [9:0]  wr_addr_ram,
    output wire [31:0] wr_data_ram,
    // ---------------- Instruction signals (SPI_SEL_MEM_OUT == 4) -----------
    output wire        wen_instr,
    output wire [13:0] wr_addr_instr,
    output wire [15:0] wr_data_instr,
    // ---------------- Input buffer signals ----------------
    (* keep *) output wire wen_inputbuffer,
    output wire [13:0] wr_addr_inputbuffer,
    output wire [15:0] wr_data_inputbuffer
);

// Internal signals
wire [3:0] spi_reg_sel;
assign spi_reg_sel = i_wb_spi_adr[19:16];
wire spi_enable, spi_byte_valid, spi_transaction_valid;
reg spi_rd_ack, spi_enable_d;
wire [7:0] spi_rd_data; // Data received from SPI
reg wb_ack, wb_cyc_d;

// Memory mapped SPI registers
reg [23:0] mm_spi_adr; // SPI slave address register
reg [31:0] mm_mem_address; // Memory address to write to
reg [17:0] mm_read_size; // Number of bytes to read from SPI
reg mm_spi_start;
reg mm_spi_valid; // Status of the SPI operation

always @(posedge i_wb_clk) begin
    if (i_wb_rst) begin
        // Reset all memory mapped registers
        mm_spi_start <= 0;
        mm_mem_address <= 0;
        mm_read_size <= 0;
    end
    else begin 
        case (spi_reg_sel)
            // SPI_ADDR: Select SPI slave address
            `SPI_ADDR: begin 
                if (i_wb_spi_cyc && i_wb_spi_we) begin
                    mm_spi_adr <= i_wb_spi_dat;
                end
                else if (i_wb_spi_cyc && ~i_wb_spi_we) begin
                    o_wb_spi_rdt <= mm_spi_adr;
                end
            end

            // SPI_SEL_MEM_OUT: Select memory to write to
            `SPI_SEL_MEM_OUT: begin
                if (i_wb_spi_cyc && i_wb_spi_we) begin
                    mm_mem_address <= i_wb_spi_dat;
                end
                else if (i_wb_spi_cyc && ~i_wb_spi_we) begin
                    o_wb_spi_rdt <= mm_mem_address;
                end
            end

            // SPI_READ_SIZE_ADDR: Number of bytes to read from SPI (write only)
            `SPI_READ_SIZE_ADDR: begin
                if (i_wb_spi_cyc && i_wb_spi_we) begin
                    mm_read_size <= i_wb_spi_dat; 
                end
            end

            // SPI_START_ADDR: Start address for SPI operations (write only)
            `SPI_START_ADDR: begin
                if (i_wb_spi_cyc && i_wb_spi_we) begin
                    mm_spi_start <= i_wb_spi_dat[0]; // Only the LSB is used to start the SPI operation
                end
                else 
                    mm_spi_start <= 0; // Auto clear the start signal after it has been used
            end

            // SPI_VALID_ADDR: Valid address for SPI operations (read only)
            `SPI_VALID_ADDR: begin
                if (i_wb_spi_cyc && ~i_wb_spi_we) begin
                    o_wb_spi_rdt <= {31'b0, mm_spi_valid}; // Return the status of the SPI operation
                end
            end

            `SPI_DEBUG_ADDR: begin
                if (i_wb_spi_cyc && ~i_wb_spi_we) begin
                    o_wb_spi_rdt <= spi_debug_reg; // Return the last received data from SPI
                end
            end
            endcase
    end
end


// SPI start handling: it generate a pulse when mm_spi_start is set to start the SPI operation
reg mm_spi_start_d;
always @(posedge i_wb_clk) begin
    if (i_wb_rst) begin
        mm_spi_start_d <= 0;
        spi_enable_d <= 0;
    end
    else begin
        spi_enable_d <= spi_enable; // Store the previous state of spi_enable
        mm_spi_start_d <= mm_spi_start;
    end
end
assign spi_enable = mm_spi_start & ~mm_spi_start_d; 



// SPI end transaction handling: mm_spi_valid is set when the SPI operation is completed and it is cleared after
// a bus access to the SPI_VALID_ADDR register
wire reading_spi_valid_reg = i_wb_spi_cyc && ~i_wb_spi_we && (spi_reg_sel == `SPI_VALID_ADDR);


reg valid_rst_cond = 0;
always @(posedge i_wb_clk) 
	valid_rst_cond <= mm_spi_valid && reading_spi_valid_reg;

always @(posedge i_wb_clk) begin
    if (i_wb_rst) begin
        mm_spi_valid <= 0;
        spi_rd_ack <= 0;
    end else if (spi_transaction_valid) begin
        mm_spi_valid <= 1; // Set valid when the SPI transaction is completed
        spi_rd_ack <= 1; // Acknowledge the read operation
    end else if (valid_rst_cond) begin
        mm_spi_valid <= 0; // Clear valid when reading the SPI_VALID_ADDR register is read
        spi_rd_ack <= 0; // Acknowledge the read operation
    end
    else begin
        spi_rd_ack <= 0; 
    end
end

// Ack handling
always @(posedge i_wb_clk) begin
    if (i_wb_rst) begin
        wb_cyc_d <= 0;
        wb_ack <= 0;
    end else begin
        wb_cyc_d <= i_wb_spi_cyc;
        wb_ack <= i_wb_spi_cyc & ~wb_cyc_d; 
    end
end
assign o_wb_spi_ack = wb_ack; // Output the ack signal



////////////////////////////////////////////////////////////////
//  ____  ____ ___     __  __    _    ____ _____ _____ ____   //
// / ___||  _ \_ _|   |  \/  |  / \  / ___|_   _| ____|  _ \  //
// \___ \| |_) | |    | |\/| | / _ \ \___ \ | | |  _| | |_) | // 
//  ___) |  __/| |    | |  | |/ ___ \ ___) || | | |___|  _ <  //
// |____/|_|  |___|   |_|  |_/_/   \_\____/ |_| |_____|_| \_\ //
//                                                            //  
////////////////////////////////////////////////////////////////    

    spi_master_asic spi(
        .clk                (i_wb_clk),
        .reset              (i_wb_rst),
        .SPI_SCK            (o_flash_sck),
        .SPI_SS             (o_flash_ss),
        .SPI_MOSI           (o_flash_mosi),
        .SPI_MISO           (i_flash_miso), 
        .en                 (spi_enable),
        .addr               (mm_spi_adr),
        .valid              (spi_byte_valid),
        .end_transaction    (spi_transaction_valid),
        .rd_ack             (spi_rd_ack),
        .rd_data            (spi_rd_data),
        .words_to_read      (mm_read_size),
        .read_req           (1'b1), // Always read request is set to 1
        .wr_data            (8'b0) // No write data is used in this case
    );

    reg [31:0] spi_debug_reg; // Debug register to store SPI dato
    reg spi_byte_valid_d, spi_byte_valid_dd;
    wire spi_byte_valid_pulse;
    always @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            spi_byte_valid_d <= 0;
            spi_byte_valid_dd <= 0;
        end
        else begin
            spi_byte_valid_d <= spi_byte_valid_pulse;
            spi_byte_valid_dd <= spi_byte_valid_d; // Store the previous state of spi_byte_valid_d
        end
    end

    assign spi_byte_valid_pulse = spi_byte_valid & ~spi_byte_valid_d;

    always @(posedge i_wb_clk) begin
        if (i_wb_rst)
            spi_debug_reg <= 32'h00000000;
        else if (spi_byte_valid_pulse)
            spi_debug_reg <= {spi_debug_reg[23:0], spi_rd_data};
    end


    // SPI output memories mapping
    wire en_intmem1;
    assign en_intmem1 = mm_mem_address == 3'b000;
    wire en_intmem2;
    assign en_intmem2 = mm_mem_address == 3'b001;
    wire en_intmem3;
    assign en_intmem3 = mm_mem_address == 3'b010;
    wire en_intmem4;
    assign en_intmem4 = mm_mem_address == 3'b011;
    wire en_instr;
    assign en_instr = mm_mem_address == 3'b100;
    (* keep *)wire en_inputbuffer;
    assign en_inputbuffer = mm_mem_address == 3'b101;
    wire en_delta;
    assign en_delta = mm_mem_address == 3'b110;
    wire en_ram;
    assign en_ram = mm_mem_address == 3'b111;

    wire en_intmems;
    assign en_intmems = (en_intmem1 | en_intmem2 | en_intmem3 | en_intmem4 | en_inputbuffer | en_delta | en_instr)&spi_byte_valid_pulse;
    wire rst_out_spi;
    assign rst_out_spi = i_wb_rst | spi_enable;

    reg [15:0] data_in_intmems;
    reg [14:0] address_mems; // The first LSB bit is used as valid data, the others 14 are reserved for the address
    always @(posedge i_wb_clk) begin
        if (rst_out_spi) begin
            address_mems <= 0;
        end else if (spi_byte_valid_d) begin 
            address_mems <= address_mems+1; 
        end
    end 

    always @(posedge i_wb_clk) begin
        if (rst_out_spi | (address_mems[0]&spi_byte_valid_d))
            data_in_intmems <= 16'h0000;
        else if (en_intmems)
            data_in_intmems <= {data_in_intmems[7:0], spi_rd_data};
    end

    always @(posedge i_wb_clk) begin
        if (rst_out_spi | (address_mems[0]&spi_byte_valid_d))
            data_in_intmems <= 8'h0000;
        else if (en_intmems)
            data_in_intmems <= spi_rd_data;
    end

    // --- Assemblaggio 2 byte SPI -> 1 parola da 16 bit per le memorie pesi ---
    // La SPI consegna 8 bit alla volta; la ram_1024x16 vuole una parola da 16 bit
    // con un solo write-enable. Il primo byte del pair (indice pari) e' il byte
    // ALTO, il secondo (indice dispari) e' il byte BASSO -> hi-first, coerente col
    // layout dei pesi in flash.txt (es. C7 15 -> 0xC715). Una sola scrittura, sul
    // secondo byte del pair. Il path campioni (input buffer) resta invariato sotto.
    reg [7:0] hi_byte_intmem;
    always @(posedge i_wb_clk) begin
        if (rst_out_spi)
            hi_byte_intmem <= 8'h00;
        else if (en_intmems & ~address_mems[0])   // primo byte del pair = byte alto
            hi_byte_intmem <= spi_rd_data;
    end
    wire [15:0] word_intmem = {hi_byte_intmem, spi_rd_data};  // {alto, basso}
    wire        wen_word    = en_intmems & address_mems[0];    // scrive sul secondo byte

    assign wr_addr_intmem1 = address_mems[14:1];
    assign wr_data_intmem1 = word_intmem;
    assign wen_intmem1 = en_intmem1 & wen_word;

    assign wr_addr_intmem2 = address_mems[14:1];
    assign wr_data_intmem2 = word_intmem;
    assign wen_intmem2 = en_intmem2 & wen_word;

    assign wr_addr_intmem3 = address_mems[14:1];
    assign wr_data_intmem3 = word_intmem;
    assign wen_intmem3 = en_intmem3 & wen_word;

    assign wr_addr_intmem4 = address_mems[14:1];
    assign wr_data_intmem4 = word_intmem;
    assign wen_intmem4 = en_intmem4 & wen_word;

    // delta mem: parola 16-bit hi-first {delta, prev_init}, come i pesi
    assign wr_addr_delta = address_mems[10:1];
    assign wr_data_delta = word_intmem;
    assign wen_delta     = en_delta & wen_word;

    // --- CPU RAM (firmware): assembla 4 byte -> parola 32-bit, big-endian ---
    // Il primo byte del gruppo di 4 e' il piu' significativo. Scrittura sul 4o
    // byte (address_mems[1:0]==11), all'indirizzo di parola address_mems[11:2].
    wire en_ram_byte = en_ram & spi_byte_valid_pulse;
    reg [23:0] ram_acc;   // primi 3 byte del gruppo
    always @(posedge i_wb_clk) begin
        if (rst_out_spi)
            ram_acc <= 24'b0;
        else if (en_ram_byte & (address_mems[1:0] != 2'b11))
            ram_acc <= {ram_acc[15:0], spi_rd_data};
    end
    assign wr_data_ram  = {ram_acc, spi_rd_data};
    assign wr_addr_ram  = address_mems[11:2];
    assign wen_ram_boot = en_ram_byte & (address_mems[1:0] == 2'b11);
    // istruzioni SNN: parola 16-bit hi-first, come i pesi
    assign wr_addr_instr = address_mems[14:1];
    assign wr_data_instr = word_intmem;
    assign wen_instr     = en_instr & wen_word;

    assign wr_addr_inputbuffer = address_mems[14:1];
    assign wr_data_inputbuffer = data_in_intmems;
    assign wen_inputbuffer = en_inputbuffer & spi_byte_valid_d;
endmodule
