`timescale 1ns / 1ps

module integrator #(parameter WIDTH = 16)(
    input clk, rst, en, detection,
    input conv_enable,
    input pooling_spike_enable,
    input first_input_feature,
    input [WIDTH-1:0] output_old,
    input [13:0] decay,
    input [WIDTH-1:0] stimolo,
    input [WIDTH-1:0] threshold,
    
    output valid,
    output valid_fifo,
    output spike,
    output [WIDTH-1:0] output_new
);
    localparam P_SIZE = WIDTH + 13;

    //(* keep = "true" *) 
    reg signed [WIDTH-1:0] r_stimolo[1:0];
    reg [3:0] en_shift;
    reg signed [WIDTH-1:0] comparator_in;
    wire signed [31:0] mult_out;
    wire signed_out;
/*
    reg [WIDTH-1:0] threshold_d;
    always @(posedge clk)
        threshold_d <= threshold;
*/
    wire signed [15:0] mac_a = output_old[15:0]; // tronca a 16 bit
    wire signed [15:0] mac_b = conv_enable ? (first_input_feature ? { {2{decay[13]}}, decay } : 4096) : { {2{decay[13]}}, decay }; 

    // Istanziazione del blocco DSP
    SB_MAC16 #(
        .A_SIGNED(1'b1),
        .B_SIGNED(1'b1),
        .TOPOUTPUT_SELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00),
        .PIPELINE_16x16_MULT_REG1(1'b1),
        .PIPELINE_16x16_MULT_REG2(1'b1),
        .TOP_8x8_MULT_REG(1'b1),
        .BOT_8x8_MULT_REG(1'b1),
        .A_REG(1'b1),
        .B_REG(1'b1),
        .C_REG(1'b1),
        .D_REG(1'b1),
        .TOPADDSUB_UPPERINPUT(1'b1),
        .TOPADDSUB_LOWERINPUT(2'b10),
        .BOTADDSUB_UPPERINPUT(1'b1),
        .BOTADDSUB_LOWERINPUT(2'b10),
        .TOPADDSUB_CARRYSELECT(2'b10)
    ) mac_inst (
        .A(mac_a),
        .B(mac_b),
        .C(stimolo_c),
        .D(stimolo_d),
        .O(mult_out),
        .CLK(clk),
        .CE(1'b1),
        .IRSTTOP(rst),
        .IRSTBOT(rst),
        .ORSTTOP(1'b0),
        .ORSTBOT(1'b0),
        .AHOLD(1'b0),
        .BHOLD(1'b0),
        .CHOLD(1'b0),
        .DHOLD(1'b0),
        .OHOLDTOP(1'b0),
        .OHOLDBOT(1'b0),
        .OLOADTOP(1'b0),
        .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0),
        .ADDSUBBOT(1'b0),
        .CI(1'b0),
        .CO(),
        .ACCUMCI(),
        .ACCUMCO(carry_out),
        .SIGNEXTIN(),
        .SIGNEXTOUT(signed_out)
    );

    //(* keep = "true" *) 
    wire signed [31:0] stimolo_32;
    assign stimolo_32 = $signed({r_stimolo[1],12'b0});

    //(* keep = "true" *) 
    wire [15:0] stimolo_c, stimolo_d;

    assign stimolo_c = stimolo_32[31:16]; // Prendi i primi 16 bit
    assign stimolo_d = stimolo_32[15:0]; // Prendi i secondi 16 bit
    reg [P_SIZE-1:0] supporto_1;
    wire signed_result_negative = mac_a[15] ^ mac_b[15];

    reg r_signed_out [2:0];
    // Pipeline
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            en_shift <= 0;
            r_stimolo[0] <= 0;
            r_stimolo[1] <= 0;
            for(i = 0; i < 3; i = i + 1)
                r_signed_out[i] <= 0;
        end else begin
            en_shift[0] <= en;
            r_stimolo[0] <= stimolo;
            r_signed_out[0] <= signed_result_negative;

            en_shift[1] <= en_shift[0];
            r_stimolo[1] <= r_stimolo[0];
            r_signed_out[1] <= r_signed_out[0]; 

            en_shift[2] <= en_shift[1];
            r_signed_out[2] <= r_signed_out[1]; 

            en_shift[3] <= en_shift[2];
            
            if(r_signed_out[2])begin
                supporto_1 = ~mult_out+1'b1;
                comparator_in <= ~supporto_1[P_SIZE-1:12]+1'b1;
            end
            else
                comparator_in <= mult_out[P_SIZE-1:12];
            //comparator_in <= mult_out[P_SIZE-1:12] + (r_signed_out[2]& mult_out[P_SIZE-1]);// - (r_signed_out[2]& ~mult_out[P_SIZE-1]);  //-1 se è positivo +1 se negativo;
        end
    end

    assign spike = pooling_spike_enable ? 1'b1 : (($signed(comparator_in) >= $signed(threshold)) & detection);
    assign output_new = spike ? comparator_in - threshold : comparator_in;
    assign valid_fifo = en_shift[3];
    assign valid = en_shift[3] && detection;

endmodule