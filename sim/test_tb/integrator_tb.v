`timescale 1ns / 1ps

module tb_integrator;

    // Parametri
    parameter WIDTH = 16;

    // Segnali
    reg clk = 0;
    reg rst;
    reg en;
    reg detection;
    reg [WIDTH-1:0] output_old;
    reg [13:0] decay;
    reg [WIDTH-1:0] stimolo;
    reg [WIDTH-1:0] threshold;

    wire valid;
    wire spike;
    wire [WIDTH-1:0] output_new;

    // Clock a 10ns (100 MHz)
    always #5 clk = ~clk;

    // Istanzia il DUT (Device Under Test)
    integrator_new #(WIDTH) dut_new (
        .clk(clk),
        .rst(rst),
        .en(en),
        .detection(detection),
        .output_old(output_old),
        .decay(decay),
        .stimolo(stimolo),
        .threshold(threshold),
        .valid(valid_new),
        .spike(spike_new),
        .output_new(output_new_new)
    );

    // Istanzia il DUT (Device Under Test)
    integrator #(WIDTH) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .detection(detection),
        .output_old(output_old),
        .decay(decay),
        .stimolo(stimolo),
        .threshold(threshold),
        .valid(valid),
        .spike(spike),
        .output_new(output_new)
    );
    // Stimolo
    initial begin
        // Inizializza
        $dumpfile("tb_integrator.vcd"); 
        $dumpvars(10,tb_integrator); 
        $display("Time\tvalid\tspike\toutput_new");
        rst = 1;
        en = 0;
        detection = 0;
        output_old = 0;
        decay = 14'd4096; // ~1.0 in Q12
        stimolo = 25'd1000;
        threshold = 16'h1000;

        #20;
        rst = 0;

        // Primo ciclo attivo
        @(posedge clk);
        en = 1;
        detection = 1;
        output_old = 25'd1000; // esempio
        stimolo = 25'd800;
        threshold = 16'h1200;

        @(posedge clk); en = 0; // disattiva abilitazione

        // Aspetta valid
        repeat (4) @(posedge clk);
        $display("%0dns\t%b\t%b\t%d", $time, valid, spike, output_new);

        // Prova con somma sopra soglia → spike
        @(posedge clk);
        en = 1;
        output_old = 25'd2000;
        stimolo = 25'd1000;
        threshold = 25'd2500;

        @(posedge clk); en = 0;
        repeat (4) @(posedge clk);
        $display("%0dns\t%b\t%b\t%d", $time, valid, spike, output_new);

        // Caso con reset
        @(posedge clk);
        rst = 1;
        @(posedge clk);
        rst = 0;

        $finish;
    end

endmodule
