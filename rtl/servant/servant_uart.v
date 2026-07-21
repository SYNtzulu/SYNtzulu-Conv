`timescale 1 ns / 1 ps

module servant_uart #(
    parameter pClockFrequency = 24000000,
    parameter pBaudRate       = 115200,
    parameter UART_QUEUE = 4
)(
    // Wishbone
    input  wire        i_wb_clk,
    input  wire        wb_rst,
    input  wire [31:0] i_cpu_adr,   
    input  wire [31:0] i_cpu_dat,
    input  wire        i_cpu_we,
    input  wire        i_cpu_cyc,
    output reg  [31:0] o_cpu_rdt,
    output wire         o_cpu_ack,
    input wire [31:0] output_buffer_out,
`ifdef RICEZIONE 
    input  wire i_rxd, //ricezione
`endif
    output wire o_txd
);
`ifdef RICEZIONE 
    // Transmitter
	wire uart_tx_go, uart_tx_go_hp;
	wire [7:0] uart_byte, uart_byte_hp;
	wire [clogb2(UART_QUEUE-1)-1:0] sel;
	wire hp_tx_start;
    wire        uart_if_ready;
    reg uart_if_send;
    reg uart_hp;
    reg [7:0] uart_data;
    reg uart_wren;
    reg		   uart_send_next, uart_send;
	assign hp_tx_start = uart_wren & uart_hp;

    always @(posedge i_wb_clk or posedge wb_rst)
            if(wb_rst)
                uart_wren <= 0;
            else
                uart_wren <= (i_cpu_adr[19:16] == 4'h1) && (i_cpu_cyc & i_cpu_we & o_cpu_ack); 

	fsm_uart_tx #( .N(UART_QUEUE)) 
	fsm_uart_tx_i
		(
		.clk(i_wb_clk),
		.rst(wb_rst),
		.i_start(hp_tx_start),
		.i_continue(uart_if_ready),
		.o_sel(sel),
		.o_valid(uart_tx_go_hp)
		);

	assign uart_byte_hp =  (sel == 0)? output_buffer_out[7:0] : 
                           (sel == 1)? output_buffer_out[15:8]:
                           (sel == 2)? output_buffer_out[23:16] : 
                        	     	   output_buffer_out[31:24];
		
	assign uart_byte = uart_hp ? uart_byte_hp : uart_data;
	assign uart_tx_go = uart_hp ? uart_tx_go_hp : uart_wren;

	SerialTransmitter #(.pClockFrequency(pClockFrequency), .pBaudRate(pBaudRate))
	uart_transmitter(
		.iClock (i_wb_clk),
		.iReset (wb_rst),
		.iData  (uart_byte),
		.iSend  (uart_tx_go),
		.oReady (uart_if_ready),
		.oTxd   (o_txd));



    always @(*) begin
		if (i_cpu_adr[19:16] == 4'h1 && i_cpu_we && i_cpu_cyc) begin
        uart_send_next = i_cpu_dat;
      end
      else begin
        uart_send_next = 0;
      end
    end

    // =============================================================
    //  RX UART
    // =============================================================
    wire [7:0] rx_data_raw;
    wire       rx_valid_pulse;   
    wire       rx_break;         
    
    SerialReceiver #(
        .pClockFrequency (pClockFrequency),
        .pBaudRate       (pBaudRate)         
    ) u_rx (
        .iClock     (i_wb_clk),
        .iRxd       (i_rxd),
        .oData      (rx_data_raw),
        .oReceived  (rx_valid_pulse),
        .oBreak     (rx_break),
        .iReset   (wb_rst)   
    );
    
    
    reg [7:0] rx_latched;
    reg       rx_flag;      
    reg ack_this;
    wire  [3:0] regsel = i_cpu_adr[19:16];         
    reg ack_this_d;   
    always @(posedge i_wb_clk or posedge wb_rst) begin
      if (wb_rst) begin
        rx_latched <= 8'd0;
        rx_flag    <= 1'b0;
      end else begin
        if (rx_valid_pulse) begin
          rx_latched <= rx_data_raw;
          rx_flag    <= 1'b1;
        end
    
       
        if (i_cpu_cyc && !i_cpu_we && o_cpu_ack && regsel == 4'h5 )
          rx_flag <= 1'b0;
      end
    end

    reg ack_int;
    always @(posedge i_wb_clk or posedge wb_rst) begin
      if (wb_rst) begin
        ack_int    <= 1'b0;
      end else begin
        ack_int    <= i_cpu_cyc;
      end
    end
    assign o_cpu_ack = ack_int;	
    


    always @(posedge i_wb_clk) begin
				case (i_cpu_adr[19:16])
					4'h0: begin										
						o_cpu_rdt <= {24'h0, uart_data};
						if (i_cpu_cyc & i_cpu_we) begin
							uart_data <= i_cpu_dat;
						end
					end
					4'h1: begin
						o_cpu_rdt <= {31'h0, uart_if_send};			
					end
					4'h2: begin
						o_cpu_rdt <= {31'h0, uart_if_ready};			
					end 
					4'h3: begin										
						o_cpu_rdt <= {31'h0, uart_hp};
						if (i_cpu_cyc & i_cpu_we) begin
							uart_hp <= i_cpu_dat[0];
						end
					end
          4'h4: o_cpu_rdt <= {24'h0, rx_latched};  
          4'h5: o_cpu_rdt <= {31'h0, rx_flag};     
				endcase
            uart_if_send <= uart_send_next;
    end
`else

    // =============================================================
    //  TRANSMITTER ONLY
    // =============================================================
    wire uart_tx_go, uart_tx_go_hp;
    wire [7:0] uart_byte, uart_byte_hp;
    wire [clogb2(UART_QUEUE-1)-1:0] sel;
    wire hp_tx_start;
    wire uart_if_ready;

    reg  uart_if_send;
    reg  uart_hp = 0;
    reg  [7:0] uart_data = 8'h00;
    reg  uart_wren;
    reg  uart_send_next;

    assign hp_tx_start = uart_wren & uart_hp;

    always @(posedge i_wb_clk or posedge wb_rst)
        if (wb_rst)
            uart_wren <= 0;
        else
            uart_wren <= (i_cpu_adr[19:16] == 4'h1) && (i_cpu_cyc & i_cpu_we & o_cpu_ack); 

    // FSM TX for high-performance stream
    fsm_uart_tx #(.N(UART_QUEUE)) fsm_uart_tx_i (
        .clk(i_wb_clk),
        .rst(wb_rst),
        .i_start(hp_tx_start),
        .i_continue(uart_if_ready),
        .o_sel(sel),
        .o_valid(uart_tx_go_hp)
    );

    assign uart_byte_hp = (sel == 0) ? output_buffer_out[7:0] :
                          (sel == 1) ? output_buffer_out[15:8] :
                          (sel == 2) ? output_buffer_out[23:16] :
                                       output_buffer_out[31:24];

    assign uart_byte  = uart_hp ? uart_byte_hp : uart_data;
    assign uart_tx_go = uart_hp ? uart_tx_go_hp : uart_wren;

    SerialTransmitter #(
        .pClockFrequency(pClockFrequency),
        .pBaudRate(pBaudRate)
    ) uart_transmitter (
        .iClock (i_wb_clk),
        .iReset (wb_rst),
        .iData  (uart_byte),
        .iSend  (uart_tx_go),
        .oReady (uart_if_ready),
        .oTxd   (o_txd)
    );

    // -------------------------------------------------------------
    // Wishbone interface
    // -------------------------------------------------------------
    always @(*) begin
        if (i_cpu_adr[19:16] == 4'h1 && i_cpu_we && i_cpu_cyc && o_cpu_ack)
            uart_send_next = i_cpu_dat;
        else
            uart_send_next = 0;
    end

    reg ack_int;
    always @(posedge i_wb_clk or posedge wb_rst) begin
        if (wb_rst)
            ack_int <= 1'b0;
        else
            ack_int <= i_cpu_cyc;
    end
    assign o_cpu_ack = ack_int;

    always @(posedge i_wb_clk) begin
        case (i_cpu_adr[19:16])
            4'h0: begin
                o_cpu_rdt <= {24'h0, uart_data};
                if (i_cpu_cyc & i_cpu_we)
                    uart_data <= i_cpu_dat;
            end
            4'h1: o_cpu_rdt <= {31'h0, uart_if_send};
            4'h2: o_cpu_rdt <= {31'h0, uart_if_ready};
            4'h3: begin
                o_cpu_rdt <= {31'h0, uart_hp};
                if (i_cpu_cyc & i_cpu_we)
                    uart_hp <= i_cpu_dat[0];
            end
            default: o_cpu_rdt <= 32'h0;
        endcase
        uart_if_send <= uart_send_next;
    end

`endif


	function integer clogb2;
	  input integer depth;
		for (clogb2=0; depth>0; clogb2=clogb2+1)
		  depth = depth >> 1;
	endfunction 
	
endmodule
