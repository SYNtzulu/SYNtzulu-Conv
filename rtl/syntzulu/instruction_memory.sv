module instruction_memory #(
    parameter RAM_WIDTH = 16,
    parameter INSTR_WIDTH = 64,
    parameter INSTR_DEPTH = 16,
    parameter INSTR_FILE = "/home/federico/Documents/syntzulu_new/rtl/instruction.hex"
)(
    input clk,
    input rst,
    input new_inference_start,
    input en,
    output reg [INSTR_WIDTH-1:0] instruction
);
    wire  [15:0] bram_out;

    reg [63:0] instr_parts;
    reg [2:0]  read_cnt;

    localparam ADDR_WIDTH = clogb2(INSTR_DEPTH-1);
    reg [ADDR_WIDTH-1:0] addr;
    reg [ADDR_WIDTH-1:0] instr_counter;
    wire [ADDR_WIDTH-1:0] instr_counter_plus_four = instr_counter + 4;

    // FSM states
    localparam IDLE = 2'b00;
    localparam READ = 2'b01;
    localparam WAIT = 2'b10;
    localparam DONE = 2'b11;
    
    reg [1:0] state, next_state;
    reg new_layer_en;
    reg first;
    //reg first_comb;  

    //assign read_en = (state == READ);

    SB_RAM40_4K #(
        .INIT_FILE("rtl/instruction.hex")
    )bram (
        .RDATA(bram_out), 
        .RADDR(addr), 
        .RCLK(clk), 
        .RCLKE(1'b1),
        .RE(state == READ || state == IDLE), 
        .WADDR(1'b0), 
        .WCLK(clk), 
        .WCLKE(1'b1),
        .WDATA(1'b0), 
        .WE(1'b0),
        .MASK (16'h0000)
    );

    // FSM transition
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            new_layer_en <= 0;
        end else if(en) begin
            new_layer_en      <= 1;
        end else if (state == DONE) begin
            new_layer_en <= 0;
        end
    end

    wire done = en || first || new_layer_en;

    // FSM next state logic - completamente combinatoria
    always @(*) begin
        //first_comb = first;  
        next_state = state;  
        
        case (state)
            IDLE: begin
                next_state = READ ;
            end
            
            READ: begin
                if (read_cnt == 3'd4) begin 
                    next_state = (done) ? DONE : WAIT;
                end
            end
            
            WAIT: begin
                if (done) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = READ;
            end
        endcase
    end



    // Instruction buffer & control logic
    always @(posedge clk) begin
        if (rst) begin
            read_cnt      <= 0;
            addr          <= 0;
            instr_counter <= 0;
            first <= 1;
            
            // Reset dell'array instr_parts
            for (integer i = 0; i < 4; i = i + 1) begin
                instr_parts[i] <= 0;
            end
        end else begin

            case (state)
                IDLE: begin
                    read_cnt <= 0;
                    addr     <= instr_counter+1;
                end

                READ: begin
                    if (read_cnt >= 3'd1 && read_cnt <= 3'd4) begin
                        /*case (read_cnt)
                            3'd1: instr_parts[63:48] <= bram_out;
                            3'd2: instr_parts[47:32] <= bram_out;
                            3'd3: instr_parts[31:16] <= bram_out;
                            3'd4: instr_parts[15:0]  <= bram_out;
                        endcase*/
                        instr_parts <= {instr_parts[47:0], bram_out};
                    end
                    read_cnt <= read_cnt + 1;
                    addr <= addr + 1;
                end

                WAIT: begin
                    first <= 0;  // Non è più il primo ciclo
                    // Nessuna operazione, solo attesa
                end

                DONE: begin
                    instruction <= instr_parts;
                    addr <= (instr_counter_plus_four < INSTR_DEPTH) ? 
                                   instr_counter_plus_four : 0;
                                   
                    instr_counter <= (instr_counter_plus_four < INSTR_DEPTH) ? 
                                   instr_counter_plus_four: 0;
                    first <= 0;
                end
            endcase
        end
    end

    // Utility function per calcolare la larghezza dell'indirizzo
    function integer clogb2;
        input integer depth;
        begin
            depth = depth - 1;
            for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
                depth = depth >> 1;
        end
    endfunction

endmodule