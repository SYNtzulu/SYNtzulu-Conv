#!/usr/bin/env python3
"""
gen_rom_boot.py -- genera rtl/memorie_ihp/rom_boot.v (boot ROM) dal codice di boot.

Il boot (eseguito dalla CPU dalla ROM a 0x8000_0000):
  1. dice al SPI-slave di leggere il firmware dalla flash (FW_ADDR) e scriverlo
     nella RAM CPU (target ID 7);
  2. attende la fine (poll SPI_VALID);
  3. salta a RAM[0] (jr) -> parte il firmware.

La size del load (FW_WORDS) e' ricavata da firmware/exe.hex, quindi RIGENERARE
la ROM dopo ogni build del firmware:  python3 scripts/gen_rom_boot.py
"""
import os, subprocess, struct

TOOL  = "/opt/riscv32/bin/riscv32-unknown-elf-"
EXE   = "firmware/exe.hex"
ROM_V = "rtl/memorie_ihp/rom_boot.v"

FW_ADDR         = 0x00121000   # offset firmware in flash (dopo delta + slot istruzioni)
RAM_TARGET      = 7            # SPI_SEL_MEM_OUT -> RAM CPU
SPI_ADDR        = 0xA0000000
SPI_SEL_MEM_OUT = 0xA0010000
SPI_READ_SIZE   = 0xA0020000
SPI_START       = 0xA0030000
SPI_VALID       = 0xA0040000


def fw_words():
    with open(EXE) as f:
        return sum(1 for l in f if l.strip())


def boot_asm(fw_bits):
    return f"""
    .section .text
    .globl _start
_start:
    li   t0, {SPI_ADDR}
    li   t1, {FW_ADDR}
    sw   t1, 0(t0)
    li   t0, {SPI_SEL_MEM_OUT}
    li   t1, {RAM_TARGET}
    sw   t1, 0(t0)
    li   t0, {SPI_READ_SIZE}
    li   t1, {fw_bits}
    sw   t1, 0(t0)
    li   t0, {SPI_START}
    li   t1, 1
    sw   t1, 0(t0)
    li   t0, {SPI_VALID}
1:  lw   t1, 0(t0)
    beqz t1, 1b
    li   t0, 0
    jr   t0
"""


def main():
    fw = fw_words()
    fw_bits = fw * 32

    s, o, elf, binf = ("/tmp/boot_rom.s", "/tmp/boot_rom.o",
                       "/tmp/boot_rom.elf", "/tmp/boot_rom.bin")
    open(s, "w").write(boot_asm(fw_bits))
    subprocess.run([TOOL+"as", "-march=rv32i", "-mabi=ilp32", s, "-o", o], check=True)
    subprocess.run([TOOL+"ld", "-Ttext=0x80000000", o, "-o", elf], check=True)
    subprocess.run([TOOL+"objcopy", "-O", "binary", elf, binf], check=True)

    data = open(binf, "rb").read()
    words = [struct.unpack("<I", data[i:i+4])[0] for i in range(0, len(data), 4)]

    body = "\n".join(f"       8'd{i}:{'  ' if i >= 10 else '   '} o_wb_rdt <= 32'h{w:08X};"
                     for i, w in enumerate(words))

    v = f'''`default_nettype none
//////////////////////////////////////////////////////////////////////////////
// rom_boot : boot ROM (Wishbone slave). GENERATA da scripts/gen_rom_boot.py.
// NON modificare a mano: rigenerare dopo ogni build del firmware.
//
// Mappata a ROM_BASE = 0x8000_0000 (RESET_PC). Carica il firmware dalla flash
// SPI (@0x{FW_ADDR:06X}, {fw} word) nella RAM CPU (target SPI ID {RAM_TARGET}), poi salta a RAM[0].
//////////////////////////////////////////////////////////////////////////////
module rom_boot
  (input  wire        i_wb_clk,
   input  wire        i_wb_rst,
   input  wire [31:2] i_wb_adr,
   input  wire        i_wb_cyc,
   output reg  [31:0] o_wb_rdt,
   output reg         o_wb_ack);

   // ack a 1 ciclo, come servant_ram (reset asincrono)
   always @(posedge i_wb_clk or posedge i_wb_rst)
     if (i_wb_rst) o_wb_ack <= 1'b0;
     else          o_wb_ack <= i_wb_cyc & !o_wb_ack;

   wire [7:0] a = i_wb_adr[9:2];

   always @(posedge i_wb_clk)
     case (a)
{body}
       default: o_wb_rdt <= 32'h0000_0013;   // nop
     endcase

endmodule
'''
    open(ROM_V, "w").write(v)
    print(f"[gen_rom_boot] firmware {fw} word ({fw_bits} bit) -> "
          f"{len(words)} istruzioni ROM -> {ROM_V}")


if __name__ == "__main__":
    main()
