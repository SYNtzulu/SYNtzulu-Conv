module priority_encoder #(
    parameter MAX_KERNEL = 3
)( //122LUT
	input clk,
	input en, // load new 3x3 receptive field
	input rst,
	input conv_enable, // the layer under execution is either convolutional or pooling
	input pooling_enable, // 1 if the layer is pooling
	input [MAX_KERNEL*MAX_KERNEL-1:0] kernel_in, // input 3x3 receptive field
	input input_feature_finish_d, // IF dispatch completed
	input row_finish,	// row dispatch end
	output reg conv_en, // 1 during IF computation
	output wire [15:0] spike_address, // receptive field active pointers (output of the module)
    output PE_finish,				  // receptive field processed, 1 when the remaining spike are <= 4
	output pooling_spike,			  // or reduce of the receptive field, used by max pooling layer
	output valid_pooling_spike,		  // pooling valid 
	output last_spike				  // it a sort of raw version of PE_finish used by the synaptic current computation module. Maybe it can be substituted with PE_finish
);  	
	// Mappatura della matrice 3x3 in colonne
	wire [2:0] kernel_col0 = {kernel[6], kernel[3], kernel[0]};
	wire [2:0] kernel_col1 = {kernel[7], kernel[4], kernel[1]};
	wire [2:0] kernel_col2 = {kernel[8], kernel[5], kernel[2]};

	wire [3:0] spike_address_0; //indirizzo lineare dello spike 0
	wire [3:0] spike_address_1; //indirizzo lineare dello spike 1
	wire [3:0] spike_address_2; //indirizzo lineare dello spike 2
	wire [3:0] spike_address_3; //indirizzo lineare dello spike 3

	assign spike_address = (conv_en) ? {spike_address_3, spike_address_2, spike_address_1, spike_address_0} : 16'hBBBB; //composizione indirizzo finale
	
	wire [1:0] C0, C1, C2; //indica quanti spike ci sono in ogni colonna
	wire [7:0] column_sel; //indica le colonne (2bit a colonna) dove ci sono gli spike attivi
	wire [2:0] R_PE0, R_PE1, R_PE2, R_PE3; // sono le colonne in ingresso all'encoder (uno per encoder)
		
	reg[8:0] kernel;
	column_selection column(kernel_col2, kernel_col1, kernel_col0, C0, C1, C2, column_sel); //25LUT
	row_selection row(kernel_col0,kernel_col1,kernel_col2, column_sel, R_PE0, R_PE1, R_PE2, R_PE3); //24LUT
	encoder_system encoder(column_sel, R_PE0, R_PE1, R_PE2, R_PE3,  C0, C1, C2, spike_address_0,spike_address_1,spike_address_2,spike_address_3); //37LUT

	// once four spikes are dispatched, they are reset from the 3x3 FF array 
	// to permit to the system to select the next four spikes when present
	always @(posedge clk or posedge rst)
		if (rst)
			kernel <= 0;
		else begin
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
	always @(posedge clk or posedge rst)
		if(rst)
			en_d <= 0;
		else
			en_d <= en;

	reg en_dd;
	always @(posedge clk or posedge rst)
		if(rst)
			en_dd <= 0;
		else
			en_dd <= en_d;
	
	reg row_finish_d;
	always @(posedge clk or posedge rst)
		if(rst)
			row_finish_d <= 0;
		else
			row_finish_d <= row_finish;

	reg row_finish_dd;
	always @(posedge clk or posedge rst)
		if(rst)
			row_finish_dd <= 0;
		else
			row_finish_dd <= row_finish_d;

	// overall number of active spikes to know when 
	// we are dispathing the last group of spikes
	wire [3:0] active_spike;
	assign active_spike = C0+C1+C2;
	assign last_spike = active_spike <= 4 ? 1 : 0;
	
	wire kernel_zero = ~(|active_spike); // pooling output
		
	assign PE_finish = pooling_enable ? (en_d && !row_finish_d) : (conv_enable && PE_active && last_spike); 

	reg last_spike_d;
	always @(posedge clk or posedge rst)
		if(rst)
			last_spike_d <= 0;
		else
			last_spike_d <= last_spike;

	assign pooling_spike = (pooling_enable && PE_active) ? ~kernel_zero : 0;
	assign valid_pooling_spike = en_dd && !row_finish_dd;

	// active when 2 c.c. are needed to consume the current receptive field
	// used to break the path from PE_active to ... or for critical path
	// or to break a combinational loop
	wire last_two_spike = active_spike <= 8 ? 1 : 0;
	reg PE_active;
	always @(posedge clk or posedge rst) begin
		if (rst)
			PE_active <= 0;
		else begin
			PE_active <= en || (last_two_spike && !last_spike);
		end	
	end

	always @(posedge clk)
		if(en_d && !en_dd)
			conv_en <= 1;
		else if(input_feature_finish_d)
			conv_en <= 0;

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

/*
Depending on how many spikes are active in each column, it is decided how many read ports
are assigned to each column, e.g. if the first column has 2 active spikes, both rd port 1 
and rd port 2 are assigned to it. To assign a rd port, sel0, sel1, sel2, and sel3 are used.
selx signals are 2 bit signals used to select 1 out of 3 columns in a layer of 4 muxes.
*/

module column_selection(
	input [2:0] kernel_col0, kernel_col1, kernel_col2,
	output [1:0] C0_in, C1_in, C2_in,
	output reg[7:0] sel  //selettore mux per controllo colonna in ingresso a PE
);
	integer i;
	//wire [1:0] counts [3:0];
	reg [1:0] C0,C1,C2;
	assign C2_in = (kernel_col0[0] + kernel_col0[1] + kernel_col0[2]);
	assign C1_in = (kernel_col1[0] + kernel_col1[1] + kernel_col1[2]);
	assign C0_in = (kernel_col2[0] + kernel_col2[1] + kernel_col2[2]);
	
	always @(*) 
		begin
		// Inizializzo i contatori
		{C0, C1, C2} = {C0_in, C1_in, C2_in};
		sel = 8'b11111111; // Default a 2'b11

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


// This is the layer of 4 multiplexers that decide to which column
// is assigned each of the 4 read ports
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

/*

*/

module encoder_system(
    input  [7:0] sel,
    input  [2:0] R_PE0, R_PE1, R_PE2, R_PE3,
    input  [1:0] C0, C1, C2,
    output [3:0] spike_address_PE3, spike_address_PE2, spike_address_PE1, spike_address_PE0
);

    // Calcolo rank
    wire [1:0] rank0;
    wire [1:0] rank1;
    wire [1:0] rank2;
    wire [1:0] rank3;

	// rank is the name of the selectors of the 2nd layer of multiplexers 
    assign rank0 = 2'd0;
    assign rank1 = (sel[3:2] == sel[1:0]) ? 2'd1 : 2'd0;
    assign rank2 = ((sel[5:4] == sel[1:0]) ? 2'd1 : 2'd0) +
                   ((sel[5:4] == sel[3:2]) ? 2'd1 : 2'd0);
    assign rank3 = ((sel[7:6] == sel[1:0]) ? 2'd1 : 2'd0) +
                   ((sel[7:6] == sel[3:2]) ? 2'd1 : 2'd0) +
                   ((sel[7:6] == sel[5:4]) ? 2'd1 : 2'd0);

	// 3 bits priority encoder
    function [1:0] first_one;
        input [2:0] rank; // column of spikes
        begin
            if (rank[0]) first_one = 2'd0;
            else if (rank[1]) first_one = 2'd1;
            else if (rank[2]) first_one = 2'd2;
            else first_one = 2'd3; // nessuna
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
        input [2:0] rank; // column of spikes
        input [1:0] k; 	  // selector of the 2nd layer of mux
        reg [2:0] t;
        begin
            t = rank; // column of spikes
            if (k == 2'd0) begin
                choose_spike = first_one(t); // 3-bit PE
            end else if (k == 2'd1) begin
                t = clear_first(t); // reset the first one
                choose_spike = first_one(t); // use again a 3-bit PE :(
            end else begin
                t = clear_first(t); // reset the first one
                t = clear_first(t); // and the second one
                choose_spike = first_one(t); // and use again a 3-bit PE :((((((((
            end
        end
    endfunction

	// Priority Encoder instance
    wire [1:0] spike_address_row_PE0 = choose_spike(R_PE0, rank0);
    wire [1:0] spike_address_row_PE1 = choose_spike(R_PE1, rank1);
    wire [1:0] spike_address_row_PE2 = choose_spike(R_PE2, rank2);
    wire [1:0] spike_address_row_PE3 = choose_spike(R_PE3, rank3);

    // Composizione indirizzo (row,col)
    wire [3:0] temp_PE0 = {spike_address_row_PE0, sel[1:0]};
    wire [3:0] temp_PE1 = {spike_address_row_PE1, sel[3:2]};
    wire [3:0] temp_PE2 = {spike_address_row_PE2, sel[5:4]};
    wire [3:0] temp_PE3 = {spike_address_row_PE3, sel[7:6]};

	// translation from cartesian coordinates to linear coordinates
	/*
					___|_10_|_01_|_00_
					10 | 8  | 7  | 6
					01 | 5  | 4  | 3
					00 | 2  | 1  | 0
	*/
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