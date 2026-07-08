module instruction_memory #(
    parameter RAM_WIDTH    = 16,
    parameter INSTR_WIDTH  = 80,  // <-- from 64 to 80
    parameter INSTR_DEPTH  = 16,
    parameter INSTR_FILE   = "flash/src/emg/instruction.hex"
)(
    input  clk,
    input  rst,
    input  new_inference_start,
    input  en,
    // write port (external loading from AXI/TB)
    input  wren,
    input  [clogb2(INSTR_DEPTH-1)-1:0] wr_addr,
    input  [15:0] data_in,
    (* keep *) output reg [INSTR_WIDTH-1:0] instruction
);

    wire [15:0] bram_out_data;
    reg  [15:0] bram_out;
    (* keep *) reg  [INSTR_WIDTH-1:0] instr_parts; 
    reg  [2:0] read_cnt;

    localparam ADDR_WIDTH = clogb2(INSTR_DEPTH-1);
    reg [ADDR_WIDTH-1:0] addr;
    reg [ADDR_WIDTH-1:0] instr_counter;
    wire [ADDR_WIDTH-1:0] instr_counter_plus_five = instr_counter + 5;

    // FSM states
    localparam IDLE = 2'b00;
    localparam READ = 2'b01;
    localparam WAIT = 2'b10;
    localparam DONE = 2'b11;

    reg [1:0] state, next_state;
    reg first;

    initial instruction = 80'h0000000000000000;
    initial instr_parts = 80'h0000000000000000;

    // BRAM 16-bit wide (single-port read-first, like all the other memories).
    // RAM_PERFORMANCE("LOW_LATENCY") -> 1 read latency cycle, like the
    // old SB_RAM40_4K, so the assembly FSM remains unchanged.
    BRAM_singlePort_readFirst #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(INSTR_DEPTH),
        .RAM_PERFORMANCE("LOW_LATENCY"),
        .INIT_FILE(INSTR_FILE)
    ) bram (
        .addra(wr_addr),                         // port A: write (loading)
        .addrb(addr),                            // port B: read (FSM)
        .dina(data_in),
        .clk(clk),
        .wea(wren),
        .ena(wren),
        .enb(state == READ || state == IDLE),    // = vecchio RE
        .rst(rst),
        .regceb(1'b1),
        .doutb(bram_out_data)
    );

    always @(posedge clk)
        if (rst) bram_out <= 0;
        else     bram_out <= bram_out_data;

    // FSM transition
    always @(posedge clk)
        if (rst) state <= IDLE;
        else     state <= next_state;
/*
    always @(posedge clk) begin
        if (rst)
            new_layer_en <= 0;
        else if (en)
            new_layer_en <= 1;
        else if (state == DONE)
            new_layer_en <= 0;
    end
*/
    wire done = en || first;// || new_layer_en

    // FSM combinatorial next state
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: next_state = READ;
            READ: if (read_cnt == 3'd5)
                      next_state = (done) ? DONE : WAIT;
            WAIT: if (done)
                      next_state = DONE;
            DONE: next_state = IDLE;
            default: next_state = READ;
        endcase
    end

    // Instruction assembly
    always @(posedge clk) begin
        if (rst) begin
            read_cnt      <= 0;
            addr          <= 0;
            instr_counter <= 0;
            first         <= 1;
            instr_parts   <= 80'b0;
        end else begin
            case (state)
                IDLE: begin
                    read_cnt <= 0;
                    addr     <= instr_counter + 1;
                end

                READ: begin
                    if (read_cnt >= 3'd1 && read_cnt <= 3'd5) begin
                        // shift left 16 bits and append the new word
                        instr_parts <= {instr_parts[INSTR_WIDTH-17:0], bram_out};
                    end
                    read_cnt <= read_cnt + 1;
                    addr     <= addr + 1;
                end

                WAIT: begin
                    first <= 0;
                end

                DONE: begin
                    instruction <= instr_parts;
                    addr <= (instr_counter_plus_five < INSTR_DEPTH) ?
                              instr_counter_plus_five : 0;

                    instr_counter <= (instr_counter_plus_five < INSTR_DEPTH) ?
                              instr_counter_plus_five : 0;
                    first <= 0;
                end
                default:begin
                    read_cnt <= 0;
                    addr     <= instr_counter + 1;
                end

            endcase
        end
    end

    // Utility function
    function integer clogb2;
        input integer depth;
        begin
            depth = depth - 1;
            for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
                depth = depth >> 1;
        end
    endfunction

endmodule
