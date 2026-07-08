`define POTENTIAL
// >>> SELECT ONLY ONE dataset (uncomment one, leave the others commented) <<<
//`define IEEG
//`define MNIST
`define OPTICAL_FLOW

 // For each dataset:
 //   `PATH         -> folder name used for ALL files read at runtime
 //                    (flash, input_even/odd, decay_thr, instruction, snn_inference, ...)
 //   `CONFIG_PATH  -> path of config.txt; must remain a literal because
 //                    `include does not accept macro concatenations.

`ifdef IEEG
	`define PATH "ieeg"
	`define CONFIG_PATH "rtl/config/ieeg/config.txt"
`elsif EMG
	 `define PATH "emg"
	 `define CONFIG_PATH "rtl/config/emg/config.txt"
`elsif MNIST
	 `define PATH "mnist"
	 `define CONFIG_PATH "mnist/config.txt"
`elsif OPTICAL_FLOW
	 `define PATH "optical_flow"
	 `define CONFIG_PATH "optical_flow/config.txt"
`endif

//`define CONFIGURABILITY
`define ACCESSIBILITY
//`define UART_HP
`define LOW_POWER
