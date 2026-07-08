module priority_encoder #(
    parameter MAX_KERNEL = 3
)( //122LUT
	input clk,
	input en,
	input rst,
	input conv_enable,
	input pooling_enable,
	input [MAX_KERNEL*MAX_KERNEL-1:0] kernel_in,
	input input_feature_ready,
	input weights_buffer_ready,
	output reg conv_en,
	output wire [15:0] spike_address,
    output PE_finish_pulse,
	output pooling_spike,
	output valid_pooling_spike,
	output last_spike
);  	
	// Mapping of the 3x3 matrix into columns
	wire [2:0] kernel_col0 = {kernel[6], kernel[3], kernel[0]};
	wire [2:0] kernel_col1 = {kernel[7], kernel[4], kernel[1]};
	wire [2:0] kernel_col2 = {kernel[8], kernel[5], kernel[2]};

	wire [3:0] spike_address_0; //address of spike 0
	wire [3:0] spike_address_1; //address of spike 1
	wire [3:0] spike_address_2; //address of spike 2
	wire [3:0] spike_address_3; //address of spike 3

	assign spike_address = (conv_enable) ? {spike_address_3, spike_address_2, spike_address_1, spike_address_0} : 16'hBBBB; //final address composition
	
	wire [1:0] C0, C1, C2; //indicates how many spikes there are in each column
	wire [7:0] column_sel; //indicates the columns (2 bits per column) where the active spikes are
	wire [2:0] R_PE0, R_PE1, R_PE2, R_PE3; //are the input rows to the encoder (one per encoder)
	
	wire [1:0] spike_address_row_PE3, spike_address_row_PE2, spike_address_row_PE1, spike_address_row_PE0;
	
	reg[8:0] kernel;
	column_selection column(kernel_col2, kernel_col1, kernel_col0, C0, C1, C2, column_sel); //25LUT
	row_selection row(kernel_col0,kernel_col1,kernel_col2, column_sel, R_PE0, R_PE1, R_PE2, R_PE3); //24LUT
	encoder_system encoder(column_sel, R_PE0, R_PE1, R_PE2, R_PE3,  C0, C1, C2, spike_address_0,spike_address_1,spike_address_2,spike_address_3); //37LUT

	always @(posedge clk)
		if (rst)
			kernel <= 0;
		else if (conv_enable) begin
			if(en) begin
				kernel<=kernel_in;
			end
			else
				begin 
					kernel[spike_address_0]<=0;
					kernel[spike_address_1]<=0;
					kernel[spike_address_2]<=0;
					kernel[spike_address_3]<=0;
				end
		end

	reg en_d;
	always @(posedge clk)
		if(rst)
			en_d <= 0;
		else
			en_d <= en;

	wire [3:0] active_spike;
	assign active_spike = C0+C1+C2;
	wire PE_finish;
	assign PE_finish = pooling_enable ? en_d : (conv_enable && PE_active && kernel==0) ? 1 : 0; 

	assign last_spike = active_spike <= 4 ? 1 : 0;

	wire active_spike_maior_zero = active_spike > 0;

	assign pooling_spike = (pooling_enable && PE_active) ? active_spike_maior_zero : 0;
	assign valid_pooling_spike = en_d;

	always @(posedge clk) begin
		if (rst)
			conv_en <= 0;
		else if (conv_enable) begin
			if(en)
				conv_en <= 1;
			else if (last_spike)
				conv_en <= 0;
		end	else
				conv_en <= 0;
		
	end

	reg PE_active;
	always @(posedge clk) begin
		if (rst)
			PE_active <= 0;
		else if (conv_enable) begin
			if(en)
				PE_active <= 1;
			else if (kernel==0)
				PE_active <= 0;
		end	else
				PE_active <= 0;
		
	end

	reg PE_finish_d;
	always @(posedge clk) begin
		if (rst)
			PE_finish_d <= 0;
		else if (conv_enable) begin
			/*if(en)
				PE_finish_d <= 0;
			else*/
				PE_finish_d <= PE_finish;
		end	else
				PE_finish_d <= 0;
		
	end

	assign PE_finish_pulse = PE_finish && !PE_finish_d; //Generates a pulse when PE_finish transitions from 0 to 1\

	function integer clogb2(input integer value);
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clogb2 = i;
        end
    endfunction

endmodule    

module column_selection(
	input [2:0] kernel_col0, kernel_col1, kernel_col2,
	output [1:0] C0_in, C1_in, C2_in,
	output reg[7:0] sel  //mux selector for controlling the input column to PE
);
	integer i;
	//wire [1:0] counts [3:0];
	reg [1:0] C0,C1,C2;
	assign C2_in = (kernel_col0[0] + kernel_col0[1] + kernel_col0[2]);
	assign C1_in = (kernel_col1[0] + kernel_col1[1] + kernel_col1[2]);
	assign C0_in = (kernel_col2[0] + kernel_col2[1] + kernel_col2[2]);
	
	always @(*) 
		begin
		// Initialize the counters
		{C0, C1, C2} = {C0_in, C1_in, C2_in};
		sel = 8'b11111111; // Default to 2'b11

		casex ({C0 > 0, C1 > 0, C2 > 0})
		3'b1xx: begin sel[1:0] = 2'b00; C0 = C0 - 1; end
		3'b01x: begin sel[1:0] = 2'b01; C1 = C1 - 1; end
		3'b001: begin sel[1:0] = 2'b10; C2 = C2 - 1; end
		endcase
		casex ({C0 > 0, C1 > 0, C2 > 0})
		3'b1xx: begin sel[3:2] = 2'b00; C0 = C0 - 1; end
		3'b01x: begin sel[3:2] = 2'b01; C1 = C1 - 1; end
		3'b001: begin sel[3:2] = 2'b10; C2 = C2 - 1; end
		endcase
		casex ({C0 > 0, C1 > 0, C2 > 0})
		3'b1xx: begin sel[5:4] = 2'b00; C0 = C0 - 1; end
		3'b01x: begin sel[5:4] = 2'b01; C1 = C1 - 1; end
		3'b001: begin sel[5:4] = 2'b10; C2 = C2 - 1; end
		endcase
		casex ({C0 > 0, C1 > 0, C2 > 0})
		3'b1xx: begin sel[7:6] = 2'b00; C0 = C0 - 1; end
		3'b01x: begin sel[7:6] = 2'b01; C1 = C1 - 1; end
		3'b001: begin sel[7:6] = 2'b10; C2 = C2 - 1; end
        endcase
	end
endmodule

module row_selection(
	input [2:0] kernel_col0,
	input [2:0] kernel_col1,
	input [2:0] kernel_col2,
	input [7:0] sel,
	output [2:0] R_PE0,R_PE1,R_PE2,R_PE3
);	
	assign R_PE0 = (sel[1:0] == 2'b00) ? kernel_col0 :
	             (sel[1:0] == 2'b01) ? kernel_col1 :
	             (sel[1:0] == 2'b10) ? kernel_col2 : 
	             3'b000;  // Default case
	assign R_PE1 = (sel[3:2] == 2'b00) ? kernel_col0 :
	             (sel[3:2] == 2'b01) ? kernel_col1 :
	             (sel[3:2] == 2'b10) ? kernel_col2 : 
	             3'b000;  // Default case
	assign R_PE2 = (sel[5:4] == 2'b00) ? kernel_col0 :
	             (sel[5:4] == 2'b01) ? kernel_col1 :
	             (sel[5:4] == 2'b10) ? kernel_col2 : 
	             3'b000;  // Default case
	assign R_PE3 = (sel[7:6] == 2'b00) ? kernel_col0 :
	             (sel[7:6] == 2'b01) ? kernel_col1 :
	             (sel[7:6] == 2'b10) ? kernel_col2 : 
	             3'b000;  // Default case
endmodule

module encoder_system(
    input  [7:0] sel,
    input  [2:0] R_PE0, R_PE1, R_PE2, R_PE3,
    input  [1:0] C0, C1, C2,
    output [3:0] spike_address_PE3, spike_address_PE2, spike_address_PE1, spike_address_PE0
);

    // Rank computation
    wire [1:0] rank0;
    wire [1:0] rank1;
    wire [1:0] rank2;
    wire [1:0] rank3;

    assign rank0 = 2'd0;
    assign rank1 = (sel[3:2] == sel[1:0]) ? 2'd1 : 2'd0;
    assign rank2 = ((sel[5:4] == sel[1:0]) ? 2'd1 : 2'd0) +
                   ((sel[5:4] == sel[3:2]) ? 2'd1 : 2'd0);
    assign rank3 = ((sel[7:6] == sel[1:0]) ? 2'd1 : 2'd0) +
                   ((sel[7:6] == sel[3:2]) ? 2'd1 : 2'd0) +
                   ((sel[7:6] == sel[5:4]) ? 2'd1 : 2'd0);

    function [1:0] first_one;
        input [2:0] rank;
        begin
            if (rank[0]) first_one = 2'd0;
            else if (rank[1]) first_one = 2'd1;
            else if (rank[2]) first_one = 2'd2;
            else first_one = 2'd3; // none
        end
    endfunction

    function [2:0] clear_first;
        input [2:0] rank;
        begin
            if (rank[0]) clear_first = rank & 3'b110;
            else if (rank[1]) clear_first = rank & 3'b101;
            else if (rank[2]) clear_first = rank & 3'b011;
            else clear_first = rank;
        end
    endfunction

    function [1:0] choose_spike;
        input [2:0] rank;
        input [1:0] k;
        reg [2:0] t;
        begin
            t = rank;
            if (k == 2'd0) begin
                choose_spike = first_one(t);
            end else if (k == 2'd1) begin
                t = clear_first(t);
                choose_spike = first_one(t);
            end else begin
                t = clear_first(t);
                t = clear_first(t);
                choose_spike = first_one(t);
            end
        end
    endfunction

    wire [1:0] spike_address_row_PE0 = choose_spike(R_PE0, rank0);
    wire [1:0] spike_address_row_PE1 = choose_spike(R_PE1, rank1);
    wire [1:0] spike_address_row_PE2 = choose_spike(R_PE2, rank2);
    wire [1:0] spike_address_row_PE3 = choose_spike(R_PE3, rank3);

    // Address composition (row,col)
    wire [3:0] temp_PE0 = {spike_address_row_PE0, sel[1:0]};
    wire [3:0] temp_PE1 = {spike_address_row_PE1, sel[3:2]};
    wire [3:0] temp_PE2 = {spike_address_row_PE2, sel[5:4]};
    wire [3:0] temp_PE3 = {spike_address_row_PE3, sel[7:6]};

    function [3:0] correct_address;
        input [3:0] addr;
        begin
            case (addr)
                4'b0100: correct_address = 4'b0011; // 4 → 3
                4'b0101: correct_address = 4'b0100; // 5 → 4
                4'b0110: correct_address = 4'b0101; // 6 → 5
                4'b1000: correct_address = 4'b0110; // 8 → 6
                4'b1001: correct_address = 4'b0111; // 9 → 7
                4'b1010: correct_address = 4'b1000; // 10 → 8
				4'b1111: correct_address = 4'b1011; // F → B
                default: correct_address = addr;
            endcase
        end
    endfunction

	assign spike_address_PE0 = correct_address(temp_PE0);
    assign spike_address_PE1 = correct_address(temp_PE1);
    assign spike_address_PE2 = correct_address(temp_PE2);
    assign spike_address_PE3 = correct_address(temp_PE3);

endmodule
/*
module encoder_system_old(
	input [7:0] sel,
	input  wire [2:0] R_PE0,R_PE1,R_PE2,R_PE3,
	input wire [1:0] C0, C1, C2,
	output [3:0] spike_address_PE3, spike_address_PE2, spike_address_PE1, spike_address_PE0
);  
	wire [1:0] spike_address_row_PE3, spike_address_row_PE2, spike_address_row_PE1, spike_address_row_PE0; //final outputs with the address of the row where the spike is in the selected column
	wire [1:0] spike_address_row_PE1_1, spike_address_row_PE1_2, spike_address_row_PE2_1, spike_address_row_PE2_2, spike_address_row_PE2_3, spike_address_row_PE3_1, spike_address_row_PE3_2, spike_address_row_PE3_3; //intermediate outputs
	
	wire sel_PE1;
	wire [1:0] sel_PE2, sel_PE3; //are the selectors of the output mux from each PE
	
	//PE0
	assign spike_address_row_PE0 = (R_PE0[0] == 1) ? 0 : (R_PE0[1] == 1) ? 1 : 2;
	
	//PE1
	assign spike_address_row_PE1_1 = (R_PE1[0] == 1) ? 0 : (R_PE1[1] == 1) ? 1 : 2;
	assign spike_address_row_PE1_2 = (R_PE1[0] == 1 && R_PE1[1] == 1) ? 1 : 2;
	assign sel_PE1 = ((C0==1)|((C0==0)&(C1==1))) ? 0 : 1;
	assign spike_address_row_PE1 = (sel_PE1 == 0) ? spike_address_row_PE1_1 : spike_address_row_PE1_2;

	//PE2
	assign spike_address_row_PE2_1 = (R_PE2[0] == 1) ? 0 : (R_PE2[1] == 1) ? 1 : 2;
	assign spike_address_row_PE2_2 = (R_PE2[1] == 1) ? 1 : 2;
	assign spike_address_row_PE2_3 = 2;
	assign sel_PE2 = (((C0==2)&(C1!=0))|((C0==2)&(C1==0)&(C2!=0))|((C0==1)&(C1==1)&(C2!=0))|((C0==0)&(C1==2)&(C2!=0))) ? 0 : 
			 (((C0==1)&(C1>1))|((C0==1)&(C1==0)&(C2>1))|((C0==0)&(C1==1)&(C2>1))) ? 1 : 2;
	assign spike_address_row_PE2 = (sel_PE2 == 0) ? spike_address_row_PE2_1 : 
					(sel_PE2 == 1) ? spike_address_row_PE2_2 : spike_address_row_PE2_3; 
	
	//PE3
	assign spike_address_row_PE3_1 = (R_PE3[0] == 1) ? 0 : (R_PE3[1] == 1) ? 1 : 2;
	assign spike_address_row_PE3_2 = (R_PE3[1] == 1) ? 1 : 2;
	assign spike_address_row_PE3_3=2;	
	assign sel_PE3 = (((C0==3)&(C1!=0))|((C0==3)&(C1==0)&(C2!=0))|((C0==2)&(C1==1)&(C2!=0))|((C0==1)&(C1==2)&(C2!=0))) ? 0 : 
			 (((C0==2)&(C1>1))|((C0==2)&(C1==0)&(C2>1))|((C0==1)&(C1==1)&(C2>1))) ? 1 : 2;
	assign spike_address_row_PE3 = (sel_PE3 == 0) ? spike_address_row_PE3_1 : 
					(sel_PE3 == 1) ? spike_address_row_PE3_2 : spike_address_row_PE3_3; 
	
	//Spike address composition
	function [3:0] correct_address;
        input [3:0] addr;
        begin
            case (addr)
                4'b0100: correct_address = 4'b0011;  // 4 → 3
                4'b0101: correct_address = 4'b0100;  // 5 → 4
                4'b0110: correct_address = 4'b0101;  // 6 → 5
                4'b1000: correct_address = 4'b0110;  // 8 → 6
                4'b1001: correct_address = 4'b0111;  // 9 → 7
                4'b1010: correct_address = 4'b1000;  // 10 → 8
                default: correct_address = addr;  // Keep the others
            endcase
        end
	endfunction

	wire [3:0] temp_PE0, temp_PE1, temp_PE2, temp_PE3;

	assign temp_PE0 = {spike_address_row_PE0, sel[1:0]};
	assign temp_PE1 = {spike_address_row_PE1, sel[3:2]};
	assign temp_PE2 = {spike_address_row_PE2, sel[5:4]};
	assign temp_PE3 = {spike_address_row_PE3, sel[7:6]};

	assign spike_address_PE0 = correct_address(temp_PE0);
	assign spike_address_PE1 = correct_address(temp_PE1);
	assign spike_address_PE2 = correct_address(temp_PE2);
	assign spike_address_PE3 = correct_address(temp_PE3);



endmodule
*/
