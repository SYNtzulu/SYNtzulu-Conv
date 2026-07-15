
// ihp_ram: 1024 x 32-bit CPU RAM built from TWO 1024x16 IHP macros side by side.
//
// Was a single RM_IHPSG13_1P_1024x64: the CPU word is only 32 bit (we[3:0] =
// 4 byte-enables), so the upper 32 bit of the 64-bit macro were never written
// -> half the macro (32 Kbit) wasted. Two 1024x16 macros give exactly 1024x32.
//
//   ram_lo -> bits [15:0]  (bytes 0,1 -> we[0],we[1])
//   ram_hi -> bits [31:16] (bytes 2,3 -> we[2],we[3])
//
// INIT: the firmware exe.hex is 32-bit/word, so it is split into two 16-bit
// hex files (firmware/exe_lo.hex = bits[15:0], firmware/exe_hi.hex = bits[31:16])
// and each half inits its bank. See firmware/Makefile (split-hex step).
//
// Ports are unchanged (dina/dout stay [63:0]; only [31:0] are meaningful).

module ihp_ram # (
	parameter memfile    = "",                     // kept for compatibility (unused for init)
	parameter memfile_lo = "firmware/exe_lo.hex",  // bits [15:0]
	parameter memfile_hi = "firmware/exe_hi.hex"   // bits [31:16]
)
(
	input wire clk,
	input wire [3:0] we,
	input wire [9:0] addr,
	input wire [63:0] dina,
	output wire [63:0] dout,
	input wire enb_debug

);

	wire wea = (|we);
	reg [7:0] B1, B2, B3, B4;

	//bitmask per-byte (1 = scrivi), stessa logica di prima
	always @(posedge clk) begin
	    if (we[0]) B1 = 8'hFF; else B1 = 8'h00;
	    if (we[1]) B2 = 8'hFF; else B2 = 8'h00;
	    if (we[2]) B3 = 8'hFF; else B3 = 8'h00;
	    if (we[3]) B4 = 8'hFF; else B4 = 8'h00;
	end

	// mask a 16 bit per ciascun banco
	wire [15:0] BM_lo = {B2, B1};   // bytes 1,0 -> [15:0]
	wire [15:0] BM_hi = {B4, B3};   // bytes 3,2 -> [31:16]

	wire [15:0] dout_lo, dout_hi;
	assign dout = {32'b0, dout_hi, dout_lo};

	// banco basso: bit [15:0]
	RM_IHPSG13_1P_1024x16_c2_bm_bist #(.INIT_FILE(memfile_lo)) ram_lo (
	    .A_CLK(clk),
	    .A_MEN(enb_debug),
	    .A_WEN(wea),
	    .A_REN(enb_debug),
	    .A_ADDR(addr),
	    .A_DIN(dina[15:0]),
	    .A_DLY(1'b0),
	    .A_DOUT(dout_lo),
	    .A_BM(BM_lo),
	    .A_BIST_CLK(1'b0),
	    .A_BIST_EN(1'b0),
	    .A_BIST_MEN(1'b0),
	    .A_BIST_WEN(1'b0),
	    .A_BIST_REN(1'b0),
	    .A_BIST_ADDR(10'b0),
	    .A_BIST_DIN(16'b0),
	    .A_BIST_BM(16'b0)
	);

	// banco alto: bit [31:16]
	RM_IHPSG13_1P_1024x16_c2_bm_bist #(.INIT_FILE(memfile_hi)) ram_hi (
	    .A_CLK(clk),
	    .A_MEN(enb_debug),
	    .A_WEN(wea),
	    .A_REN(enb_debug),
	    .A_ADDR(addr),
	    .A_DIN(dina[31:16]),
	    .A_DLY(1'b0),
	    .A_DOUT(dout_hi),
	    .A_BM(BM_hi),
	    .A_BIST_CLK(1'b0),
	    .A_BIST_EN(1'b0),
	    .A_BIST_MEN(1'b0),
	    .A_BIST_WEN(1'b0),
	    .A_BIST_REN(1'b0),
	    .A_BIST_ADDR(10'b0),
	    .A_BIST_DIN(16'b0),
	    .A_BIST_BM(16'b0)
	);

endmodule
