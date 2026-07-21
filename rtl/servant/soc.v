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

    // ------------------------------------------------------------------
    //  IHP SG13G2 I/O PAD RING
    //  The soc ports are the chip pads; the core sees the *_i wires.
    //  Inputs  -> sg13g2_IOPadIn      (pad -> p2c)
    //  Outputs -> sg13g2_IOPadOut16mA (c2p -> pad)
    //  Every IO pad cell is 80x180 um regardless of drive strength, so the
    //  16 mA variant is used everywhere and the ring stays homogeneous.
    // ------------------------------------------------------------------
    wire       i_clk_i, i_rst_i;
    wire       i_rxd_i, o_txd_i;
    wire [3:0] led_i;
    wire [2:0] buttons_i;
    wire       i_flash_miso_i;
    wire       o_flash_sck_i, o_flash_ss_i, o_flash_mosi_i;

    sg13g2_IOPadIn      pad_i_clk        (.pad(i_clk),        .p2c(i_clk_i));
    sg13g2_IOPadIn      pad_i_rst        (.pad(i_rst),        .p2c(i_rst_i));
    sg13g2_IOPadIn      pad_i_rxd        (.pad(i_rxd),        .p2c(i_rxd_i));
    sg13g2_IOPadIn      pad_i_flash_miso (.pad(i_flash_miso), .p2c(i_flash_miso_i));

    sg13g2_IOPadIn      pad_buttons_0    (.pad(buttons[0]),   .p2c(buttons_i[0]));
    sg13g2_IOPadIn      pad_buttons_1    (.pad(buttons[1]),   .p2c(buttons_i[1]));
    sg13g2_IOPadIn      pad_buttons_2    (.pad(buttons[2]),   .p2c(buttons_i[2]));

    sg13g2_IOPadOut16mA pad_o_txd        (.pad(o_txd),        .c2p(o_txd_i));

    sg13g2_IOPadOut16mA pad_o_flash_sck  (.pad(o_flash_sck),  .c2p(o_flash_sck_i));
    sg13g2_IOPadOut16mA pad_o_flash_ss   (.pad(o_flash_ss),   .c2p(o_flash_ss_i));
    sg13g2_IOPadOut16mA pad_o_flash_mosi (.pad(o_flash_mosi), .c2p(o_flash_mosi_i));

    sg13g2_IOPadOut16mA pad_led_0        (.pad(led[0]),       .c2p(led_i[0]));
    sg13g2_IOPadOut16mA pad_led_1        (.pad(led[1]),       .c2p(led_i[1]));
    sg13g2_IOPadOut16mA pad_led_2        (.pad(led[2]),       .c2p(led_i[2]));
    sg13g2_IOPadOut16mA pad_led_3        (.pad(led[3]),       .c2p(led_i[3]));

    servant #(
        .memfile (memfile),
        .memsize (memsize),
        .pClockFrequency (pClockFrequency),
        .pBaudRate (pBaudRate),
        .UART_QUEUE (UART_QUEUE),
        .HFOSC (HFOSC)
    )
    servant(
        .i_clk(i_clk_i),
        .i_rst(i_rst_i),
        .led      (led_i),
        .buttons(buttons_i),
        .i_rxd   (i_rxd_i),
        .o_txd   (o_txd_i),
        // SPI slave interface
        .i_flash_miso (i_flash_miso_i),
        .o_flash_sck  (o_flash_sck_i),
        .o_flash_ss   (o_flash_ss_i),
        .o_flash_mosi (o_flash_mosi_i)
        );

	//  The following function calculates the address width based on specified RAM depth
	function integer clogb2;
	  input integer depth;
		for (clogb2=0; depth>0; clogb2=clogb2+1)
		  depth = depth >> 1;
	endfunction   

endmodule
