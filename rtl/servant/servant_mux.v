`include "rtl/servant/memory_mapping.v"

module servant_mux
  (
   input wire 	      i_clk,
   input wire 	      i_rst,
   
   // WB MASTER - RV
   input wire [31:0]  i_wb_cpu_adr,
   input wire [31:0]  i_wb_cpu_dat,
   input wire [3:0]   i_wb_cpu_sel,
   input wire 	      i_wb_cpu_we,
   input wire 	      i_wb_cpu_cyc,
   output reg [31:0] o_wb_cpu_rdt,
   output reg 	      o_wb_cpu_ack,

   // WB SLAVE - Data memory
   output wire [31:0] o_wb_mem_adr,
   output wire [31:0] o_wb_mem_dat,
   output wire [3:0]  o_wb_mem_sel,
   output wire 	      o_wb_mem_we,
   output wire 	      o_wb_mem_cyc,
   input wire [31:0]  i_wb_mem_rdt,

   // WB SLAVE - GPIO
   output wire [31:0]  o_wb_gpio_adr,
   output wire [31:0]  o_wb_gpio_dat,
   output wire 	       o_wb_gpio_we,
   output wire 	       o_wb_gpio_cyc,
   input wire 	[31:0] i_wb_gpio_rdt,
   
   // WB SLAVE - Timer
   output wire [31:0] o_wb_timer_adr,
   output wire [31:0] o_wb_timer_dat,
   output wire 	      o_wb_timer_we,
   output wire 	      o_wb_timer_cyc,
   input wire [31:0]  i_wb_timer_rdt,

   // WB SLAVE - UART 
   output wire [31:0] o_wb_uart_adr,
   output wire [31:0] o_wb_uart_dat,
   output wire 	      o_wb_uart_we,
   output wire 	      o_wb_uart_cyc,
   input wire [31:0]  i_wb_uart_rdt,
   input wire 	      i_wb_uart_ack,
   
   // WB SLAVE - Memory
   `ifdef SERVANT_EXT_MEM
   output wire [31:0] o_wb_extMem_adr,
   output wire [31:0] o_wb_extMem_dat,
   output wire            o_wb_extMem_we,
   output wire            o_wb_extMem_cyc,
   input wire [31:0]     i_wb_extMem_rdt,
   input wire            i_wb_extMem_ack,
   `endif
   // WB SLAVE - Accelerator
   output wire [31:0] o_wb_acc_adr,
   output wire [31:0] o_wb_acc_dat,
   output wire 	      o_wb_acc_we,
   output wire 	      o_wb_acc_cyc,
   input wire [31:0]  i_wb_acc_rdt,
   input wire 		  i_wb_acc_ack,

   // WB_SLAVE - SPI
   output wire [31:0] o_wb_spi_adr,
   output wire [31:0] o_wb_spi_dat,
   output wire 	      o_wb_spi_we,
   output wire 	      o_wb_spi_cyc,
   input wire [31:0]  i_wb_spi_rdt,
   input wire 	      i_wb_spi_ack,

   // WB_SLAVE - CLOCKs
   output wire [31:0] o_wb_clk_adr,
   output wire [31:0] o_wb_clk_dat,
   output wire 	      o_wb_clk_we,
   output wire 	      o_wb_clk_cyc,
   input wire [31:0]  i_wb_clk_rdt,
   input wire 	      i_wb_clk_ack
   );

   // master adr 3 MSBs select the slave
   
   // Slave response channel multiplexer
   wire [2:0] s = i_wb_cpu_adr[31-:3];
   
   always @(*) begin
      case (s) 
         `DMEM: begin
            o_wb_cpu_rdt = i_wb_mem_rdt;
         end
         `ACC: begin
            o_wb_cpu_rdt = i_wb_acc_rdt;
         end
         `TIMER: begin
            o_wb_cpu_rdt = i_wb_timer_rdt;
         end
         `GPIO: begin
            o_wb_cpu_rdt = i_wb_gpio_rdt;
         end 
         `UART: begin
            o_wb_cpu_rdt = i_wb_uart_rdt;
         end
         `ifdef SERVANT_EXT_MEM
         `BRAM: begin
            o_wb_cpu_rdt = i_wb_extMem_rdt;
         end
         `endif
         `SPI: begin
            o_wb_cpu_rdt = i_wb_spi_rdt;
         end
         `CLK: begin
            o_wb_cpu_rdt = i_wb_clk_rdt;
         end

         default: begin
            o_wb_cpu_rdt = 32'h0;
         end
      endcase
   end

   // Slave ack signal multiplexer
   always @(posedge i_clk) begin
      if(i_rst)
         o_wb_cpu_ack <= 0;
      else if(i_wb_cpu_cyc & !o_wb_cpu_ack)
         case (s) 
            `DMEM: begin
               o_wb_cpu_ack <= 1'b1;
            end
            `ACC: begin
               o_wb_cpu_ack <= i_wb_acc_ack;
            end
            `TIMER: begin
               o_wb_cpu_ack <= 1'b1;
            end
            `GPIO: begin
               o_wb_cpu_ack <= 1'b1;
            end 
            `UART: begin
               o_wb_cpu_ack <= 1'b1;
            end
            `ifdef SERVANT_EXT_MEM  
            `BRAM: begin
               o_wb_cpu_ack <= i_wb_extMem_ack;
            end
            `endif
            `SPI: begin
               o_wb_cpu_ack <= i_wb_spi_ack;
            end
            `CLK: begin
               o_wb_cpu_ack <= i_wb_clk_ack;
            end
            default: begin
               o_wb_cpu_ack <= 1'b0;
            end
         endcase
      else
         o_wb_cpu_ack <= 1'b0;
   end

   // Master bus propagation
   assign o_wb_mem_adr = i_wb_cpu_adr;
   assign o_wb_mem_dat = i_wb_cpu_dat; 
   assign o_wb_mem_sel = i_wb_cpu_sel;
   assign o_wb_mem_we  = i_wb_cpu_we;
   assign o_wb_mem_cyc = i_wb_cpu_cyc & (s == `DMEM);

   assign o_wb_acc_adr = i_wb_cpu_adr;
   assign o_wb_acc_dat = i_wb_cpu_dat;
   assign o_wb_acc_we  = i_wb_cpu_we;
   assign o_wb_acc_cyc = i_wb_cpu_cyc & (s == `ACC);

   assign o_wb_timer_adr = i_wb_cpu_adr;
   assign o_wb_timer_dat = i_wb_cpu_dat;
   assign o_wb_timer_we  = i_wb_cpu_we;
   assign o_wb_timer_cyc = i_wb_cpu_cyc & (s == `TIMER);

   assign o_wb_gpio_adr = i_wb_cpu_adr;
   assign o_wb_gpio_dat = i_wb_cpu_dat;
   assign o_wb_gpio_we  = i_wb_cpu_we;
   assign o_wb_gpio_cyc = i_wb_cpu_cyc & (s == `GPIO);

   assign o_wb_uart_adr = i_wb_cpu_adr;
   assign o_wb_uart_dat = i_wb_cpu_dat;
   assign o_wb_uart_we  = i_wb_cpu_we;
   assign o_wb_uart_cyc = i_wb_cpu_cyc & (s == `UART);
   `ifdef SERVANT_EXT_MEM
   assign o_wb_extMem_adr = i_wb_cpu_adr;
   assign o_wb_extMem_dat = i_wb_cpu_dat;
   assign o_wb_extMem_we  = i_wb_cpu_we;
   assign o_wb_extMem_cyc = i_wb_cpu_cyc & (s == `BRAM);
   `endif
   assign o_wb_spi_adr = i_wb_cpu_adr;
   assign o_wb_spi_dat = i_wb_cpu_dat;
   assign o_wb_spi_we  = i_wb_cpu_we;
   assign o_wb_spi_cyc = i_wb_cpu_cyc & (s == `SPI);

   assign o_wb_clk_adr = i_wb_cpu_adr;
   assign o_wb_clk_dat = i_wb_cpu_dat;
   assign o_wb_clk_we  = i_wb_cpu_we;
   assign o_wb_clk_cyc = i_wb_cpu_cyc & (s == `CLK);

endmodule
