`timescale 1ns/1ps

module tb_integrator_snnTorch;

    // Parametri
    parameter nbits_M       =  8;
    parameter nbits_thr     = 16;
    parameter nbits_decay   =  8;
    parameter nbits_voltage =  8;

    // Segnali
    reg clk;
    reg rst;

    reg en;
    reg detection;
    reg conv_enable;
    reg pooling_spike_enable;
    reg last_input_feature;
    reg recurrency;
    reg recurrency_next;

    reg [nbits_voltage-1:0] output_old;
    reg [nbits_thr-1:0]     threshold;
    reg [nbits_decay:0]   decay;
    reg [nbits_M-1:0]       M;
    reg signed [15:0]              buffer_current;

    wire valid;
    wire valid_fifo;
    wire spike;
    wire signed [nbits_voltage-1:0] output_new;
    
    integer i, file_in, file_exp;
    reg signed [15:0] tmp_in;
    reg signed [7:0] tmp_exp;
    integer r_in, r_exp;
    reg signed [7:0] expected_output;
    integer cycle;


    // DUT
    integrator_snnTorch #(
        .nbits_M(nbits_M),
        .nbits_thr(nbits_thr),
        .nbits_decay(nbits_decay),
        .nbits_voltage(nbits_voltage)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .detection(detection),
        .conv_enable(conv_enable),
        .pooling_spike_enable(pooling_spike_enable),
        .last_input_feature(last_input_feature),
        .recurrency(recurrency),
        .recurrency_next(recurrency_next),
        .output_old(output_old),
        .threshold(threshold),
        .decay(decay),
        .M(M),
        .buffer_current(buffer_current),
        .valid(valid),
        .valid_fifo(valid_fifo),
        .spike(spike),
        .output_new(output_new)
    );

    // Clock: 10ns periodo
    always #10 en = ~en;
    
    initial begin
	$dumpfile("wave.vcd");
	$dumpvars(0, tb_integrator_snnTorch);
    	pooling_spike_enable = 0;
    	detection = 1;
    	recurrency = 0;
    	en = 0;
    	M = 5; threshold = 780; decay = 230; output_old = 0;
    	cycle = 0;
 
        file_in  = $fopen("verilog_tb_files/buffer_current.txt", "r");
        file_exp = $fopen("verilog_tb_files/output_new_expected.txt", "r");   	
                 
        // Loop principale
        while (!$feof(file_in) && !$feof(file_exp)) begin

	r_in  = $fscanf(file_in, "%h\n", tmp_in);
	r_exp = $fscanf(file_exp, "%h\n", tmp_exp);

	buffer_current   = tmp_in;
	expected_output  = tmp_exp;
           

            @(posedge en);

            // Aspetta che output sia valido (se necessario puoi ritardare)
            #1;

            // Check
            if (output_new !== expected_output) begin
                $display("ERRORE ciclo %0d: input=%0d expected=%0d got=%0d",
                         cycle, buffer_current, expected_output, output_new);
            end else begin
                $display("OK ciclo %0d: input=%0d output=%0d",
                         cycle, buffer_current, output_new);
            end

            // aggiorna stato (feedback)
            output_old = output_new;

            cycle = cycle + 1;
        end

        $fclose(file_in);
        $fclose(file_exp);

        $display("Simulazione completata");
    	

    	$finish;
    end
    
    

endmodule











