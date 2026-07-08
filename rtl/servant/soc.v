`default_nettype none
// `include `CONFIG_PATH
module soc #(
	parameter HFOSC = "0b01", // "0b00" = 48 MHz, "0b01" = 24 MHz, "0b10" = 12 MHz, "0b11" = 6 MHz
	parameter memfile = "firmware/exe.hex",
    parameter memsize =  4096,
    parameter pClockFrequency = 24_000_000, // 12 MHz
    parameter pBaudRate = 4000000, // 4 MHz
    parameter UART_QUEUE = 1
)
(
    input wire  i_clk, i_rst,
    input wire i_rxd,
    output wire [3:0] led,
	input  wire [2:0] buttons,
    output wire o_txd,
    // SPI slave interface
    input  wire i_flash_miso,
    output wire o_flash_sck,
    output wire o_flash_ss,
    output wire o_flash_mosi
);	

	
//////////////////////////////////////////////////////////////////////////////////////
//   ____  _____ ______     ___    _   _ _____                                      //
//  / ___|| ____|  _ \ \   / / \  | \ | |_   _|                                     //
//  \___ \|  _| | |_) \ \ / / _ \ |  \| | | |                                       //
//   ___) | |___|  _ < \ V / ___ \| |\  | | |                                       //
//  |____/|_____|_| \_\ \_/_/   \_\_| \_| |_|                                       //
//   ____  _____ ______     __  ____  ___ ____   ______     __  ____         ____   //
//  / ___|| ____|  _ \ \   / / |  _ \|_ _/ ___| / ___\ \   / / / ___|  ___  / ___|  //
//  \___ \|  _| | |_) \ \ / /  | |_) || |\___ \| |    \ \ / /  \___ \ / _ \| |      //
//   ___) | |___|  _ < \ V /   |  _ < | | ___) | |___  \ V /    ___) | (_) | |___   //
//  |____/|_____|_| \_\ \_/    |_| \_\___|____/ \____|  \_/    |____/ \___/ \____|  //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

    servant #(
        .memfile (memfile),
        .memsize (memsize),
        .pClockFrequency (pClockFrequency),
        .pBaudRate (pBaudRate),
        .UART_QUEUE (UART_QUEUE),
        .HFOSC (HFOSC)
    )
    servant(
        .i_clk(i_clk),
        .i_rst(i_rst),
        .led      (led),
        .buttons(buttons),
        .i_rxd   (i_rxd),
        .o_txd   (o_txd),
        // SPI slave interface
        .i_flash_miso (i_flash_miso),
        .o_flash_sck  (o_flash_sck),
        .o_flash_ss   (o_flash_ss),
        .o_flash_mosi (o_flash_mosi)
        );

	//  The following function calculates the address width based on specified RAM depth
	function integer clogb2;
	  input integer depth;
		for (clogb2=0; depth>0; clogb2=clogb2+1)
		  depth = depth >> 1;
	endfunction   

endmodule