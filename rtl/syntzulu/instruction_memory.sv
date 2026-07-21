module instruction_memory #(
    parameter RAM_WIDTH    = 16,
    parameter INSTR_WIDTH  = 80,  // <-- da 64 a 80
    parameter INSTR_DEPTH  = 16,
    parameter INSTR_FILE   = "flash/src/emg/instruction.hex"
)(
    input  clk,
    input  rst,
    input  en,
    // caricamento istruzioni da SPI a boot (era INIT_FILE)
    input             spi_wen,
    input      [13:0] spi_waddr,
    input      [15:0] spi_wdata,
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

    // BRAM 16-bit wide (RAM inferita / FF su ASIC; era SB_RAM40_4K su iCE40).
    // LOW_LATENCY = 1 ciclo di lettura, identico a SB_RAM40_4K (la FSM lo assume).
    // Sola lettura: porta di scrittura A disattivata (wea/ena = 0).
    BRAM_singlePort_readFirst #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(INSTR_DEPTH),
        .RAM_PERFORMANCE("LOW_LATENCY"),
        .INIT_FILE(INSTR_FILE)
    ) bram (
        .addra(spi_waddr[ADDR_WIDTH-1:0]),
        .addrb(addr),
        .dina(spi_wdata),
        .clk(clk),
        .wea(spi_wen),
        .ena(spi_wen),
        .enb(state == READ || state == IDLE),
        .rst(rst),
        .regceb(1'b1),
        .doutb(bram_out_data)
    );

    always @(posedge clk or posedge rst)
        if (rst) bram_out <= 0;
        else     bram_out <= bram_out_data;

    // FSM transition
    always @(posedge clk or posedge rst)
        if (rst) state <= IDLE;
        else     state <= next_state;
/*
    always @(posedge clk or posedge rst) begin
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
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_cnt      <= 0;
            addr          <= 0;
            instr_counter <= 0;
            first         <= 1;
            instr_parts   <= 80'b0;
            instruction   <= 80'b0;
        end else begin
            case (state)
                IDLE: begin
                    read_cnt <= 0;
                    addr     <= instr_counter + 1;
                end

                READ: begin
                    if (read_cnt >= 3'd1 && read_cnt <= 3'd5) begin
                        // shift left 16 bit e aggiungi la nuova parola
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
