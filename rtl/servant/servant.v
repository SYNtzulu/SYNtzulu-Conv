`default_nettype none
module servant#(
    parameter pClockFrequency = 24_000_000, // 24 MHz
    parameter pBaudRate = 4000000, // UART baud rate
    parameter UART_QUEUE = 1,
    parameter memfile = "zephyr_hello.hex",
    parameter memsize = 8192,
    parameter HFOSC = "0b01"
)(
    input i_clk,
    input i_rst,
    output wire [3:0]   led,
	  input  wire [2:0]   buttons,

  // --------------------- UART ---------------------
    input  wire         i_rxd,
    output wire         o_txd,
  // --------------------- SPI ---------------------
    input  wire         i_flash_miso,
    output wire         o_flash_sck,
    output wire         o_flash_ss,
    output wire         o_flash_mosi
);
    
    parameter reset_strategy = "MINI";
    parameter with_csr = 1;
    parameter [0:0] compress = 0;
    parameter [0:0] align = compress;

    wire [31:0] wb_ibus_adr;
    wire 	    wb_ibus_cyc;
    wire [31:0] wb_ibus_rdt;
    wire 	    wb_ibus_ack;

    wire [31:0] wb_dbus_adr;
    wire [31:0] wb_dbus_dat;
    wire [3:0] 	wb_dbus_sel;
    wire 	    wb_dbus_we;
    wire 	    wb_dbus_cyc;
    wire [31:0] wb_dbus_rdt;
    wire 	    wb_dbus_ack;

    wire [31:0] wb_dmem_adr;
    wire [31:0] wb_dmem_dat;
    wire [ 3:0] wb_dmem_sel;
    wire 	    wb_dmem_we;
    wire 	    wb_dmem_cyc;
    wire [31:0] wb_dmem_rdt;
    wire 	    wb_dmem_ack;

    wire [31:0]	wb_mem_adr;
    wire [31:0] wb_mem_dat;
    wire [ 3:0] wb_mem_sel;
    wire 	    wb_mem_we;
    wire 	    wb_mem_cyc;
    wire [31:0] wb_mem_rdt;
    wire 	    wb_mem_ack;

    // Boot ROM decode: fetch a ROM_BASE (0x8000_0000, bit 31) -> ROM, resto -> RAM.
    localparam [31:0] ROM_BASE = 32'h8000_0000;
    wire        is_rom = wb_mem_adr[31];
    wire [31:0] ram_rdt, rom_rdt;
    wire        ram_ack, rom_ack;
    assign wb_mem_rdt = is_rom ? rom_rdt : ram_rdt;
    assign wb_mem_ack = is_rom ? rom_ack : ram_ack;

    wire [31:0] wb_gamux_adr;
    wire [31:0]	wb_gamux_dat;
    wire        wb_gamux_we;
    wire 	    wb_gamux_cyc;
    wire [31:0]	wb_gamux_rdt;

	wire [31:0] wb_gpio_adr;
    wire [31:0] wb_gpio_dat;
    wire        wb_gpio_we;
    wire 	    wb_gpio_cyc;
    wire [31:0] wb_gpio_rdt;

    wire [31:0] wb_timer_adr;
    wire [31:0] wb_timer_dat;
    wire 	    wb_timer_we;
    wire 	    wb_timer_cyc;
    wire [31:0] wb_timer_rdt;
    wire       timer_irq;

    wire [31:0] o_wb_acc_adr;
    wire [31:0] o_wb_acc_dat;
    wire        o_wb_acc_we;
    wire        o_wb_acc_cyc;
    wire [31:0] i_wb_acc_rdt;
    wire        i_wb_acc_ack;

    // --------------------- UART ---------------------
    wire [31:0] o_wb_uart_adr;
    wire [31:0] o_wb_uart_dat;
    wire        o_wb_uart_we;
    wire        o_wb_uart_cyc;
    wire [31:0] i_wb_uart_rdt;
    wire        i_wb_uart_ack;

    // --------------------- SPI ---------------------
    wire [31:0] wb_spi_adr;
    wire [31:0] wb_spi_dat;
    wire        wb_spi_we;
    wire        wb_spi_cyc;
    wire [31:0] wb_spi_rdt;
    wire        wb_spi_ack;


    // -------------------- CLK -------------------------
    wire [31:0] wb_clk_adr;
    wire [31:0] wb_clk_dat;
    wire 	      wb_clk_we;
    wire 	      wb_clk_cyc;
    wire [31:0] wb_clk_rdt;
    wire 	      wb_clk_ack;


    wire [31:0] mdu_rs1;
    wire [31:0] mdu_rs2;
    wire [ 2:0] mdu_op;
    wire        mdu_valid;
    wire [31:0] mdu_rd;
    wire        mdu_ready;

////////////////////////////////////////////////////////////////
//   ____ _     _  __                  _   ____  ____ _____   //
//  / ___| |   | |/ /   __ _ _ __   __| | |  _ \/ ___|_   _|  //
// | |   | |   | ' /   / _` | '_ \ / _` | | |_) \___ \ | |    //
// | |___| |___| . \  | (_| | | | | (_| | |  _ < ___) || |    //
//  \____|_____|_|\_\  \__,_|_| |_|\__,_| |_| \_\____/ |_|    //
//                                                            //
////////////////////////////////////////////////////////////////

    wire wb_clk;        // clock “veloce” (gated, verso CPU/RAM/periferiche)
    wire slow_tick;     // enable “lento” (prescaler da i_clk, era LFOSC)
    wire wb_rst;        // reset sincrono a wb_clk

    clk_gen_wb #(
        .HFOSC(HFOSC)
    ) clkgen (
        .i_clk (i_clk),          
        .i_rst (i_rst),
        .o_clk (wb_clk),
        .o_slow_tick(slow_tick),
        .o_rst (wb_rst),
        .timer_irq           (timer_irq),
        .i_wb_clkgen_adr     (wb_clk_adr),
        .i_wb_clkgen_dat     (wb_clk_dat),
        .i_wb_clkgen_we      (wb_clk_we),
        .i_wb_clkgen_cyc     (wb_clk_cyc),
        .o_wb_clkgen_rdt     (wb_clk_rdt),
        .o_wb_clkgen_ack     (wb_clk_ack)
    );

    wire [12:0] o_output_buffer_out;
    servant_arbiter arbiter(
        .i_wb_cpu_dbus_adr (wb_dmem_adr),
        .i_wb_cpu_dbus_dat (wb_dmem_dat),
        .i_wb_cpu_dbus_sel (wb_dmem_sel),
        .i_wb_cpu_dbus_we  (wb_dmem_we ),
        .i_wb_cpu_dbus_cyc (wb_dmem_cyc),
        .o_wb_cpu_dbus_rdt (wb_dmem_rdt),
        .o_wb_cpu_dbus_ack (wb_dmem_ack),

        .i_wb_cpu_ibus_adr (wb_ibus_adr),
        .i_wb_cpu_ibus_cyc (wb_ibus_cyc),
        .o_wb_cpu_ibus_rdt (wb_ibus_rdt),
        .o_wb_cpu_ibus_ack (wb_ibus_ack),

        .o_wb_cpu_adr (wb_mem_adr),
        .o_wb_cpu_dat (wb_mem_dat),
        .o_wb_cpu_sel (wb_mem_sel),
        .o_wb_cpu_we  (wb_mem_we ),
        .o_wb_cpu_cyc (wb_mem_cyc),
        .i_wb_cpu_rdt (wb_mem_rdt),
        .i_wb_cpu_ack (wb_mem_ack)
        );

   servant_mux servant_mux
     (
      .i_clk (wb_clk),
      .i_rst (wb_rst & (reset_strategy != "NONE")),
      .i_wb_cpu_adr (wb_dbus_adr),
      .i_wb_cpu_dat (wb_dbus_dat),
      .i_wb_cpu_sel (wb_dbus_sel),
      .i_wb_cpu_we  (wb_dbus_we),
      .i_wb_cpu_cyc (wb_dbus_cyc),
      .o_wb_cpu_rdt (wb_dbus_rdt),
      .o_wb_cpu_ack (wb_dbus_ack),

      .o_wb_mem_adr (wb_dmem_adr),
      .o_wb_mem_dat (wb_dmem_dat),
      .o_wb_mem_sel (wb_dmem_sel),
      .o_wb_mem_we  (wb_dmem_we),
      .o_wb_mem_cyc (wb_dmem_cyc),
      .i_wb_mem_rdt (wb_dmem_rdt),

      // GPIO
      .o_wb_gpio_adr (wb_gpio_adr),
      .o_wb_gpio_dat (wb_gpio_dat),
      .o_wb_gpio_we (wb_gpio_we),
      .o_wb_gpio_cyc (wb_gpio_cyc),
      .i_wb_gpio_rdt (wb_gpio_rdt), 

      // Accelerator
      .o_wb_acc_adr (o_wb_acc_adr),
      .o_wb_acc_dat (o_wb_acc_dat),
      .o_wb_acc_we  (o_wb_acc_we),
      .o_wb_acc_cyc (o_wb_acc_cyc),
      .i_wb_acc_rdt (i_wb_acc_rdt),
	    .i_wb_acc_ack (i_wb_acc_ack),

      // UART
      .o_wb_uart_adr (o_wb_uart_adr),
      .o_wb_uart_dat (o_wb_uart_dat),
      .o_wb_uart_we  (o_wb_uart_we),
      .o_wb_uart_cyc (o_wb_uart_cyc),
      .i_wb_uart_rdt (i_wb_uart_rdt),
	    .i_wb_uart_ack (i_wb_uart_ack),
      
      // SPI
      .o_wb_spi_adr (wb_spi_adr),
      .o_wb_spi_dat (wb_spi_dat),
      .o_wb_spi_we  (wb_spi_we),
      .o_wb_spi_cyc (wb_spi_cyc),
      .i_wb_spi_rdt (wb_spi_rdt),
      .i_wb_spi_ack (wb_spi_ack),

      // CLK
      .o_wb_clk_adr (wb_clk_adr),
      .o_wb_clk_dat (wb_clk_dat),
      .o_wb_clk_we  (wb_clk_we),
      .o_wb_clk_cyc (wb_clk_cyc),
      .i_wb_clk_rdt (wb_clk_rdt),
      .i_wb_clk_ack (wb_clk_ack),

      // TIMER
      .o_wb_timer_adr (wb_timer_adr),
      .o_wb_timer_dat (wb_timer_dat),
      .o_wb_timer_we  (wb_timer_we),
      .o_wb_timer_cyc (wb_timer_cyc),
      .i_wb_timer_rdt (wb_timer_rdt));

   servant_ram
     #(.memfile (memfile),
       .depth (memsize),
       .RESET_STRATEGY (reset_strategy))
   ram
     (// Wishbone interface
      .i_wb_clk (wb_clk),
      .i_wb_rst (wb_rst),
      .i_wb_adr (wb_mem_adr[$clog2(memsize)-1:2]),
      .i_wb_cyc (wb_mem_cyc & ~is_rom),
      .i_wb_we  (wb_mem_we) ,
      .i_wb_sel (wb_mem_sel),
      .i_wb_dat (wb_mem_dat),
      .o_wb_rdt (ram_rdt),
      .o_wb_ack (ram_ack),
      .boot_wen (wen_ram_boot_spi),
      .boot_addr(wr_addr_ram_spi),
      .boot_data(wr_data_ram_spi));

   rom_boot boot_rom
     (.i_wb_clk (wb_clk),
      .i_wb_rst (wb_rst),
      .i_wb_adr (wb_mem_adr[31:2]),
      .i_wb_cyc (wb_mem_cyc & is_rom),
      .o_wb_rdt (rom_rdt),
      .o_wb_ack (rom_ack));
		
	servant_slow_timer
		   #(.RESET_STRATEGY (reset_strategy),
			 .WIDTH (32))
	timer_slow
		   (.i_clk    (i_clk),   // always-on clock: resta vivo durante lo sleep
			.slow_tick (slow_tick),
			.i_rst    (wb_rst),
			.o_irq    (timer_irq),
			.i_wb_cyc (wb_timer_cyc),
			.i_wb_we  (wb_timer_we) ,
			.i_wb_dat (wb_timer_dat),
			.o_wb_rdt (wb_timer_rdt));
	
   servant_gpio gpio
     (.i_wb_clk (wb_clk),
      .i_wb_adr (wb_gpio_adr),            
      .i_wb_dat (wb_gpio_dat),
      .i_wb_we  (wb_gpio_we),
      .i_wb_cyc (wb_gpio_cyc),
      .o_wb_rdt (wb_gpio_rdt),
      .led   (led),
	  .buttons(buttons)); 

   serv_rf_top
     #(.RESET_PC (32'h8000_0000),   // boot dalla ROM (ROM_BASE); poi jump a RAM@0
       .RESET_STRATEGY (reset_strategy),
  `ifdef MDU
       .MDU(1),
  `endif 
       .WITH_CSR (with_csr),
       .COMPRESSED(compress),
       .ALIGN(align))
   cpu
     (
      .clk      (wb_clk),
      .i_rst    (wb_rst),
      .i_timer_irq  (timer_irq),
`ifdef RISCV_FORMAL
      .rvfi_valid     (),
      .rvfi_order     (),
      .rvfi_insn      (),
      .rvfi_trap      (),
      .rvfi_halt      (),
      .rvfi_intr      (),
      .rvfi_mode      (),
      .rvfi_ixl       (),
      .rvfi_rs1_addr  (),
      .rvfi_rs2_addr  (),
      .rvfi_rs1_rdata (),
      .rvfi_rs2_rdata (),
      .rvfi_rd_addr   (),
      .rvfi_rd_wdata  (),
      .rvfi_pc_rdata  (),
      .rvfi_pc_wdata  (),
      .rvfi_mem_addr  (),
      .rvfi_mem_rmask (),
      .rvfi_mem_wmask (),
      .rvfi_mem_rdata (),
      .rvfi_mem_wdata (),
`endif

      .o_ibus_adr   (wb_ibus_adr),
      .o_ibus_cyc   (wb_ibus_cyc),
      .i_ibus_rdt   (wb_ibus_rdt),
      .i_ibus_ack   (wb_ibus_ack),

      .o_dbus_adr   (wb_dbus_adr),
      .o_dbus_dat   (wb_dbus_dat),
      .o_dbus_sel   (wb_dbus_sel),
      .o_dbus_we    (wb_dbus_we),
      .o_dbus_cyc   (wb_dbus_cyc),
      .i_dbus_rdt   (wb_dbus_rdt),
      .i_dbus_ack   (wb_dbus_ack),
      
      //Extension
      .o_ext_rs1    (mdu_rs1),
      .o_ext_rs2    (mdu_rs2),
      .o_ext_funct3 (mdu_op),
      .i_ext_rd     (mdu_rd),
      .i_ext_ready  (mdu_ready),
      //MDU
      .o_mdu_valid  (mdu_valid));

`ifdef MDU
    mdu_top mdu_serv
    (
     .i_clk(wb_clk),
     .i_rst(wb_rst),
     .i_mdu_rs1(mdu_rs1),
     .i_mdu_rs2(mdu_rs2),
     .i_mdu_op(mdu_op),
     .i_mdu_valid(mdu_valid),
     .o_mdu_ready(mdu_ready),
     .o_mdu_rd(mdu_rd));
`else
    assign mdu_ready = 1'b0;
    assign mdu_rd = 32'b0;
`endif

  // =========================== UART Slave ===========================
  servant_uart #(
    .pClockFrequency(pClockFrequency),
    .pBaudRate      (pBaudRate),
    .UART_QUEUE     (UART_QUEUE)
  ) u_servant_uart (
    .i_wb_clk   (wb_clk),
    .wb_rst     (wb_rst),
    .i_cpu_adr  (o_wb_uart_adr),
    .i_cpu_dat  (o_wb_uart_dat),
    .i_cpu_we   (o_wb_uart_we),
    .i_cpu_cyc  (o_wb_uart_cyc),
    .o_cpu_rdt  (i_wb_uart_rdt),
    .o_cpu_ack  (i_wb_uart_ack),
    .output_buffer_out({19'b0, o_output_buffer_out}),  
  `ifdef RICEZIONE
    .i_rxd      (i_rxd),
  `endif
    .o_txd      (o_txd)
  );

  // ===================== External Memory Slave ========================
  `ifdef SERVANT_EXT_MEM
  parameter WIDTH_EXT_MEM = 8;
  parameter DEPTH_EXT_MEM = 255; 
  parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE"; 
  parameter INIT_FILE = "scripts/outputs/input_bram_servant.txt"; 
    servant_extMem #(
    .WIDTH_MEM       (WIDTH_EXT_MEM),
    .DEPTH_MEM       (DEPTH_EXT_MEM),
    .RAM_PERFORMANCE (RAM_PERFORMANCE),
    .INIT_FILE       (INIT_FILE)
    ) u_extmem (
    .i_wb_clk  (wb_clk),
    .i_wb_rst  (wb_rst),
    .i_cpu_adr (o_wb_extMem_adr),
    .i_cpu_dat (o_wb_extMem_dat),
    .i_cpu_we  (o_wb_extMem_we),
    .i_cpu_cyc (o_wb_extMem_cyc),
    .o_cpu_rdt (i_wb_extMem_rdt),
    .o_cpu_ack (i_wb_extMem_ack)
    );

`endif

/////////////////////////////////////////////////////////
//  ____  ____ ___           ____  _                   //
// / ___||  _ \_ _|         / ___|| | __ ___   _____   //
// \___ \| |_) | |   _____  \___ \| |/ _` \ \ / / _ \  //
//  ___) |  __/| |  |_____|  ___) | | (_| |\ V /  __/  //
// |____/|_|  |___|         |____/|_|\__,_| \_/ \___|  //
//                                                     //
/////////////////////////////////////////////////////////
wire wen_intmem1_spi;
wire [13:0] wr_addr_intmem1_spi;
wire [15:0] wr_data_intmem1_spi;
wire wen_intmem2_spi;
wire [13:0] wr_addr_intmem2_spi;
wire [15:0] wr_data_intmem2_spi;
wire wen_intmem3_spi;
wire [13:0] wr_addr_intmem3_spi;
wire [15:0] wr_data_intmem3_spi;
wire wen_intmem4_spi;
wire [13:0] wr_addr_intmem4_spi;
wire [15:0] wr_data_intmem4_spi;
wire wen_instruction_spi;
wire [13:0] wr_addr_instruction_spi;
wire [15:0] wr_data_instruction_spi;
wire wen_inputbuffer_spi;
wire [13:0] wr_addr_inputbuffer_spi;
wire [15:0] wr_data_inputbuffer_spi;
wire wen_delta_spi;
wire [9:0]  wr_addr_delta_spi;
wire [15:0] wr_data_delta_spi;
wire wen_ram_boot_spi;
wire [9:0]  wr_addr_ram_spi;
wire [31:0] wr_data_ram_spi;

servant_spi inst_servant_spi (
    // Wishbone interface
    .i_wb_clk       (wb_clk),
    .i_wb_rst       (wb_rst),
    .i_wb_spi_adr   (wb_spi_adr),
    .i_wb_spi_dat   (wb_spi_dat),
    .i_wb_spi_we    (wb_spi_we),
    .i_wb_spi_cyc   (wb_spi_cyc),
    .o_wb_spi_rdt   (wb_spi_rdt),
    .o_wb_spi_ack   (wb_spi_ack),
    // SPI slave interface
    .o_flash_sck    (o_flash_sck),
    .o_flash_ss     (o_flash_ss),
    .o_flash_mosi   (o_flash_mosi),
    .i_flash_miso   (i_flash_miso),
    // SPRAM Signals
    .wen_intmem1   (wen_intmem1_spi),
    .wr_addr_intmem1(wr_addr_intmem1_spi),
    .wr_data_intmem1(wr_data_intmem1_spi),
    .wen_intmem2   (wen_intmem2_spi),
    .wr_addr_intmem2(wr_addr_intmem2_spi),
    .wr_data_intmem2(wr_data_intmem2_spi),
    .wen_intmem3   (wen_intmem3_spi),
    .wr_addr_intmem3(wr_addr_intmem3_spi),
    .wr_data_intmem3(wr_data_intmem3_spi),
    .wen_intmem4   (wen_intmem4_spi),
    .wr_addr_intmem4(wr_addr_intmem4_spi),
    .wr_data_intmem4(wr_data_intmem4_spi),
    // delta mem
    .wen_delta      (wen_delta_spi),
    .wr_addr_delta  (wr_addr_delta_spi),
    .wr_data_delta  (wr_data_delta_spi),
    // CPU RAM / firmware boot
    .wen_ram_boot   (wen_ram_boot_spi),
    .wr_addr_ram    (wr_addr_ram_spi),
    .wr_data_ram    (wr_data_ram_spi),/*
    // Instruction signals
    .wen_instr (wen_instruction_spi),
    .wr_addr_instr (wr_addr_instruction_spi),
    .wr_data_instr (wr_data_instruction_spi),*/
    // Input buffer signals
    .wen_inputbuffer (wen_inputbuffer_spi),
    .wr_addr_inputbuffer (wr_addr_inputbuffer_spi),
    .wr_data_inputbuffer (wr_data_inputbuffer_spi)
);

servant_syntzulu inst_servant_syntzulu(
    .i_wb_clk               (wb_clk),
    .i_wb_rst               (wb_rst),
    .i_cpu_adr              (o_wb_acc_adr),
    .i_cpu_dat              (o_wb_acc_dat),
    .i_cpu_we               (o_wb_acc_we),
    .i_cpu_cyc              (o_wb_acc_cyc),
    .o_cpu_rdt              (i_wb_acc_rdt),
    .o_cpu_ack              (i_wb_acc_ack),

    .wen_intmem1_spi        (wen_intmem1_spi),
    .wr_addr_intmem1_spi    (wr_addr_intmem1_spi),
    .wr_data_intmem1_spi    (wr_data_intmem1_spi),

    .wen_intmem2_spi        (wen_intmem2_spi),
    .wr_addr_intmem2_spi    (wr_addr_intmem2_spi),
    .wr_data_intmem2_spi    (wr_data_intmem2_spi),

    .wen_intmem3_spi        (wen_intmem3_spi),
    .wr_addr_intmem3_spi    (wr_addr_intmem3_spi),
    .wr_data_intmem3_spi    (wr_data_intmem3_spi),

    .wen_intmem4_spi        (wen_intmem4_spi),
    .wr_addr_intmem4_spi    (wr_addr_intmem4_spi),
    .wr_data_intmem4_spi    (wr_data_intmem4_spi),

    .wen_delta_spi          (wen_delta_spi),
    .wr_addr_delta_spi      (wr_addr_delta_spi),
    .wr_data_delta_spi      (wr_data_delta_spi),
/*
    .wen_instr              (wen_instruction_spi),
    .wr_addr_instr          (wr_addr_instruction_spi),
    .wr_data_instr          (wr_data_instruction_spi),
*/
    .i_sample_mem_spi       (wr_data_inputbuffer_spi), 
    .i_en_encoding_slot     (wen_inputbuffer_spi),
    .i_wr_addr_inputbuffer  (wr_addr_inputbuffer_spi),
    .o_data_last_layer      (o_output_buffer_out)
  );
endmodule
