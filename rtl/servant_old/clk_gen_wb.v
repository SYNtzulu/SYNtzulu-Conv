`default_nettype none 

module clk_gen_wb #( 
	parameter HFOSC = "0b01")	 
( 
	input i_clk, i_rst, 
	output o_clk, o_sclk, o_rst, 
	input timer_irq, 
	input [31:0] i_wb_clkgen_adr, 
    input [31:0] i_wb_clkgen_dat, 
    input        i_wb_clkgen_we, 
    input        i_wb_clkgen_cyc, 
    output reg [31:0] o_wb_clkgen_rdt, 
    output reg       o_wb_clkgen_ack 
	); 



// RESET LOGIC 
localparam RESET_LENGTH = 12; 
reg [RESET_LENGTH-1:0] rst_reg = 0; 
always @(posedge o_clk) 
    rst_reg <= {rst_reg[RESET_LENGTH-2:0],1'b1}; 
assign o_rst = ~rst_reg[RESET_LENGTH-1]; 

// CLOCK GENERATOR 
reg n_gate_serv;
generate 
	begin 
		SB_HFOSC #(.CLKHF_DIV(HFOSC)) 
			hfosc 
			( 
				.CLKHFEN(1'b1), 
				.CLKHFPU(1'b1), 
				.CLKHF(o_clk) 
			); 	 

		SB_LFOSC  u_lf_osc(.CLKLFPU(1'b1), .CLKLFEN(1'b1), .CLKLF(o_sclk)); 
	end 
endgenerate 

	reg gate_serv_armed;
	// initial begin
	// gate_serv = 1'b0;
	// end
	always @(posedge o_clk, posedge timer_irq) begin
		if(timer_irq)
			n_gate_serv <= 1'b1;
		else if (o_rst)
			n_gate_serv <= 1'b1;
		else if(gate_serv_armed) 
				n_gate_serv <= 1'b0;
	end

	always @(posedge o_clk) begin
		gate_serv_armed = 0; 
		if (i_wb_clkgen_cyc) begin
			o_wb_clkgen_rdt <= {31'b0, gate_serv_armed };
			if (i_wb_clkgen_we) begin	
					gate_serv_armed = i_wb_clkgen_dat[0];
			end
	end
	end

	always @(posedge o_clk)
		if (o_rst)
			o_wb_clkgen_ack <= 0;
		else 
			o_wb_clkgen_ack <= i_wb_clkgen_cyc;

endmodule
 