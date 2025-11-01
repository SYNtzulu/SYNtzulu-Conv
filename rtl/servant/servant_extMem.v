`timescale 1 ns / 1 ps

module servant_extMem #(
    parameter WIDTH_MEM = 8,
    parameter DEPTH_MEM = 65535,
    parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE", // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    parameter INIT_FILE = "" // Specify name/location of RAM initialization file if using one (leave blank if not)
)(
    // Wishbone
    input  wire        i_wb_clk,
    input  wire        i_wb_rst,
    input  wire [31:0] i_cpu_adr,   
    input  wire [31:0] i_cpu_dat,
    input  wire        i_cpu_we,
    input  wire        i_cpu_cyc,
    output reg  [31:0] o_cpu_rdt,
    output wire         o_cpu_ack
    
);
    reg [clogb2(DEPTH_MEM-1)-1:0] rd_addr; 
    reg [clogb2(DEPTH_MEM-1)-1:0] wr_addr;
    reg [WIDTH_MEM-1:0] data_in; 
    wire [WIDTH_MEM-1:0] dout; 
    reg wr_en; 
    reg rd_en; 


    always @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            wr_en <= 0; rd_en <= 0;
        end 
        else begin
            if (i_cpu_cyc&i_cpu_we) begin 
                wr_addr <= i_cpu_adr[clogb2(DEPTH_MEM-1)+1: 2]; // Extract address bits
                wr_en <= 1'b1; // Enable write
                rd_en <= 1'b0; // Disable read
                data_in <= i_cpu_dat[WIDTH_MEM-1:0]; // Write data to memory
            end 
            else if (i_cpu_cyc&(~i_cpu_we)) begin // Read operation
                wr_en <= 1'b0; // Disable write
                rd_en <= 1'b1; // Enable read
                rd_addr <= i_cpu_adr[clogb2(DEPTH_MEM-1)+1 :2]; // Extract address bits for read
                
            end
            else begin
                wr_en <= 1'b0; // Disable write
                rd_en <= 1'b0; // Disable read
            end
            o_cpu_rdt <= {24'h0, dout}; // Read data from memory
        end
    end


    // Instance of the memory (in this case, a single-port BRAM):
    (* keep_hierarchy *)    BRAM_singlePort_readFirst
    #(
    .RAM_WIDTH(WIDTH_MEM), // Specify RAM data width
    .RAM_DEPTH(DEPTH_MEM), // Specify RAM depth (number of entries)
    .RAM_PERFORMANCE(RAM_PERFORMANCE), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    .INIT_FILE(INIT_FILE) // Specify name/location of RAM initialization file if using one (leave blank if not)
    )
    inst_wishbone_mem
    (
        .addra(wr_addr), 
        .addrb(rd_addr), 
        .dina(data_in), 
        .clk(i_wb_clk),
        .wea(wr_en),
        .ena(wr_en), 
        .enb(rd_en), 
        .rst(i_wb_rst), 
        .regceb(1'b1), 
        .doutb(dout) 
    ); 
    
    // Ack management
    reg [2:0] ack_mem;
    always @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            ack_mem[0] <= 1'b0;
            ack_mem[1] <= 1'b0;
            ack_mem[2] <= 1'b0;
        end 
        else if (i_cpu_cyc)begin
            ack_mem[0] <= 1'b1;
            ack_mem[1] <= ack_mem[0];
            ack_mem[2] <= ack_mem[1];
        end
        else begin
            ack_mem[0] <= 1'b0;
            ack_mem[1] <= 1'b0;
            ack_mem[2] <= 1'b0;
        end
    end
    assign o_cpu_ack = ack_mem[2]; 


	function integer clogb2;
	  input integer depth;
		for (clogb2=0; depth>0; clogb2=clogb2+1)
		  depth = depth >> 1;
    endfunction
endmodule