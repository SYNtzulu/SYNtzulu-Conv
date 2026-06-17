#!/usr/bin/env python3
"""
Decodifica il file instruction.hex (5 word da 16 bit per istruzione, 80 bit totali)
e mostra in maniera leggibile il contenuto della simulazione SNN.

Layout dei campi (vedi rtl/syntzulu/instruction_decoder.sv):
    layer_type             = instr[79:78]   (11 -> mappato a 01)
    dense_next             = instr[79]
    kernel_size (CONV)     = instr[77:76]
    neuron (DENSE/common)  = instr[77:71]
    number_input  (CONV)   = instr[75:71] + 1   (codificato come N-1)
    synapses (common)      = instr[70:64]
    stride (CONV)          = instr[70:69]
    number_output (CONV)   = instr[68:64] + 1
    bit_for_spike          = instr[66:64]
    M  (voltage decay)     = instr[63:52]
    reset_recurrency       = instr[51:36]
    next_dim_input_feature = instr[35:32]
    padding (CONV)         = instr[31]
    size_input_feature     = instr[30:27] + 1
    SYNAPSES               = instr[26:19]
    square_dim_out_feature = instr[15:8]
    size_output_feature    = instr[7:4]
    recurrency             = instr[3]
    recurrency_next        = instr[2]
    first_layer_no_spike   = instr[1]
"""

import os
import re
import sys
from contextlib import redirect_stdout


LAYER_NAMES = {
    0b00: "DENSE",
    0b01: "CONV",
    0b10: "POOLING",
    0b11: "CONV (dense_next=1)",
}


def bits(value: int, hi: int, lo: int) -> int:
    width = hi - lo + 1
    return (value >> lo) & ((1 << width) - 1)


def read_instructions(path: str):
    instrs = []
    words = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            words.append(int(line, 16) & 0xFFFF)
    if len(words) % 5 != 0:
        print(
            f"[warn] {path}: {len(words)} word ({len(words) % 5} in eccedenza),"
            " l'ultima istruzione e' incompleta",
            file=sys.stderr,
        )
    for i in range(0, len(words) - len(words) % 5, 5):
        w = words[i : i + 5]
        instr = 0
        for j, word in enumerate(w):
            instr |= word << (16 * (4 - j))
        instrs.append((w, instr))
    return instrs


def decode(instr: int) -> dict:
    raw_lt = bits(instr, 79, 78)
    layer_type = 0b01 if raw_lt == 0b11 else raw_lt
    return {
        "raw_layer_type": raw_lt,
        "layer_type": layer_type,
        "layer_name": LAYER_NAMES[raw_lt],
        "dense_next": bits(instr, 79, 79),
        # DENSE / common
        "neuron": bits(instr, 77, 71),
        "synapses": bits(instr, 70, 64),
        # CONV
        "kernel_size": bits(instr, 77, 76),
        # number_input_feature: in flash e' codificato come (N-1),
        # quindi per ottenere il numero reale di feature in ingresso aggiungiamo 1.
        "number_input_feature": bits(instr, 75, 71) + 1,
        "stride": bits(instr, 70, 69),
        "number_output_feature": bits(instr, 68, 64) + 1,
        # comuni
        "bit_for_spike": bits(instr, 66, 64),
        "M_voltage_decay": bits(instr, 63, 52),
        "reset_recurrency": bits(instr, 51, 36),
        "next_dim_input_feature": bits(instr, 35, 32),
        "padding": bits(instr, 31, 31),
        "size_input_feature": bits(instr, 30, 27) + 1,
        "SYNAPSES": bits(instr, 26, 19),
        "square_dim_output_feature": bits(instr, 15, 8),
        "size_output_feature": bits(instr, 7, 4),
        "recurrency": bits(instr, 3, 3),
        "recurrency_next": bits(instr, 2, 2),
        "first_layer_no_spike": bits(instr, 1, 1),
    }


def fmt_yes_no(v: int) -> str:
    return "YES" if v else "NO"


def parse_config_txt(path: str) -> dict:
    out = {}
    if not os.path.isfile(path):
        return out
    pattern = re.compile(r"`define\s+(\w+)\s+(\S+)")
    with open(path) as f:
        for line in f:
            m = pattern.search(line)
            if m:
                out[m.group(1)] = m.group(2)
    return out


def parse_constants_h(path: str) -> dict:
    out = {}
    if not os.path.isfile(path):
        return out
    pattern = re.compile(r"#define\s+(\w+)\s+(.+)")
    with open(path) as f:
        for line in f:
            m = pattern.search(line.strip())
            if m:
                out[m.group(1)] = m.group(2).strip()
    return out


def print_header(app_name: str, instr_path: str, config: dict, consts: dict):
    bar = "=" * 70
    print(bar)
    print(f"  SIMULAZIONE: {app_name}")
    print(f"  instruction file: {instr_path}")
    print(bar)
    if config:
        print("Config RTL (config.txt):")
        for k, v in config.items():
            print(f"  {k:<20s} = {v}")
    if consts:
        print("Costanti firmware (constants.h):")
        for k, v in consts.items():
            print(f"  {k:<20s} = {v}")
    print(bar)


def print_instruction(idx: int, words, instr_int: int, d: dict):
    raw_hex = " ".join(f"{w:04X}" for w in words)
    print(f"\n=== Instruction {idx} ===")
    print(f"raw words   : {raw_hex}")
    print(f"raw 80-bit  : 0x{instr_int:020X}")
    print(f"layer_type  : {d['raw_layer_type']:02b}  ({d['layer_name']})")
    print(f"dense_next  : {d['dense_next']}")

    if d["layer_type"] == 0b01:
        print("--- CONV fields ---")
        print(f"  kernel_size            = {d['kernel_size']}  "
              f"(code: 2'b{d['kernel_size']:02b})")
        print(f"  number_input_feature   = {d['number_input_feature']}")
        print(f"  number_output_feature  = {d['number_output_feature']}")
        print(f"  stride                 = {d['stride']}")
        print(f"  padding                = {fmt_yes_no(d['padding'])}")
        print(f"  size_input_feature     = {d['size_input_feature']}")
        print(f"  size_output_feature    = {d['size_output_feature']}")
        print(f"  square_dim_out_feature = {d['square_dim_output_feature']}")
    elif d["layer_type"] == 0b00:
        print("--- DENSE fields ---")
        print(f"  neuron                 = {d['neuron']}")
        print(f"  synapses               = {d['synapses']}")
    elif d["layer_type"] == 0b10:
        print("--- POOLING fields ---")
        print(f"  neuron                 = {d['neuron']}")
        print(f"  size_input_feature     = {d['size_input_feature']}")
        print(f"  size_output_feature    = {d['size_output_feature']}")
        print(f"  square_dim_out_feature = {d['square_dim_output_feature']}")

    print("--- common fields ---")
    print(f"  bit_for_spike          = {d['bit_for_spike']}")
    print(f"  M (voltage decay)      = {d['M_voltage_decay']}")
    print(f"  reset_recurrency       = {d['reset_recurrency']} "
          f"(0x{d['reset_recurrency']:04X})")
    print(f"  next_dim_input_feature = {d['next_dim_input_feature']}")
    print(f"  SYNAPSES (instr field) = {d['SYNAPSES']}")
    print(f"  recurrency             = {fmt_yes_no(d['recurrency'])}")
    print(f"  recurrency_next        = {fmt_yes_no(d['recurrency_next'])}")
    print(f"  first_layer_no_spike   = {fmt_yes_no(d['first_layer_no_spike'])}")


def short_label(d: dict) -> str:
    """Etichetta compatta per GTKWave: tipo di layer + variante recurrency
    + numero input/output feature.
    - CONV         -> recurrency = 0 e recurrency_next = 0
    - CONV_REC_FF  -> recurrency_next = 1 (il layer successivo e' ricorrente)
    - CONV_REC     -> recurrency = 1 (questo layer e' ricorrente)
    Analogo per DENSE / POOL.
    """
    lt = d["layer_type"]
    if lt == 0b01:
        base = "CONV"
    elif lt == 0b00:
        base = "DENSE"
    elif lt == 0b10:
        base = "POOL"
    else:
        base = "UNK"

    if d["recurrency"]:
        base = f"{base}_REC"
    elif d["recurrency_next"]:
        base = f"{base}_REC_FF"

    return f"{base} {d['number_input_feature']}->{d['number_output_feature']}"


def write_gtkwave_filter(path: str, instrs):
    """Genera un translate filter file per GTKWave.
    Format: `<hex_value_uppercase_no_prefix> <label>` una mappa per riga.
    GTKWave per i bus larghi mostra il valore in hex senza prefisso; questo
    filter file va caricato sul segnale `instruction` via
    tasto destro -> Data Format -> Translate Filter File -> Enable and Select.
    """
    seen = set()
    with open(path, "w") as f:
        for _words, instr_int in instrs:
            hex_val = f"{instr_int:020X}"
            if hex_val in seen:
                continue
            seen.add(hex_val)
            label = short_label(decode(instr_int))
            f.write(f"{hex_val} {label}\n")


def emit(app, instr_path, config, consts, instrs):
    print_header(app, instr_path, config, consts)
    if not instrs:
        print("(nessuna istruzione trovata)")
        return
    layer_counts = {0: 0, 1: 0, 2: 0}
    for idx, (words, instr_int) in enumerate(instrs, start=1):
        d = decode(instr_int)
        print_instruction(idx, words, instr_int, d)
        layer_counts[d["layer_type"]] += 1
    print("\n" + "=" * 70)
    print(f"Totale istruzioni: {len(instrs)}")
    print(f"  CONV    : {layer_counts[0b01]}")
    print(f"  DENSE   : {layer_counts[0b00]}")
    print(f"  POOLING : {layer_counts[0b10]}")
    print("=" * 70)


def main():
    if len(sys.argv) < 2:
        print(
            "Usage: describe_simulation.py <app_name> [instruction.hex] "
            "[config.txt] [constants.h] [output_file]",
            file=sys.stderr,
        )
        sys.exit(1)

    # Il Makefile sta nella directory padre della cartella python/
    makefile_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    app = sys.argv[1]
    instr_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        makefile_dir, f"flash/src/{app}/instruction.hex"
    )
    config_path = sys.argv[3] if len(sys.argv) > 3 else os.path.join(
        makefile_dir, f"rtl/config/{app}/config.txt"
    )
    consts_path = sys.argv[4] if len(sys.argv) > 4 else os.path.join(
        makefile_dir, f"firmware/src/applications/{app}/constants.h"
    )
    output_path = sys.argv[5] if len(sys.argv) > 5 else os.path.join(
        makefile_dir, f"simulation_{app}.txt"
    )
    filter_path = os.path.join(makefile_dir, f"instruction_{app}.gtkwf")

    if not os.path.isfile(instr_path):
        print(f"[error] file non trovato: {instr_path}", file=sys.stderr)
        sys.exit(2)

    config = parse_config_txt(config_path)
    consts = parse_constants_h(consts_path)
    instrs = read_instructions(instr_path)

    # stampa a schermo
    emit(app, instr_path, config, consts, instrs)

    # e scrive lo stesso contenuto nel file nella cartella del Makefile
    with open(output_path, "w") as f, redirect_stdout(f):
        emit(app, instr_path, config, consts, instrs)
    print(f"\n[describe_simulation] scritto: {output_path}")

    # filter file per GTKWave: in GTKWave fai tasto destro sul segnale
    # `instruction` -> Data Format -> Translate Filter File -> Enable and Select
    # e seleziona questo file.
    write_gtkwave_filter(filter_path, instrs)
    print(f"[describe_simulation] GTKWave filter: {filter_path}")


if __name__ == "__main__":
    main()
