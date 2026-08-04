# SYNtzulu-Conv on IHP 130 nm — ASIC implementation

This branch (`syntzulu_conv_ihp130`) implements **SYNtzulu-Conv** as an ASIC on
the **IHP SG13G2 130 nm open-source PDK**. Everything needed to reproduce the
flow — RTL, design setup, and the scripts that glue the tools together — is
published here.

SYNtzulu-Conv is a Convolutional Spiking Neural Network (SNN) processing core
designed for low-cost, low-power devices, enabling real-time near-sensor data
analysis. The system features a **dual-core neuromorphic processor**, with each
core capable of processing four synapses and one neuron per clock cycle, plus a
**tiny RISC-V subsystem** (SERV + Servant platform) that handles input/output
and configures runtime parameters. Input data is fetched over **SPI** from an
external flash acting as the sensor, and inference results are transmitted over
**UART**.

The SNN datapath is unchanged; the port concentrates on what a standard-cell
target requires:

- All memories mapped onto **IHP single- and dual-port SRAM macros** — 22 macros
  in the SoC.
- Fully **asynchronous reset** conversion: no reliance on power-up register
  values, which do not exist on silicon.
- Explicit **clock gating** through `sg13g2_lgcp_1` integrated clock gates,
  instantiated by the design's own wrapper rather than by the platform default.
- A complete **IHP SG13G2 I/O pad ring** around the SoC.
- Boot from an on-chip **ROM** that loads the CPU firmware, the SNN weights, and
  the SNN instructions from the external SPI flash.

For further details regarding SYNtzulu-Conv see the related paper available in
open access [here]().

## What is in this repository

| Path | Content |
|------|---------|
| `rtl/` | The design: SNN core (`syntzulu/`), RISC-V subsystem (`serv/`, `servant/`), SoC top level with the pad ring, and the IHP memory wrappers (`memorie_ihp/`) |
| `rtl/behavioural_ihp/` | Behavioural simulation models of the IHP SRAM macros (blackboxes after synthesis) |
| `std_cells/` | IHP SG13G2 standard-cell, clock-gate, and I/O simulation models used by gate-level simulation |
| `orfs_setup/` | OpenROAD Flow Scripts design setup: `config_soc.mk`, SDC constraints, floorplan/PDN/pad-ring Tcl, and the flow hooks used to close timing and DRV |
| `scripts/` | Python helpers: flash image builder, boot-ROM generator, and the Genus power-estimation package generator |
| `sim/` | Testbenches, memory images, expected results, and simulation outputs |
| `firmware/` | RISC-V firmware sources and build |
| `python/` | Notebooks that turn a trained network into the hardware configuration of a new application |
| `emg/`, `flash/` | The example sEMG application and the flash programming files |
| `modifiche_orfs.txt` | Rationale for every local modification to the ORFS flow (see the note under Requirements) |

The complete flow is driven from the top-level `Makefile`: RTL and gate-level
simulation, ORFS setup, and the Genus power-estimation package.

## Requirements

Different tools are used for the front-end (simulation) and the back-end
(synthesis, place & route) steps:

- **RISC-V cross-compiler** (`riscv32-unknown-elf-`) — required to build the firmware. If your system does not already include it, refer to the [riscv-gnu-toolchain page](https://github.com/riscv-collab/riscv-gnu-toolchain).

- **Simulation** — tested with the **oss-cad-suite (2023-07-28)**, which provides the `iverilog`/`vvp` tools. It can be downloaded [here](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2023-07-28).

- **Synthesis** — performed with **Yosys 0.52+50** (git sha1 `c894685f2`), as bundled in the **oss-cad-suite (2025-04-16)**.

- **Floorplanning, placement, and routing** — performed with **OpenROAD 2.0-17598-ga008522d8** (Ubuntu 20.04).

- **Back-end flow** — driven by **OpenROAD Flow Scripts**, tag **`v3.0-2835-geec75094`** (HEAD `eec75094`, 15 April 2025).

- **Power estimation** — performed with **Cadence Genus(TM) Synthesis Solution 18.10-p003_1**, launched in legacy UI mode (`genus -legacy_ui`).

### Local modifications to OpenROAD Flow Scripts

Everything that belongs to the *design* lives in `orfs_setup/` and is linked
into the ORFS tree by `make setup_orfs`. Four things, however, had to be changed
inside the ORFS checkout itself, because they belong to the platform and not to
the design — they do not appear anywhere in this repository, and a clean
checkout will not reproduce the results without them.

**1. `flow/platforms/ihp-sg13g2/setRC.tcl`** — two blocks appended at the end,
both guarded by `if {[info exists ::env(...)]}`, so every other design on this
platform keeps its behaviour and its earlier runs stay comparable:

```tcl
# lets the design override the pre-route parasitics reference layer
if {[info exists ::env(SIGNAL_WIRE_RC_LAYER)] && $::env(SIGNAL_WIRE_RC_LAYER) ne ""} {
  puts "setRC: signal wire RC layer overridden to $::env(SIGNAL_WIRE_RC_LAYER)"
  set_wire_rc -signal -layer $::env(SIGNAL_WIRE_RC_LAYER)
}

# lets the design override the resizer helper procs of scripts/util.tcl
if {[info exists ::env(REPAIR_HELPERS_TCL)] && $::env(REPAIR_HELPERS_TCL) ne ""} {
  source $::env(REPAIR_HELPERS_TCL)
}
```

The first block is what makes `SIGNAL_WIRE_RC_LAYER = Metal3` in `config_soc.mk`
have any effect. The platform default is Metal2, and that is **not a physical
constant**: the header of `setRC.tcl` says the values come from `correlateRC.py`
correlated against gcd, ibex, aes, jpeg, chameleon and riscv32i — all
standard-cell designs. The fit does not transfer to a floorplan that is 86 %
macro by area, where nets detour around the blocks and climb to the upper
layers. Measured on this design, the routed wire splits **44 % Metal2 / 38 %
Metal3 / 17 % Metal4**, a weighted 0.117 fF/µm against the 0.0181 fF/µm that
Metal2 implies: the pre-route estimate was 6.4× optimistic before detour length
was even counted. That is why the design looked clean up to CTS and came apart
at global route. Metal3 makes the estimate represent the real mix.

The second block is the only way to reach `scripts/resize.tcl`, which has no
hook of its own — see [ASIC flow](#asic-flow) for what is done with it.

> The Metal3 switch is the most invasive of these changes: the resizer finds far
> more violations already at `3_4` and inserts far more buffers before final
> placement. If global placement or detailed route start complaining about
> density, this is the first lever to release — not `MAX_WIRE_LENGTH`.

**2. `flow/platforms/ihp-sg13g2/lib/RM_IHPSG13_1P_*.lib`** — 30 files in which
the `max_capacitance` of the single-port SRAM pins is written in farad
(`6.4e-14`) instead of pF (`0.064`), which is what the rest of the library and
the dual-port macros already use.

**3 and 4. Two lines commented out**, both cosmetic — they only affect what is
printed, not what is built:

- `flow/scripts/open.tcl` — the line setting the GUI title:
  ```tcl
  #gui::set_title "OpenROAD - $::env(PLATFORM)/$::env(DESIGN_NICKNAME)/$::env(FLOW_VARIANT) - ${db_basename}"
  ```
- `flow/scripts/write_ref_sdc.tcl` — the final endpoint-count info message:
  ```tcl
  #utl::info "FLW" 11 "Path endpoint path count [sta::endpoint_path_count]"
  ```

### Machine-specific settings

The tool paths are written for the machine the flow was developed on, so a few
of them have to be pointed at your own installation before anything back-end
runs. The simulation flow needs only the RISC-V toolchain prefix.

| Where | Variable | Default | What it is |
|---|---|---|---|
| `firmware/Makefile:1` | `TOOLCHAIN_PREFIX` | `/opt/riscv32/bin/riscv32-unknown-elf-` | RISC-V cross-compiler used to build the firmware |
| `scripts/gen_rom_boot.py:16` | `TOOL` | same as above | the boot ROM is assembled with the same toolchain — keep the two in sync |
| `Makefile:43` | `OPENROAD_PATH` | `/home/luca/OpenROAD-flow-scripts_new` | root of the OpenROAD Flow Scripts checkout |
| `Makefile:44` | `PLATFORM` | `ihp-sg13g2` | ORFS platform name |
| `Makefile:77` | `ORFS_RESULTS` | `$(OPENROAD_PATH)/flow/results/ihp-sg13g2/SYNtzulu_Conv` | where ORFS writes the results; the gate-level simulation targets take the netlists from here |
| `scripts/gen_genus_power.py:40-41` | `ORFS_RESULTS`, `PLATFORM_LIB` | same tree | results and `.lib` directories used to assemble the Genus package; these two are constants in the script, with no command-line override |

Everything in the `Makefile` is a `?=` assignment, so it can also be overridden
per invocation without editing anything:
```
make simulate_post_layout VARIANT=5 OPENROAD_PATH=/path/to/OpenROAD-flow-scripts
```
`VARIANT` deliberately has **no** default: it selects which ORFS run the
netlists come from, and silently simulating an old variant produces wrong
results without any error. The targets that need it stop and list the available
variants if it is missing.

The only machine-dependent file the flow generates is `orfs_setup/paths.mk`
(the absolute path of `rtl/`), written by:
```
make setup_orfs
```
which also creates the `designs/$(PLATFORM)/SYNtzulu-Conv` symlink inside the
ORFS tree that `config_soc.mk` expects. It is generated, never committed.

The lab scripts in `orfs_setup/` carry absolute paths too — they are debugging
aids run by hand, not part of the flow. `sta_corners.tcl` reads `ORFS_FLOW`,
`VARIANT` and `CORNER` from the environment and only falls back to the hardcoded
path; `pdn_lab.tcl` and `check_pdn.tcl` have theirs at the top of the file and
are meant to be edited before use.

# SYNtzulu's flow

To introduce you to SYNtzulu, we have prepared a demo that showcases its capabilities. The demo involves continuous force decoding from 4 8x8 patches of electrode sampling sEMG signal. The biosignal is event-encoded using the delta modulation algorithm and the patches are organised in a 16x16 shape. Consequently, the network has 2x16x16 input channels (each sEMG channel is mapped into two spiking channels) and 5 output channels (one for each finger). The network consists of 2 dense layers, a pooling layer, a convolutional layer, and a final dense layer.

The application, named "emg", is already installed. 
If you wish to create your own application you can go through the four Python Notebook located in the Python folder. As a result, you will obtain a folder named according to your application containing all the hardware configuration file needed to run it in hardware.

## Application files on the ASIC target

The same applies here: the notebooks are untouched and still produce the very
same `<app>/` folder. What changes is what happens to those files afterwards.
Previously, weights, delta thresholds and SNN instructions were written into the
memories at build time, and the flash only had to hold the sensor samples. An
ASIC has no such initialization: at power-up every memory holds an unknown
value, and the only way in is the SPI flash the CPU reads at boot. The
application files are therefore rearranged, by two Python scripts in `scripts/`,
into the two things the chip really boots from — a single flash image and an
on-chip boot ROM.

Nothing of this has to be run by hand: the two scripts are part of every
`simulate` target, and are re-run on each simulation because both depend on the
firmware, which is rebuilt first. Installing an application is the only one-off
step.

```
python/*.ipynb ──> <app>/
                     │
                     │   once, when a new application is added:
                     ├── make create_application_BRAM ──> rtl/config/<app>/       sim/target/<app>/
                     │                                    firmware/src/applications/<app>/   flash/src/<app>/
                     │
                     │   on every "make simulate" (and simulate_post_syn / simulate_post_layout):
                     ├── cd firmware && make -B ────────> firmware/exe.hex ─┐
                     ├── scripts/gen_rom_boot.py <───────────────────────────┤
                     │        └──────────────────────> rtl/memorie_ihp/rom_boot.v ──> boot ROM inside the SoC
                     └── scripts/build_flash_asic.py <───────────────────────┘
                              └─────────────────────> sim/mem/<app>/ASIC_flash.txt ──> spiflash model (sim/tb/flash_spi_sim.sv)
```

Both scripts also read `firmware/exe.hex`, which is why they run after the
firmware build: the boot ROM embeds the number of words to transfer, and the
flash image embeds the firmware itself.

### Installing an application

```
make create_application_BRAM app=emg
```
Replace *emg* with the name of your application folder, after copying it into
the root of SYNtzulu-Conv. This distributes the notebook output to the paths the
RTL and the testbench expect, and rebuilds the firmware:

| From `<app>/` | To | Used by |
|---|---|---|
| `config.txt` | `rtl/config/<app>/` | included at compile time through `` `CONFIG_PATH `` (`rtl/define.v`): SNN sizing (`DW`, `INPUT_CHANNELS`, `N_OUTPUTS`, `TIME_STEPS`, …) |
| `constants.h` | `firmware/src/applications/<app>/` | firmware (`WEIGHT_DEPTH`, `CHANNELS`, `SAMPLE_ADDR`) |
| `snn_inference.txt` | `sim/target/<app>/` | golden reference the testbench checks every SNN output against |
| `spike_vec.txt` | `sim/target/<app>/` | reference of the event encoding; the check that reads it is currently commented out in the testbench |
| `delta_concat.hex` | `sim/mem/<app>/` | legacy delta memory image, kept for reference: on this branch the delta parameters come from the flash image |
| `weights_N_M.hex`, `samples.txt`, `instruction.hex`, `address.txt` | `flash/src/<app>/` | per-file sources for writing a physical flash (`flash/flash_program.sh`) |

The same target also compiles the firmware and calls `build_flash_asic.py`, so a
freshly installed application already has its flash image.

`rtl/define.v` selects which application is compiled: `` `define EMG `` sets
`` `PATH `` and `` `CONFIG_PATH ``, which both the RTL and the testbench use to
build every other path. Note that the target is `create_application_BRAM`, not
`create_application`: the latter is the older naming and expects file
names that notebook 4 no longer produces.

### `build_flash_asic.py` — the flash image

`python3 scripts/build_flash_asic.py <app>` reads the notebook output and packs
it, together with the freshly compiled firmware, into one contiguous image
written to `<app>/ASIC_flash.txt` and `sim/mem/<app>/ASIC_flash.txt`. This is the
file the simulated SPI flash is loaded with, and its layout is the address map
the firmware and the boot ROM are compiled against (base address `0x100000`):

| Address | Size | Content |
|---|---|---|
| `0x100000` | 128000 B | sensor samples (from `flash.txt`) |
| `0x11F400` | 6144 B | 4 weight banks — bank *N* = `weights_N_1..3.hex` concatenated, 768 16-bit words, high byte first |
| `0x120C00` | 512 B | delta modulation: high byte = threshold (`delta.hex`), low byte = initial reference (`delta_ref_init.hex`) |
| `0x120E00` | 512 B (fixed slot) | SNN instructions (`instruction.hex`), zero padded so that the firmware address stays fixed |
| `0x121000` | rest | CPU firmware (`firmware/exe.hex`), 32-bit words, MSB first |

The two "historical" transformations that used to be done elsewhere — splitting
the weights into banks and concatenating the delta files — are encapsulated
here, so the notebooks do not have to know about the ASIC.

### `gen_rom_boot.py` — the boot ROM

`python3 scripts/gen_rom_boot.py` assembles a short RISC-V routine and emits it
as `rtl/memorie_ihp/rom_boot.v`, the ROM the CPU executes from `0x8000_0000`
after reset. The routine programs the SPI master to copy the firmware from
`0x121000` into the CPU RAM, polls for completion, and jumps to it; the SNN
weights and instructions are then loaded by the firmware itself over the same
interface. Because the transfer size is taken from `firmware/exe.hex`, **the ROM
must be regenerated after every firmware build** — `make simulate` and the two
gate-level targets do it automatically.

## Environment setup

See [Requirements](#requirements) for the tool versions. After downloading and
extracting the oss-cad-suite archive, prepare the simulation environment by
running:
```
source oss_cad_suite/environment
```
A RISC-V cross-compiler is also needed to build the firmware; if your system
does not already provide one:
```
git clone https://github.com/riscv/riscv-gnu-toolchain --recursive
cd riscv-gnu-toolchain/
./configure --prefix=/opt/riscv --with-arch=rv32i --with-abi=ilp32
sudo make
```

## Simulation

To start the simulation, execute:
```
make simulate
```
This process may take a few minutes. If the delta modulation and inference
results are correct, the inference results will appear in the terminal. If there
are mismatches between simulated and expected results, the errors will be
reported in the terminal.

The target rebuilds the firmware, regenerates the boot ROM and the flash image,
compiles the whole RTL together with the testbench, runs it, and finally opens
the waveform in GTKWave:

```
cd firmware && make -B                        # firmware/exe.hex
python3 scripts/gen_rom_boot.py               # rtl/memorie_ihp/rom_boot.v
python3 scripts/build_flash_asic.py emg       # sim/mem/emg/ASIC_flash.txt
iverilog -DFUNCTIONAL -o rtl_sim  rtl/define.v sim/tb/* rtl/servant/* rtl/serv/* \
         rtl/syntzulu/* rtl/memorie_ihp/* rtl/behavioural_ihp/* std_cells/*
vvp rtl_sim $(SIMFLAGS)
```

Everything the run needs is passed to `vvp` as plusargs, through `SIMFLAGS`:

| Plusarg | Effect |
|---|---|
| `+runtime_ns=N` | simulated time after the buttons are released (default 9 ms). The SPI load of weights and instructions alone takes the first ~6.3 ms, so the power windows need e.g. `make simulate SIMFLAGS="+runtime_ns=25000000"`, which shows 4–5 complete cycles |
| `+nodump` | no VCD. Mandatory on the netlists, where the dump is several GB and dominates the run time |
| `+gatedump` | reduced dump: only the top-level testbench signals plus the whole `clkgen`, enough to look at the clock gating |
| `+gatetrace` | prints every edge of the four signals that decide whether the core sleeps (`gate_arm`, `irq_sync`, `timer_irq`, `clk_en`). RTL only |
| `+window=N` | which occurrence of idle/inference ends up in the power-window summary. Default 2, because the first one still contains the SPI load and is not representative |

Two more compile-time knobs: `-DNO_CLKGATE` disables the clock gating, and the
testbench parameter `MAX_ERRORS` (default 2) can be raised with
`-Pservant_tb.MAX_ERRORS=<n>` to let a run continue past the first mismatches.

### What happens during the run

The simulation reproduces the real power-up sequence of the chip: no memory is
preloaded, and every byte the system needs enters through the SPI flash. In
particular the CPU RAM is *not* initialized from `firmware/exe.hex` — the
`memfile` parameter survives only for port compatibility (`rtl/memorie_ihp/ihp_ram.v`)
— so the boot path below is exercised exactly as it will be on silicon.

**1. Clock, reset and start button.** The testbench drives `i_clk` at 24 MHz
(41.667 ns period) from time 0 and holds `i_rst` for the first 40 ns.
`clk_gen_wb` synchronizes the reset and stretches it for `RESET_LENGTH` = 12
cycles, then produces two clocks: `i_clk`, always on, which feeds the reset
synchronizer, the slow-tick prescaler and the timer, and `o_clk`, the same clock
gated by a real ICG cell, which feeds CPU, memories and peripherals. The
`buttons` input is held at 1 and released at t = 20 µs — the start button the
firmware waits on.

**2. Boot ROM.** SERV starts from `RESET_PC = 0x8000_0000`, i.e. `rom_boot`
(the ROM generated by `gen_rom_boot.py`). The routine programs the SPI master to
copy the firmware from flash address `0x121000` into the CPU RAM (target ID 7),
polls `SPI_VALID`, and jumps to RAM address 0. On the other side of the SPI bus
is the `spiflash` model of `sim/tb/flash_spi_sim.sv`, whose content is
`$readmemh`-ed from **`sim/mem/<app>/ASIC_flash.txt`** — that single file is the
one and only source of everything the chip reads.

**3. Firmware startup.** The firmware (`firmware/src/main.c`) disables the clock
gate and the interrupts, installs the timer ISR, writes the GPIO, and then spins
on the button bits (`while (DEV_READ(SERVANT_GPIO_ADDR) & 0xf0000000)`) until
the testbench releases them. Four bytes (6, 7, 7, 6) go out on the UART as a
start marker; `sim/tb/uart_decoder.v` decodes the line and prints every byte as
`UART RX: …`.

**4. Network parameters over SPI.** Still from the same flash image, the
firmware loads — addresses in `firmware/src/constants.h`, destinations selected
by writing `SPI_SEL_MEM_OUT`:

| What | Flash address | Size | SPI target |
|---|---|---|---|
| weight bank 1…4 | `0x11F400`, `0x11FA00`, `0x120000`, `0x120600` | 768 × 16 bit each | 0…3 |
| delta thresholds `{delta, prev_init}` | `0x120C00` | 256 × 16 bit | 6 |
| SNN instructions | `0x120E00` | 25 × 16 bit | 4 |

Only when all of them are in place does the firmware write `SYNTZULU_BOOT_RST`
= 0, releasing the SNN from reset: the instruction memory can then preload
instruction 0 and the encoding logic is already out of reset when the first
sample arrives.

**5. Sample.** `spi_load_sample()` reads `CHANNELS` = 256 bytes starting at
`SAMPLE_ADDR` = `0x100000` into the input buffer (SPI target 5). The samples
region holds 500 consecutive samples and comes from the `flash.txt` produced by
notebook 4.

**6. Inference.** The delta modulator event-encodes the sample, the SNN runs it
through its layers, and the firmware polls `SYNTZULU_CLASS` until the valid bit
is set, sends the class on the UART, and pulses `SYNTZULU_VALID_RST`.

**7. Sleep.** The firmware arms the timer (`TIME` = 20 slow ticks, one tick every
`SLOW_DIV` = 2400 cycles ≈ 100 µs, so ≈ 2.1 ms), enables the interrupts, and
enters the idle loop, whose only body is `DEV_WRITE(CLOCK_GATE_CTRL, 1)`. That
write arms the gate; `GATE_DELAY` = 64 always-on cycles later — long enough for
the store to retire and for the core to be parked on the next iteration —
`clk_en` drops and `o_clk` stops. The CPU, the SNN and the peripherals freeze;
only the reset synchronizer, the prescaler and the timer keep switching. There
is deliberately no `wfi`: SERV decodes it as a trap, not as a stall.

**8. Wake-up, and the loop.** The timer interrupt is resynchronized into the
always-on domain and forces `clk_en` back to 1 for its whole duration, so the
core reaches a trap boundary safely. The ISR loads the next sample
(`sample_addr += CHANNELS`), runs the inference, sends the result on the UART
and rearms the timer, then returns to the idle loop — which puts the chip back
to sleep. From here on the simulation just repeats step 5 → 8 once per timer
period until the simulated time runs out.

### What the testbench watches

`sim/tb/servant_tb_mnist.v` taps the two SNN currents `p1`/`p2` (the
`comparator_in` of the two layer-1/layer-2 integrators) and, on every valid,
compares them against two consecutive values read from
`sim/target/<app>/snn_inference.txt`, printing every mismatch and stopping the
run after `MAX_ERRORS`. In parallel it delimits the two intervals the power
estimation needs, sampling them on the always-on `i_clk` — on the gated clock
the end of an idle window would never be seen:

- **idle** — from the falling to the rising edge of `clk_en`, i.e. the whole gated window;
- **inference** — from the first `valid_snn` to the moment the class is ready (`acc_snn_valid_mp`, the same bit the firmware polls).

Every occurrence is printed as it closes (`#[IDLE #n …]`, `#[INFERENCE #n …]`),
and occurrence `+window=N` is the one written to file. In the reference run the
inference window lasts ≈ 0.79 ms and the idle window ≈ 1.95 ms.

At the end of the run (or on an early stop) the testbench closes the files,
prints the summary and writes into `sim/results/<app>/`:

- `snn_inference.txt` — the outputs produced by the hardware, in the same format as the target file;
- `label.txt` — the decoded class, when a valid label is available;
- `power_windows.txt` — the four timestamps of the selected windows, the input of `scripts/gen_genus_power.py`. Gate-level runs write `power_windows_ps.txt` (post-synthesis) and `power_windows_pl.txt` (post-layout), so a netlist run never silently overwrites the RTL numbers.

The waveform ends up in `work/tb_serv.vcd` (`ps_tb_serv.vcd` and
`pl_tb_serv.vcd` for the gate-level runs) and is opened with the saved view
`work/serv_waves.gtkw`.

# ASIC flow

The back end runs on OpenROAD Flow Scripts. Nothing of the design lives inside
the ORFS tree: `orfs_setup/` is the complete design directory and is linked into
it, so the flow is reproducible from this repository alone — bar the two ORFS
side patches listed below.

## The files

| File | ORFS hook | What it does |
|---|---|---|
| `soc/config_soc.mk` | `DESIGN_CONFIG` | the whole configuration: RTL file list, SRAM macro LEF/LIB/GDS, die and core area, floorplan, margins, and the hooks below. Every non-obvious value carries its reasoning in a comment |
| `soc/constraint_soc.sdc` | `SDC_FILE` | 24 MHz clock on the `i_clk` pad, `o_flash_sck` declared as a generated clock (÷2, 12 MHz), input transition and output load at the pad boundary, false paths on `buttons`/`led`/`o_txd` |
| `soc/pad_soc.tcl` | `FOOTPRINT_TCL` | pad ring. The signal pads are instantiated by `rtl/servant/soc.v`, so they are only *placed* here; the supply pads carry no logic and are created here with `-master`, together with bondpads and IO fill |
| `soc/placement_soc.cfg` | `MACRO_PLACEMENT` | the 22 SRAM origins, all R0, every coordinate a multiple of 3.36 µm so the macro pins land on the Metal2/Metal3 tracks |
| `soc/pdn_soc.tcl` | `PDN_TCL` | power grid: global connections, core ring in the `PowRingSpace` band, straps, macro rings |
| `check_pdn.tcl` | `POST_PDN_TCL` | runs the PDN connectivity check right after `pdngen` (stage 2_4) instead of at the end of the flow, where stock ORFS does it. A floating supply used to cost a full route before showing up |
| `soc/pad_nets_dont_touch.tcl` | `POST_FLOORPLAN_TCL` | **new** — see below |
| `soc/post_cts_repair.tcl` | `POST_CTS_TCL` | **new** — see below |
| `soc/pre_global_route.tcl` | `PRE_GLOBAL_ROUTE` | **new** — see below |
| `soc/repair_helpers.tcl` | `REPAIR_HELPERS_TCL` | **new** — see below |
| `pdn_lab.tcl`, `sta_corners.tcl` | — | debugging aids, run by hand on a saved ODB |

`modifiche_orfs.txt` documents every one of these changes, the measurements
behind them and the results per variant.

## One-time setup

```
make setup_orfs
```
writes `orfs_setup/paths.mk` (the absolute path of `rtl/`, the only
machine-dependent piece, generated and never committed) and links
`orfs_setup/` into the ORFS tree as
`$(OPENROAD_PATH)/flow/designs/$(PLATFORM)/SYNtzulu-Conv`, which is the path
`config_soc.mk` resolves its own includes against.

The ORFS checkout itself also has to be patched: the two guard blocks appended
to `platforms/ihp-sg13g2/setRC.tcl` — without which `SIGNAL_WIRE_RC_LAYER =
Metal3` and `REPAIR_HELPERS_TCL` in `config_soc.mk` are simply ignored — and the
unit fix in the single-port SRAM `.lib` files. Both are described in
[Local modifications to OpenROAD Flow Scripts](#local-modifications-to-openroad-flow-scripts);
they belong to the platform, so they are not part of `orfs_setup/`.

## Running the flow

```
cd $(OPENROAD_PATH)/flow
make DESIGN_CONFIG=./designs/ihp-sg13g2/SYNtzulu-Conv/soc/config_soc.mk synth
make DESIGN_CONFIG=./designs/ihp-sg13g2/SYNtzulu-Conv/soc/config_soc.mk
```
The first command stops after synthesis, the second runs the flow to the end.
Results land in `results/ihp-sg13g2/SYNtzulu_Conv/$(FLOW_VARIANT)/`, and
`FLOW_VARIANT` is set in `config_soc.mk` (currently 5): bumping it is all that
is needed to keep an old run intact and have the next one land beside it. Do
*not* change `DESIGN_NICKNAME` for that — it forks a whole new tree and loses
the comparison.

### Stage order, and where each script hooks in

| Stage | Output | What runs there |
|---|---|---|
| `1_synth` | `1_synth.v` | yosys on `VERILOG_FILES`; the SRAMs and the IO pads are blackboxed from their LEF/LIB. The clock gates are `sg13g2_lgcp_1`, instantiated by `rtl/servant/syntzulu_icg.v` — *not* the platform's `OPENROAD_CLKGATE`, whose body is always `assign GCK = CK` |
| `2_1_floorplan` | `2_1_floorplan.odb` | `initialize_floorplan`, `make_tracks`, then **`pad_soc.tcl`** builds the pad ring, and **`pad_nets_dont_touch.tcl`** runs at the end of the stage |
| `2_2_floorplan_macro` | `2_2_floorplan_macro.odb` | macros placed from **`placement_soc.cfg`**, plus the `MACRO_PLACE_HALO` blockages |
| `2_3_floorplan_tapcell` | `2_3_floorplan_tapcell.odb` | tapcells and endcaps |
| `2_4_floorplan_pdn` | `2_4_floorplan_pdn.odb` | **`pdn_soc.tcl`**, then **`check_pdn.tcl`** |
| `3_1`…`3_3` | `3_3_place_gp.odb` | IO placement and global placement at `PLACE_DENSITY` 0.60 |
| `3_4_place_resized` | `3_4_place_resized.odb` | `repair_design` #1 — reached through **`repair_helpers.tcl`**, `-max_wire_length 600`. The only repair that runs while the placement can still change |
| `3_5_place_dp` | `3_5_place_dp.odb` | detailed placement |
| `4_1_cts` | `4_1_cts.odb` | clock tree synthesis, then **`post_cts_repair.tcl`**: `repair_design` #2 with `-max_wire_length 600`, followed by `detailed_placement` and `check_placement` |
| `5_1_grt` | `5_1_grt.odb` | **`pre_global_route.tcl`** redefines the helper, then global route runs `repair_design` #3 with `-max_wire_length 1000` |
| `5_2`, `5_3` | `5_route.odb` | detailed route, filler cells |
| `6_*` | `6_final.v`, `.def`, `.gds`, `.spef`, `.sdc` | fill, GDS merge, final reports on RCX-extracted parasitics |

The four new scripts all exist for the same reason, and it is worth stating it
once: **`repair_design` is the only step in the flow that can split a net with
buffers, and that path was dead.** ORFS never passes `-max_wire_length`, so
OpenROAD computes its own default from the die — 23868 µm on a 3230 µm die — and
no net ever qualifies as long. Only driver upsizing was left, which does nothing
for a net whose delay is dominated by its own wire RC. On top of that the
pre-route parasitics were 6.4× optimistic, because ORFS estimates them on
Metal2 — the `SIGNAL_WIRE_RC_LAYER` story in
[Local modifications](#local-modifications-to-openroad-flow-scripts). Between
the two, the design looked clean all the way to CTS and came apart at global
route, with 816 slew violations appearing out of nowhere.

- **`repair_helpers.tcl`** re-enables net splitting at `3_4`. It is sourced from the platform `setRC.tcl` because `scripts/resize.tcl` has no hook of its own.
- **`post_cts_repair.tcl`** does the same after CTS, and then legalizes: without `detailed_placement` the new buffers stay at the resizer's ideal coordinates and global route dies with one `DRT-0073` each. Measured: 621 long wires, 1014 buffers.
- **`pre_global_route.tcl`** is the important one — global route is the only repair that sees parasitics from the real routed topology, and there it was inserting exactly zero buffers. The threshold is 1000 and not 600 because here the length is the real routed one, and every buffer inserted at this point is paid for in detailed-route congestion.
- **`pad_nets_dont_touch.tcl`** is unrelated to slew: once the SDC constrained the flash interface, CTS hold repair started inserting delay cells *between the pad and the chip pin*, leaving a core cell alone to drive the external 4 pF — 16 ns of slew. The flag has to be set on ODB, not in the SDC, because `write_sdc` does not re-emit `set_dont_touch` while the ODB flag survives across stages.

> ⚠️ `repair_helpers.tcl` and `pre_global_route.tcl` are **copies** of the
> `repair_design_helper` proc from `scripts/util.tcl`. If ORFS changes that
> proc, the copies go stale silently — diff them at every update.

## Post-synthesis and post-layout simulation

Both reuse the testbenches of `make simulate`; only the design under test
changes. The RTL of `servant/`, `serv/`, `syntzulu/` and `memorie_ihp/` is
replaced by the netlist, while `rtl/define.v` (the `` `PATH ``/`` `CONFIG_PATH ``
the testbench needs), the behavioural models of the SRAMs — blackboxes in the
netlist — and the IHP standard cells and IO models are still compiled in.

```
make simulate_post_syn    VARIANT=5      # netlist 1_synth.v
make simulate_post_layout VARIANT=5      # netlist 6_final.v
```

`VARIANT` has no default on purpose: simulating the netlist of an old variant
produces no error at all, it just produces wrong results. It happened — a
netlist synthesized six days before the firmware it was being simulated with,
with the UART spitting X and no obvious cause. The targets refuse to start
without it and list the variants available. A netlist from outside the ORFS tree
is passed whole instead, and then `VARIANT` is not needed:

```
make simulate_post_syn    SOC_NETLIST=<path>
make simulate_post_layout SOC_NETLIST_PL=<path>
```

Two mechanisms make the gate-level runs work:

- **`-DPSIM`** switches the testbench over to the netlist. yosys flattens everything into the single module `soc` and turns the hierarchical names into escaped, bit-blasted identifiers, so every probe is rebound one bit at a time; only nets that survive synthesis — i.e. flop outputs — can be probed at all. `p1`/`p2` do survive, so the inference check runs exactly as on RTL, while the label log is disabled. The same define also renames the VCD and the power-window file.
- **`sim/tb/nettype_wire.v`**, passed to iverilog immediately before the post-layout netlist, restores `` `default_nettype wire ``. The testbenches open with `none`, and the directive crosses file boundaries: yosys declares every wire so `1_synth.v` does not notice, but OpenROAD leaves the unconnected `_NC<n>` dummies and the pad-ring supply nets implicit, and elaboration fails without it.

The post-layout netlist also contains tapcells, fill, antenna diodes and the CTS
buffers. Both runs accept the same plusargs as the RTL one; `+nodump` is
effectively mandatory unless the VCD is what you are after, since on the netlist
it grows to several GB and dominates the run time. Outputs are
`work/ps_tb_serv.vcd` / `work/pl_tb_serv.vcd` and
`sim/results/<app>/power_windows_ps.txt` / `_pl.txt`.

## Power estimation

```
make genus_power VARIANT=5
make genus_power VARIANT=5 CORNER=slow
```
`scripts/gen_genus_power.py` assembles a self-contained package in
`work/genus_power_<app>_v<variant>/` (plus a zip): two Genus scripts, one for
the idle window and one for the inference window, the post-layout netlist with
its `.sdc` and `.spef`, the `.lib` files of the chosen corner, and the VCD.

It has two prerequisites, both produced by a **post-layout run without
`+nodump`**: `work/pl_tb_serv.vcd` and `sim/results/<app>/power_windows_pl.txt`,
which is where the two time windows come from. The VCD is several GB, so the zip
takes a few minutes; `GENUS_ARGS=--no-zip` leaves just the tree.

# Citation

If you wish to cite this work, please use the following: 

@ARTICLE{SYNtzuluConv,  
  author={Leone, Gianluca and Mura, Federico and Raffo, Luigi and Meloni, Paolo},  
  title={SYNtzulu-Conv: Enabling Spiking 2D Convolutions for Sensor Data Analysis on Low-Power FPGAs},  
  booktitle={Highly Efficient Accelerators & Reconfigurable Technologies (HEART 2026)}, 
  year={2026}
  doi={} }

# Acknowledgments

We would like to thank the following repositories and authors for providing modules and resources that were invaluable in this project:

- [YosysHQ - Open Source EDA](https://github.com/YosysHQ/oss-cad-suite-build)
- [SERV](https://github.com/olofk/serv/tree/main)
- [BasicUART](https://github.com/STjurny/BasicUART)
- [ice40_power](https://github.com/tinyvision-ai-inc/ice40_power)
- [picorv32](https://github.com/YosysHQ/picorv32)
