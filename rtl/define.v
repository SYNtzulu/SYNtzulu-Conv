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
	 // >>> Per usare un altro dataset cambia il nome cartella in QUESTE due righe <<<
	 // `PATH         -> usato per TUTTI i file letti a runtime (flash, input, decay_thr, ...)
	 // `CONFIG_PATH  -> deve restare un literal: l'`include non accetta concatenazioni
	 `define PATH "mnist"
	 `define CONFIG_PATH "mnist/config.txt"
`endif

//`define CONFIGURABILITY
`define ACCESSIBILITY
//`define UART_HP
`define LOW_POWER
