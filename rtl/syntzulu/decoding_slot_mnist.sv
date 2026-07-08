module decoding_slot_mnist #(
    parameter MAX_NEURONS = 128,
    parameter N_CLASSES   = 10,
    parameter INFERENCES  = 48
)(
    input  wire clk,
    input  wire rst,
    input  wire valid_snn,
    input  wire s1,
    input  wire s2,
    input  wire valid_spike_in,
    input  wire [clogb2(MAX_NEURONS/2-1)-1:0] integrated_neuron_cnt,
    output reg  [3:0] class_out,        // classe predetta (0–9)
    output reg        class_valid,      // 1 = classe valida
    output reg        first_inference,
    output reg [clogb2(INFERENCES):0] inference_cnt
);

    localparam integer SC_WIDTH = 4; //clogb2(INFERENCES);

    reg [SC_WIDTH-1:0] spike_count [0:N_CLASSES-1];
    
    reg [3:0] max_idx;
    reg [SC_WIDTH:0] max_val;

    integer i;

    // funzione log2
    function integer clogb2;
        input integer depth;
        begin
            depth = depth - 1;
            for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
                depth = depth >> 1;
        end
    endfunction
    integer idx1, idx2;
    
    // spike counting + aggiornamento massimo
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N_CLASSES; i = i + 1)
                spike_count[i] <= 0;
            max_val     <= 0;
            max_idx     <= 0;
            class_out   <= 0;
            class_valid <= 0;
        end else if (valid_spike_in) begin
            
            idx1 = {integrated_neuron_cnt, 1'b0};
            idx2 = {integrated_neuron_cnt, 1'b1};

            if (s1) begin
                spike_count[idx1] <= spike_count[idx1] + 1;
                if (spike_count[idx1] + 1 > max_val) begin
                    max_val <= spike_count[idx1] + 1;
                    max_idx <= idx1[3:0];
                end
            end
            if (s2) begin
                spike_count[idx2] <= spike_count[idx2] + 1;
                if (spike_count[idx2] + 1 > max_val) begin
                    max_val <= spike_count[idx2] + 1;
                    max_idx <= idx2[3:0];
                end
            end

            // quando finisce l’inferenza, emette il risultato e resetta i contatori
            if ((inference_cnt == INFERENCES-1) && (integrated_neuron_cnt == N_CLASSES/2 -1)) begin
                class_out   <= max_idx;
                class_valid <= 1'b1;

                // reset contatori spike per la prossima inferenza
                for (i = 0; i < N_CLASSES; i = i + 1)
                    spike_count[i] <= 0;

                max_val <= 0;
                max_idx <= 0;
            end else begin
                class_valid <= 0;
            end
        end else begin
            class_valid <= 0;
        end
    end

    // contatore inferenze
    always @(posedge clk) begin
        if (rst)
            inference_cnt <= 0;
        else if (valid_snn)
            inference_cnt <= (inference_cnt == INFERENCES-1) ? 0 : inference_cnt + 1;
    end

    // segnale first_inference
    always @(posedge clk)
        if (rst)
            first_inference <= 1;
        else
            first_inference <= (inference_cnt == 0);

endmodule