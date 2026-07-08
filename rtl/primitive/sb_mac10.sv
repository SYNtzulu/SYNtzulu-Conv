(* blackbox *)
module SB_MAC (
	input CLK, CE,
	input [15:0] C, A, B, D,
	input AHOLD, BHOLD, CHOLD, DHOLD,
	input IRSTTOP, IRSTBOT,
	input ORSTTOP, ORSTBOT,
	input OLOADTOP, OLOADBOT,
	input ADDSUBTOP, ADDSUBBOT,
	input OHOLDTOP, OHOLDBOT,
	input CI, ACCUMCI, SIGNEXTIN,
	output [31:0] O,
	output CO, ACCUMCO, SIGNEXTOUT
);
endmodule