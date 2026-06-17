`timescale 1ns/1ps

module tb_decoder;

    // === Parametri ===
    localparam MAX_NEURONS = 128;
    localparam N_CLASSES   = 10;
    localparam INFERENCES  = 48;
    localparam SC_WIDTH    = 4;

    // === Segnali DUT ===
    reg  clk;
    reg  rst;
    reg  valid_snn;
    reg  valid_spike_in;
    reg  s1, s2;
    reg  [3:0] integrated_neuron_cnt;

    wire [3:0] class_out;
    wire       class_valid;
    wire       first_inference;
    wire [5:0] inference_cnt;

    // === Instanza DUT ===
    decoding_slot_mnist #(
        .MAX_NEURONS(MAX_NEURONS),
        .N_CLASSES(N_CLASSES),
        .INFERENCES(INFERENCES),
        .SC_WIDTH(SC_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_snn(valid_snn),
        .s1(s1),
        .s2(s2),
        .valid_spike_in(valid_spike_in),
        .integrated_neuron_cnt(integrated_neuron_cnt),
        .class_out(class_out),
        .class_valid(class_valid),
        .first_inference(first_inference),
        .inference_cnt(inference_cnt)
    );

    // === Clock ===
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // === Stimoli ===
    integer i;
    initial begin
        $dumpfile("tb_decoder.vcd");
        $dumpvars(10, tb_decoder);

        // inizializzazione
        rst = 1;
        valid_snn = 0;
        valid_spike_in = 0;
        s1 = 0; s2 = 0;
        integrated_neuron_cnt = 0;

        // reset
        #30;
        rst = 0;
        valid_snn = 1;

        // Simulazione di 48 inferenze
        for (i = 0; i < INFERENCES; i = i + 1) begin
            send_spikes_for_inference(i);
        end

        #200;
        $display("=== SIMULAZIONE COMPLETATA ===");
        $finish;
    end

    // === Task per simulare spike ===
    task send_spikes_for_inference(input integer inf_id);
        integer num_spikes;
        integer spike_i;
        begin
            num_spikes = $urandom_range(20, 50); // spike totali in questa inferenza
            $display("[%0t ns] --> Inizio inferenza %0d con %0d spike",
                     $time, inf_id, num_spikes);
            for (spike_i = 0; spike_i < num_spikes; spike_i = spike_i + 1) begin
                @(posedge clk);
                valid_spike_in = 1;

                // genera spike su s1 e/o s2 casualmente
                case ($urandom_range(0,2))
                    0: begin s1 = 1; s2 = 0; end
                    1: begin s1 = 0; s2 = 1; end
                    2: begin s1 = 1; s2 = 1; end // entrambi
                endcase

                // incrementa il contatore dei neuroni
                integrated_neuron_cnt <= integrated_neuron_cnt + 1;
                if (integrated_neuron_cnt >= (N_CLASSES/2 - 1))
                    integrated_neuron_cnt <= 0;

                @(posedge clk);
                valid_spike_in = 0;
                s1 = 0; s2 = 0;
            end

            // piccola pausa tra inferenze
            repeat (5) @(posedge clk);
        end
    endtask

    // === Monitor ===
    always @(posedge clk) begin
        if (class_valid) begin
            $display("[%0t ns] ➜ Inferenza terminata! Classe predetta = %0d",
                     $time, class_out);
        end
    end

endmodule
