module ram_1024x16 #(
    parameter INIT_FILE_RAM0 = "",
    parameter INIT_FILE_RAM1 = "",
    parameter INIT_FILE_RAM2 = "",
    parameter INIT_FILE_RAM3 = ""
    )(
    input clk,

    input        we,
    input [9:0]  waddr,
    input [15:0] wdata,

    input        re,
    input [9:0]  raddr,
    output reg [15:0] rdata
);

wire [1:0] wbank = waddr[9:8];

reg [1:0] rbank_d;
always @(posedge clk) begin
    rbank_d <= rbank;
end

wire [1:0] rbank = raddr[9:8];

wire [7:0] waddr_int = waddr[7:0];
wire [7:0] raddr_int = raddr[7:0];

wire [15:0] rdata0, rdata1, rdata2, rdata3;

////////////////////
// RAM 0
////////////////////
SB_RAM40_4K #(
    .INIT_FILE(INIT_FILE_RAM0))
ram0 (
    .RDATA(rdata0),
    .RCLK(clk),
    .RCLKE(1'b1),
    .RE(re && (rbank == 2'b00)),
    .RADDR({3'b000, raddr_int}),

    .WCLK(clk),
    .WCLKE(1'b1),
    .WE(we && (wbank == 2'b00)),
    .WADDR({3'b000, waddr_int}),
    .MASK(16'h0000),
    .WDATA(wdata)
);

////////////////////
// RAM 1
////////////////////
SB_RAM40_4K #(
    .INIT_FILE(INIT_FILE_RAM1))
ram1 (
    .RDATA(rdata1),
    .RCLK(clk),
    .RCLKE(1'b1),
    .RE(re && (rbank == 2'b01)),
    .RADDR({3'b000, raddr_int}),

    .WCLK(clk),
    .WCLKE(1'b1),
    .WE(we && (wbank == 2'b01)),
    .WADDR({3'b000, waddr_int}),
    .MASK(16'h0000),
    .WDATA(wdata)
);

////////////////////
// RAM 2
////////////////////
SB_RAM40_4K #(
    .INIT_FILE(INIT_FILE_RAM2))
ram2 (
    .RDATA(rdata2),
    .RCLK(clk),
    .RCLKE(1'b1),
    .RE(re && (rbank == 2'b10)),
    .RADDR({3'b000, raddr_int}),

    .WCLK(clk),
    .WCLKE(1'b1),
    .WE(we && (wbank == 2'b10)),
    .WADDR({3'b000, waddr_int}),
    .MASK(16'h0000),
    .WDATA(wdata)
);

////////////////////
// RAM 3 (NUOVA)
////////////////////
SB_RAM40_4K #(
    .INIT_FILE(INIT_FILE_RAM3))
ram3 (
    .RDATA(rdata3),
    .RCLK(clk),
    .RCLKE(1'b1),
    .RE(re && (rbank == 2'b11)),
    .RADDR({3'b000, raddr_int}),

    .WCLK(clk),
    .WCLKE(1'b1),
    .WE(we && (wbank == 2'b11)),
    .WADDR({3'b000, waddr_int}),
    .MASK(16'h0000),
    .WDATA(wdata)
);

////////////////////
// READ MUX
////////////////////
always @(posedge clk) begin
    case (rbank_d)
        2'b00: rdata <= rdata0;
        2'b01: rdata <= rdata1;
        2'b10: rdata <= rdata2;
        2'b11: rdata <= rdata3;
        default: rdata <= 16'h0000;
    endcase
end

endmodule