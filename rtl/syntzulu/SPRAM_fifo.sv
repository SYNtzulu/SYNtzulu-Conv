(* keep, keep_hierarchy *)
module SPRAM_fifo #(
  parameter RAM_WIDTH = 4,                  // Specify RAM data width
  parameter RAM_DEPTH = 64,                  // Specify RAM depth (number of entries)
  parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE", // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
  parameter INIT_FILE = ""                       // Specify name/location of RAM initialization file if using one (leave blank if not)
)
(
  input [clogb2(RAM_DEPTH-1)-1:0] addra,  // Port A address bus, width determined from RAM_DEPTH
  input [clogb2(RAM_DEPTH-1)-1:0] addrb,  // Port B address bus, width determined from RAM_DEPTH
  input [RAM_WIDTH-1:0] dina,           // Port A RAM input data
  input clk,                           // Clock
  input wea,                            // Port A write enable
  input ena,                            // Port A RAM Enable, for additional power savings, disable port when not in use
  input enb,                            // Port B RAM Enable, for additional power savings, disable port when not in use
  `ifdef USEBRAM   
    input active_spram,
  `endif     
  input rst,                           // Port A and B output reset (does not affect memory contents)
  input regceb,                         // Port B output register enable
  
  output [RAM_WIDTH-1:0] doutb                   // Port B RAM output data
    );

`ifdef USEBRAM                // Condition check for macro 
    wire [13:0] addr;
    assign addr = active_spram?{{(14-clogb2(RAM_DEPTH-1)){1'b0}},addra}:{{(14-clogb2(RAM_DEPTH-1)){1'b0}},addrb};
    
    wire [RAM_WIDTH-1:0] doutb_int; 

    SB_SPRAM256KA spram
    (
      .ADDRESS(addr),
      .DATAIN(dina),
      .MASKWREN({wea, wea, wea, wea}),
      .WREN(wea && active_spram),
      .CHIPSELECT(1'b1),
      .CLOCK(clk),
      .STANDBY(1'b0),
      .SLEEP(1'b0),
      .POWEROFF(1'b1),
      .DATAOUT(doutb_int)
    );
    reg [RAM_WIDTH-1:0] doutb_reg;	
    always @(posedge clk)
    doutb_reg <= doutb_int;

    assign doutb = doutb_int;	

    initial $display("not defined");

`else
   
	BRAM_singlePort_readFirst #(
	  RAM_WIDTH,                  
	  RAM_DEPTH,                  
	  RAM_PERFORMANCE, 
	  INIT_FILE                      
	)
		bram
	(
	  addra,  
	  addrb, 
	  dina,   
	  clk,
	  wea,
	  ena,
	  enb,
	  rst, 
	  regceb, 
	  doutb 
		);
	initial $display("FIFO BRAM");

`endif 

  //  The following function calculates the address width based on specified RAM depth
  function integer clogb2;
    input integer depth;
      for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
  endfunction

endmodule
