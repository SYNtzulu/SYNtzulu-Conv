`timescale 1ns/1ps

module tb_spike_mem_new_new;

    // Parameters del DUT
    localparam SPIKE_MEM_WIDTH = 16;
    localparam SPIKE_MEM_DEPTH = 16;
    localparam MAX_SYNAPSES = 128;

    // Segnali per il testbench
    reg clk;
    reg rst;
    reg s1, s2;
    reg valid_s1, valid_s2;
    reg dense_enable;
    reg conv_enable;
    reg [4:0] next_dim_input_feature;
    reg [9:0] SYNAPSES;
    reg [clogb2(MAX_SYNAPSES/4-1)-1:0] spike_rd_addr_mux;

    wire [8:0] spike_wr_addr;
    wire [SPIKE_MEM_WIDTH-1:0] spike_mem_out_16;
    wire [3:0] spike_mem_out_4;

    // DUT (Device Under Test)
    spike_mem_new_new #(
        .SPIKE_MEM_WIDTH(SPIKE_MEM_WIDTH),
        .SPIKE_MEM_DEPTH(SPIKE_MEM_DEPTH),
        .MAX_SYNAPSES(MAX_SYNAPSES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s1(s1),
        .valid_s1(valid_s1),
        .s2(s2),
        .valid_s2(valid_s2),
        .dense_enable(dense_enable),
        .conv_enable(conv_enable),
        .next_dim_input_feature(next_dim_input_feature),
        .SYNAPSES(SYNAPSES),
        .spike_rd_addr_mux(spike_rd_addr_mux),
        .spike_wr_addr(spike_wr_addr),
        .spike_mem_out_16(spike_mem_out_16),
        .spike_mem_out_4(spike_mem_out_4)
    );

    // Generatore del clock
    always #5 clk = ~clk;

    integer i;

    // Stimoli e controllo
    initial begin
        // Comandi per il dump delle forme d'onda
        $dumpfile("tb_lif.vcd");
        $dumpvars(0, tb_spike_mem_new_new); // 0 per dumpare tutti i segnali nella gerarchia

        $display("--- Avvio Testbench ---");

        // Inizializzazione e reset
        clk = 0;
        rst = 1;
        dense_enable = 1;
        conv_enable  = 0;
        s1 = 0; s2 = 0;
        valid_s1 = 0; valid_s2 = 0;
        next_dim_input_feature = 0;
        SYNAPSES = 0;
        spike_rd_addr_mux = 0;

        // Reset
        #20 rst = 0;

        // Abilita i segnali di validità per tutti i test
        valid_s1 = 1;
        valid_s2 = 1;

        // Test con next_dim_input_feature = 5
        run_test_case(5, 10'd15);
        
        // Test con next_dim_input_feature = 6
        run_test_case(6, 10'd16);

        // Test con next_dim_input_feature = 7
        run_test_case(7, 10'd17);

        // Test con next_dim_input_feature = 16
        run_test_case(16, 10'd18);

        // 🔴 Nuovo test richiesto: conv_enable = 1, dense_enable = 0
        $display("\n--- Avvio Test con conv_enable=1 e dense_enable=0 ---");
        dense_enable = 0;
        conv_enable  = 1;
        run_test_case(8, 10'd20);

        $display("--- Testbench completato ---");
        $finish;
    end
    
    // Task per eseguire un singolo test
    task run_test_case;
        input [3:0] test_dim_feature;
        input [9:0] test_synapses;
        begin
            $display("\n=== Test per next_dim_input_feature = %0d ===", test_dim_feature);
            
            // Applica gli ingressi
            next_dim_input_feature = test_dim_feature;
            SYNAPSES = test_synapses;

            // Esegui la scrittura per un numero di cicli
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                // Genera spike casuali
                s1 = $random % 2;
                s2 = $random % 2;
            end

            // Esegui la lettura dei dati memorizzati
            $display("Inizio lettura dei dati dalla memoria...");
            for (i = 0; i < 4; i = i + 1) begin
                spike_rd_addr_mux = i;
                @(posedge clk);
                @(posedge clk); // Attendi la latenza di 2 cicli
                $display("Time %0t: Letto da spike_rd_addr_mux = %0d, spike_mem_out_4 = %b", $time, i, spike_mem_out_4);
            end
        end
    endtask

    // Funzione per il calcolo del log base 2
    function integer clogb2;
      input integer value;
      begin
        value = value - 1;
        for (clogb2=0; value>0; clogb2=clogb2+1)
          value = value >> 1;
      end
    endfunction

endmodule
