`define POTENTIAL
//`define IEEG
`define MNIST

`ifdef IEEG
	`define PATH "ieeg"
	`define CONFIG_PATH "rtl/config/ieeg/config.txt"
`elsif EMG
	 `define PATH "emg"
	 `define CONFIG_PATH "rtl/config/emg/config.txt"
`elsif MNIST
	 `define PATH "mnist"
	 `define CONFIG_PATH "rtl/config/mnist/config.txt"
`endif

//`define CONFIGURABILITY
`define ACCESSIBILITY
//`define UART_HP
`define LOW_POWER
