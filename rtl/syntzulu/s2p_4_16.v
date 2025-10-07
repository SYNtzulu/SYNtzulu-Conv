module s2p_4_16 (
    input clk,
    input rst,
    input clr,
    input en,
    input [1:0] select_spike_in,
    input [3:0] spike_in,
    output reg [15:0] spike_out,
    output reg valid
    );

    always @(posedge clk or posedge rst) begin
        if (rst || clr) begin
            spike_out <= 16'd0;
            valid <= 1'b0;
        end else begin
            if(en) begin
                case (select_spike_in)
                    2'd0: spike_out[15:12] <= spike_in;
                    2'd1: spike_out[11:8]  <= spike_in;
                    2'd2: spike_out[7:4]   <= spike_in;
                    2'd3: spike_out[3:0]   <= spike_in;
                endcase
                valid <= 1'b1;
            end 
            else begin
                valid <= 1'b0;
            end
        end
    end
endmodule