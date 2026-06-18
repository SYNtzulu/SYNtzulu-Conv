`define POTENTIAL
// >>> SELEZIONA UN SOLO dataset (decommenta uno, lascia commentati gli altri) <<<
//`define IEEG
//`define MNIST
`define OPTICAL_FLOW

 // Per ogni dataset:
 //   `PATH         -> nome cartella usato per TUTTI i file letti a runtime
 //                    (flash, input_even/odd, decay_thr, instruction, snn_inference, ...)
 //   `CONFIG_PATH  -> path del config.txt; deve restare un literal perche'
 //                    l'`include non accetta concatenazioni di macro.

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
