module weight_memory_sram 
#(
  parameter RAM_WIDTH = 32,                         
  parameter RAM_DEPTH = 2048,                        
  parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE",  
  parameter INIT_FILE = "",
  parameter W_MEM_BYTES = 32768                         
)
(
  input [31:0] addra,  
  input [clogb2(RAM_DEPTH-1)-1:0] addrb,  
  input [RAM_WIDTH-1:0] dina,          
  input clk,                         
  input wea,                           
  input ena,                            
  input enb,                            
  input rst,                          
  input regceb,                         
  
  output reg [RAM_WIDTH-1:0] doutb                   
);

      
      wire [clogb2(RAM_DEPTH-1)-1:0] addr;
      assign addr  = ena ? addra : addrb;

      wire [RAM_WIDTH-1:0] ram_dout;
      always@(posedge clk) begin
        doutb <= ram_dout;        
      end
      	

      // Simulation here (iverilog): tc_sram_fake. For synthesis/migration
      // replace "tc_sram_fake" with "tc_sram" (same interface).
      tc_sram_fake #(
        .NumWords  ( RAM_DEPTH ),
        .DataWidth ( RAM_WIDTH ),
        .ByteWidth ( 32'd8 ),
        .NumPorts  ( 32'd1 ),
        .Latency   ( 32'd1 )
      ) wmem_1 (
        .clk_i    ( clk ),
        .rst_ni   ( ~rst ),
        .req_i    ( 1'b1 ),
        .we_i     ( ena  ),
        .addr_i   ( addr ),
        .wdata_i  ( dina),
        .be_i     ( 4'hF ),
        .rdata_o  ( ram_dout )
      );
	

  //  The following function calculates the address width based on specified RAM depth
  function integer clogb2;
    input integer depth;
      for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
  endfunction

endmodule
