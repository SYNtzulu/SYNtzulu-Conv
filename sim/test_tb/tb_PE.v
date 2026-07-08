`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Self-checking testbench per priority_encoder (kernel=9bit, 3 cicli = 9 spike)
//////////////////////////////////////////////////////////////////////////////////

module tb_encoder;

    // CLOCK
    reg clk = 0;
    reg en = 0;
    always #0.5 clk = ~clk;  // clock periodo 1ns

    // INPUT
    reg [8:0] kernel_in;
    wire [15:0] spike_address;   // <-- corretto: 16 bit come nel DUT

    // DUT
    priority_encoder dut (
        .clk(clk),
        .en(en),
        .kernel_in(kernel_in),
        .spike_address(spike_address),
        .conv_enable(1'b1)
    );  

    // SUPPORT VARS
    integer i, j, k;
    reg [3:0] expected_spikes[0:8];   // massimo 9 spike
    integer expected_count;
    reg [3:0] captured_spikes[0:11];  // 3 cicli × 4 spike = 12 max
    integer captured_count;

    // Task: calcola spike attesi da kernel_in
    task get_expected_spikes(input [8:0] value);
        integer idx;
        begin
            expected_count = 0;
            for (idx = 0; idx < 9; idx = idx + 1) begin
                if (value[idx]) begin
                    expected_spikes[expected_count] = idx[3:0];
                    expected_count = expected_count + 1;
                end
            end
            // Se non ci sono bit attivi → aspettati uno 0xB
            if (expected_count == 0) begin
                expected_spikes[0] = 4'hB;
                expected_count = 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_encoder.vcd");
        $dumpvars(0, tb_encoder);

        kernel_in = 9'b0;
        en = 0;

        // Loop su tutte le combinazioni (512 test)
        for (i = 0; i < 512; i = i + 1) begin
            #2 kernel_in = i[8:0];
            get_expected_spikes(kernel_in);

            // Avvio DUT
            #1 en = 1;
            #1 en = 0;

            // Attendi 12 fronti di clock e cattura output
            captured_count = 0;
            repeat (12) begin
                @(posedge clk);
                // spike_address è 16 bit → prendi i 4 spike paralleli
                captured_spikes[captured_count]   = spike_address[3:0];
                captured_spikes[captured_count+1] = spike_address[7:4];
                captured_spikes[captured_count+2] = spike_address[11:8];
                captured_spikes[captured_count+3] = spike_address[15:12];
                captured_count = captured_count + 4;
            end

            // --- CHECK ---
            // Verifica: ogni atteso deve comparire almeno una volta
            for (j = 0; j < expected_count; j = j + 1) begin
                reg found;
                found = 0;
                for (k = 0; k < captured_count; k = k + 1) begin
                    if (captured_spikes[k] == expected_spikes[j])
                        found = 1;
                end
                if (!found) begin
                    $display("ERRORE: kernel_in=%b -> spike atteso %0d mancante @time %0t",
                             kernel_in, expected_spikes[j], $time);
                end
            end

            // Verifica: nessun duplicato (escludendo 0xB)
            for (j = 0; j < captured_count; j = j + 1) begin
                for (k = j+1; k < captured_count; k = k + 1) begin
                    if (captured_spikes[j] == captured_spikes[k] &&
                        captured_spikes[j] != 4'hB) begin
                        $display("ERRORE: kernel_in=%b -> spike duplicato %0d @time %0t",
                                 kernel_in, captured_spikes[j], $time);
                    end
                end
            end

            // Stampa risultato
            $write("OK: kernel_in=%b -> spikes catturati=", kernel_in);
            for (j = 0; j < captured_count; j = j + 1) begin
                $write("%0d ", captured_spikes[j]);
            end
            $write("\n");
        end

        $finish;
    end

endmodule
