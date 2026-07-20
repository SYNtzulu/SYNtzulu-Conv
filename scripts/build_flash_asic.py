#!/usr/bin/env python3
"""
build_flash_asic.py -- costruisce l'immagine flash per il target ASIC (IHP130)
a partire dai file prodotti dal notebook di deployment FPGA (python/4-deployment.ipynb).

Il notebook NON va toccato: questo script parte dai suoi output (in <app>/) e
ripacchetta il flash aggiungendo pesi e delta al posto giusto, incapsulando anche
le due trasformazioni "storiche" (banchi pesi e concat delta).

Layout risultante (offset 0 = flash addr 0x100000, come da flash_spi_sim.sv):

    [ campioni  128000 B ][ 4 banchi pesi  6144 B ][ delta  512 B ]  = 134656 B
      off 0                 off 128000              off 134144 (DELTA_ADDR)

  - campioni : primi SAMPLES_BYTES byte del flash.txt del notebook (idempotente:
               se il flash e' gia' completo riprende solo la parte campioni).
  - pesi     : banco N = weights_N_1 + weights_N_2 + weights_N_3 (word 16 bit),
               scritti in flash hi-first (byte alto per primo).
  - delta    : parola i = delta.hex[i] (byte alto = soglia) +
               delta_ref_init.hex[i] (byte basso = init prev), hi-first.
               delta_ref_init.hex e' opzionale: se manca il byte basso e' 00
               (viene comunque sovrascritto a runtime).

Uso:  python3 scripts/build_flash_asic.py [app]        (default app = emg)
Output: <app>/ASIC_flash.txt  e  sim/mem/<app>/ASIC_flash.txt
"""
import sys, os

APP           = sys.argv[1] if len(sys.argv) > 1 else "emg"
SIM_DST_DIR   = os.path.join("sim", "mem", APP)

# --- parametri layout (coerenti con firmware/src/constants.h) ---
SAMPLES_BYTES = 128000   # regione campioni
N_BANKS       = 4        # WEIGHT_1..4
BANK_PARTS    = 3        # weights_N_1..3
WEIGHT_DEPTH  = 768      # word per banco (= 3 * 256)


def read_tokens(path):
    with open(path) as f:
        return f.read().split()


def read_hex_lines(path):
    """una voce esadecimale per riga, saltando commenti // e righe vuote."""
    out = []
    with open(path) as f:
        for ln in f:
            ln = ln.strip()
            if ln and not ln.startswith("//"):
                out.append(ln)
    return out


def word_to_bytes_hifirst(w):
    w = w.zfill(4).upper()
    return [w[0:2], w[2:4]]


def main():
    flash = []

    # 1) campioni: primi SAMPLES_BYTES byte del flash.txt del notebook
    base = read_tokens(os.path.join(APP, "flash.txt"))
    if len(base) < SAMPLES_BYTES:
        sys.exit(f"ERR: {APP}/flash.txt ha {len(base)} byte, attesi >= {SAMPLES_BYTES}")
    flash += [t.upper() for t in base[:SAMPLES_BYTES]]

    # 2) pesi: banco N = weights_N_1..3 concatenati, hi-first
    for n in range(1, N_BANKS + 1):
        bank_words = []
        for p in range(1, BANK_PARTS + 1):
            bank_words += read_hex_lines(os.path.join(APP, f"weights_{n}_{p}.hex"))
        if len(bank_words) != WEIGHT_DEPTH:
            sys.exit(f"ERR: banco {n} ha {len(bank_words)} word, attese {WEIGHT_DEPTH}")
        for w in bank_words:
            flash += word_to_bytes_hifirst(w)

    # 3) delta: delta.hex (hi) + delta_ref_init.hex (lo)
    delta = read_hex_lines(os.path.join(APP, "delta.hex"))
    ref_path = os.path.join(APP, "delta_ref_init.hex")
    if os.path.exists(ref_path):
        ref = read_hex_lines(ref_path)
        if len(ref) != len(delta):
            sys.exit(f"ERR: delta.hex ({len(delta)}) e delta_ref_init.hex ({len(ref)}) di lunghezza diversa")
    else:
        ref = ["00"] * len(delta)
    for hi, lo in zip(delta, ref):
        flash += [hi.zfill(2).upper(), lo.zfill(2).upper()]

    # --- scrittura (16 byte per riga) ---
    def write(path):
        with open(path, "w") as f:
            for i in range(0, len(flash), 16):
                f.write(" ".join(flash[i:i + 16]) + "\n")

    os.makedirs(SIM_DST_DIR, exist_ok=True)
    app_out = os.path.join(APP, "ASIC_flash.txt")
    sim_out = os.path.join(SIM_DST_DIR, "ASIC_flash.txt")
    write(app_out)
    write(sim_out)

    print(f"[build_flash_asic] app={APP}  totale {len(flash)} byte")
    print(f"  campioni={SAMPLES_BYTES}  pesi={N_BANKS*WEIGHT_DEPTH*2}  delta={len(delta)*2}")
    print(f"  scritto: {app_out}")
    print(f"  scritto: {sim_out}")


if __name__ == "__main__":
    main()
