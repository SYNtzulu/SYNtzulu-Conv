# snn_lp — Spiking Neural Network low-power accelerator (standalone)

RTL and standalone testbench of the **`snn_lp`** module: a low-power hardware
accelerator for Spiking Neural Networks (SNN). This repository contains the
accelerator core in isolation — no SoC, no encoder, no bus wrapper — together
with a self-contained simulation that streams a spiking input and checks the
membrane potentials against a software reference.

---

## Quick start

It has been tested with the oss_cad_suite (version 2023-07-28), which can be
downloaded [here](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2023-07-28).
After downloading and extracting the archive, prepare the environment by running
the following command:

```bash
source oss_cad_suite/environment
```

To simulate, **the only command you need is `make simulate_snn_lp`**: it
compiles the RTL together with the testbench and runs it. At the end the TB
prints whether the run passed and how many samples were compared against the
reference. Optionally, `make wave` opens the generated waveform (`.vcd`) in
GTKWave.

---

## Dataset

The simulation runs on the **`optical_flow`** dataset, whose data folder is
selected by the `` `PATH `` macro in `rtl/define.v`. The testbench reads every
input file (spike streams, weights, decay/threshold, instructions and the
software reference) from that folder.

> ⚠️ **The code that generates the `optical_flow` folder is not available yet.**
> A pre-built dataset folder is therefore required to run the simulation; the
> generation pipeline will be published later.

---

## Repository layout

The `rtl/` directory contains **only the `snn_lp` module** (and its
sub-modules). Compared to the original core, this version adds support for:

- **Recurrent layers** — a layer can accumulate its own recurrent contribution
  (a dedicated signal moves the weight-memory pointer backward to re-read the
  recurrent weights during accumulation).
- **Non-spiking input on the first layer** — the first layer can accept a
  non-binary (multi-bit) input instead of pure 0/1 spikes.
- **Separate quantization ranges for current and potential** — the synaptic
  current and the membrane potential use different quantization ranges.
- **8-bit membrane-potential quantization** — the potential is quantized to
  8 bits.
- **Per-channel threshold and decay** — each channel has its own threshold and
  decay value (loaded from the `decay_thr_*` memories), instead of a single
  shared value.

```
rtl/
  define.v              # dataset selection + build-time macros
  syntzulu/             # snn_lp and all its sub-modules (RTL)
sim/
  tb/syntzulu_tb_snn_lp.sv   # standalone testbench (instantiates only snn_lp)
Makefile
```

---

## What the simulation models — network architecture

The testbench instantiates **only `snn_lp`** and drives it exactly as the full
system would, so the simulation reproduces the behaviour of the SNN accelerator
running an inference.

**Input.** A spiking feature map of `16 × 16 × 16 = 4096` spikes per frame
(1 bit per spike). The stream is fed two spikes per cycle (`s1`, `s2`), i.e.
`2048` pairs per frame. Inference runs over **`TIME_STEPS = 10`** frames (time
steps): the same neurons are integrated across the 10 frames, so the accelerator
processes the temporal dimension of the SNN.

**Network.** The core is instruction-driven: the layer topology is described by
an **instruction memory** (`instruction.hex`) and executed layer-by-layer on the
same hardware, so a different network is run just by reloading the instructions.
Every neuron follows a **LIF** (Leaky Integrate-and-Fire) dynamic implemented by
the `lif_pipe` / `neuron_lp` pipeline: at each time step the synaptic currents
are integrated into the membrane potential, the potential decays by the
per-channel decay factor, and a spike is emitted when the per-channel threshold
is crossed.

The instructions in this repository implement a **6-layer convolutional SNN, two
of which are recurrent**. In order:

| # | Layer | Type | Notes |
|---|-------|------|-------|
| 1 | Input conv | convolutional | first layer, **non-spiking (multi-bit) input** |
| 2 | Conv | convolutional | **recurrent** |
| 3 | Conv | convolutional | — |
| 4 | Conv | convolutional | **recurrent** |
| 5 | Conv | convolutional | — |
| 6 | Output conv | convolutional | last layer |

A recurrent layer is encoded with **two consecutive instructions** — one for the
feed-forward pass and one for the recurrent-accumulation pass (during which the
weight-memory pointer is moved backward to re-read the recurrent weights) — so
the 8 instruction slots in `instruction.hex` map to these 6 logical layers.

**Verification.** As the inference runs, the testbench dumps the two probed
membrane potentials (`p1`, `p2`) to `inference_out.txt` and compares them
sample-by-sample against the software reference `snn_inference.txt`. Any
mismatch is reported and, at the end, the TB prints **PASSED** or **FAILED**
along with the number of compared samples and errors.

---

## Data files (read from the dataset folder)

| File | Content |
|------|---------|
| `input_even.txt` / `input_odd.txt` | input spike stream (`s1` / `s2`, one bit per row) |
| `weights.txt` | 32-bit weights (layer 1 + layer 2), loaded at runtime via ports |
| `decay_thr_1.txt` / `decay_thr_2.txt` | per-channel decay + threshold, per layer |
| `instruction.hex` | layer topology / instructions (16-bit words) |
| `snn_inference.txt` | software reference for `p1` / `p2` (checked online) |
| `config.txt` | build-time configuration included by the TB |
