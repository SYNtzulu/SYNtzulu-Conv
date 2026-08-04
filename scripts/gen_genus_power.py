#!/usr/bin/env python3
"""
gen_genus_power.py - prepara il pacchetto per la stima di potenza con Genus.

Mette insieme tutto quello che serve a Genus per fare report_power sulla
netlist post-layout, in un albero autoconsistente + zip:

    genus_power_<app>_v<variante>/
        power_idle.tcl          <- script Genus, finestra di idle
        power_inference.tcl     <- script Genus, finestra di inferenza
        README.txt
        lib/                    <- i .lib del corner scelto, solo quelli che servono
        netlist/                <- 6_final.v / .sdc / .spef
        vcd/                    <- il VCD della simulazione post-layout

Le finestre temporali arrivano da sim/results/<app>/power_windows_pl.txt, che
scrive il testbench durante "make simulate_post_layout".

    python3 scripts/gen_genus_power.py                 # variante 5, app emg
    python3 scripts/gen_genus_power.py --variant 3
    python3 scripts/gen_genus_power.py --no-zip        # solo l'albero

UNITA' DI TEMPO. power_windows_pl.txt e' in NANOSECONDI (il tb stampa con
$realtime e `timescale 1ns/1ps). Il VCD invece ha "$timescale 1ps", e
read_vcd -start_time/-end_time vuole le unita' del VCD. Quindi ns -> ps, x1000.
Sbagliare questo fattore non da' nessun errore: Genus prende una finestra
1000 volte piu' corta e riporta una potenza plausibile ma senza significato.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from decimal import Decimal

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ORFS_RESULTS = "/home/luca/OpenROAD-flow-scripts_new/flow/results/ihp-sg13g2/SYNtzulu_Conv"
PLATFORM_LIB = "/home/luca/OpenROAD-flow-scripts_new/flow/platforms/ihp-sg13g2/lib"

DESIGN_TOP = "soc"        # config_soc.mk: DESIGN_NAME

# Scope del DUT dentro il VCD. Genus vuole il NOME DELL'ISTANZA, non il percorso
# gerarchico completo: col percorso (servant_tb.servant_sim_i.soc_i) non aggancia
# nulla e - senza dare errore - annota lo 0% delle reti, calcolando la potenza su
# attivita' di default. Il sintomo e' che idle e inference danno lo stesso numero.
VCD_SCOPE = "soc_i"

# Corner -> suffisso dei .lib. Le std cell, gli IO e le macro RAM hanno naming
# diverso per tensione, quindi ogni famiglia ha il suo pattern.
CORNERS = {
    "typ":  {"std": "typ_1p20V_25C",   "io": "typ_1p2V_3p3V_25C",   "ram": "typ_1p20V_25C"},
    "slow": {"std": "slow_1p08V_125C", "io": "slow_1p08V_3p0V_125C", "ram": "slow_1p08V_125C"},
    "fast": {"std": "fast_1p32V_m40C", "io": "fast_1p32V_3p6V_m40C", "ram": "fast_1p32V_m55C"},
}


def die(msg):
    print(f"[gen_genus_power] ERRORE: {msg}", file=sys.stderr)
    sys.exit(1)


def read_windows(path):
    """
    power_windows_pl.txt -> dict nome -> nanosecondi come Decimal.

    Decimal e non float di proposito. Il tb stampa con %0.3f, cioe' ns con tre
    decimali = risoluzione al ps, e da qui si arriva agli interi in ps che
    finiscono in read_vcd. Con Decimal la conversione e' esatta per costruzione:
    non c'e' nessun caso in cui un .951 diventi .950999... e poi un ps di
    differenza sull'istante di start. Con questi ordini di grandezza (1e10 ps,
    11 cifre) anche il float basterebbe, ma qui l'esattezza costa zero.
    """
    if not os.path.exists(path):
        die(f"{os.path.relpath(path, REPO)} non esiste.\n"
            f"  Le finestre le scrive il testbench durante la simulazione post-layout:\n"
            f"      make simulate_post_layout SIMFLAGS=\"+runtime_ns=25000000 +nodump\"\n"
            f"  (senza +nodump servono ~4 GB di VCD, ma il VCD qui serve, vedi sotto)")

    w = {}
    for line in open(path):
        parts = line.split()
        if len(parts) == 2:
            w[parts[0]] = Decimal(parts[1])

    for k in ("start_idle", "end_idle", "start_inference", "end_inference"):
        if k not in w:
            die(f"{path}: manca la riga '{k}'")
        # Il tb inizializza a -1 e sovrascrive solo quando la finestra si chiude
        # davvero. Un -1 qui vuol dire che quella finestra non e' mai stata
        # misurata: di solito la simulazione era troppo corta.
        if w[k] < 0:
            die(f"{k} = {w[k]}: finestra mai misurata.\n"
                f"  Allunga la simulazione (+runtime_ns=N) e rifai la post-layout.")

    for a, b in (("start_idle", "end_idle"), ("start_inference", "end_inference")):
        if w[b] <= w[a]:
            die(f"{a}={w[a]} >= {b}={w[b]}: finestra non valida")

    return w


def ns_to_ps(ns):
    """
    ns -> ps INTERI, che sono le unita' del VCD ($timescale 1ps).

    read_vcd non accetta un numero col punto decimale, e comunque un istante
    frazionario non avrebbe senso: il ps e' gia' la risoluzione del dump. Il
    ritorno e' un int, cosi' la f-string che compone lo script non puo'
    reintrodurre un '.' per sbaglio.
    """
    ps = Decimal(ns) * 1000
    if ps != ps.to_integral_value():
        die(f"{ns} ns = {ps} ps non e' intero: il VCD ha risoluzione al ps, "
            f"un istante frazionario non e' rappresentabile")
    return int(ps)


def collect_libs(netlist, corner):
    """
    I .lib li ricavo dalle macro effettivamente istanziate nella netlist, non da
    una lista fissa: se il design cambia memorie, il pacchetto segue da solo.
    Un elenco hardcoded si sarebbe disallineato in silenzio, e Genus su una lib
    mancante si limita a lasciare la cella senza modello di potenza.
    """
    sfx = CORNERS[corner]

    # \w+ GREEDY, e il nome del modulo si prende per intero. Le macro si chiamano
    # RM_IHPSG13_1P_1024x16_c2_bm_bist: una regex che si ancora al "_c<cifra>"
    # taglia via il "_bm_bist" finale e costruisce path di lib inesistenti.
    #
    # Una passata sola sul file, che qui e' da ~21 MB: le macro stanno all'inizio
    # ma i pad del ring stanno in fondo, quindi leggerne solo un pezzo vuol dire
    # perdersi gli IO e restare senza la loro lib.
    macro_re = re.compile(r"^\s*(RM_IHPSG13_\w+)\s")
    pad_re   = re.compile(r"^\s*sg13g2_IOPad\w*\s")

    names, has_pads = set(), False
    with open(netlist) as f:
        for line in f:
            m = macro_re.match(line)
            if m:
                names.add(m.group(1))
            elif pad_re.match(line):
                has_pads = True

    libs = [f"{PLATFORM_LIB}/sg13g2_stdcell_{sfx['std']}.lib"]

    # Gli IO servono: la netlist post-layout include il pad ring (soc.v lo
    # istanzia). Nota che LIB_FILES di ORFS NON contiene la lib degli IO, quindi
    # questa non si puo' derivare dal config del flow.
    if has_pads:
        libs.append(f"{PLATFORM_LIB}/sg13g2_io_{sfx['io']}.lib")

    for macro in sorted(names):
        libs.append(f"{PLATFORM_LIB}/{macro}_{sfx['ram']}.lib")

    missing = [l for l in libs if not os.path.exists(l)]
    if missing:
        die("lib mancanti per il corner '%s':\n  %s" % (corner, "\n  ".join(missing)))

    return libs


def check_freshness(netlist, vcd, windows_file):
    """
    Il modo piu' facile di sbagliare qui e' mescolare pezzi di run diverse: una
    netlist risintetizzata dopo la simulazione, o un VCD di ieri con le finestre
    di oggi. Nessuno dei due da' errore, danno numeri sbagliati. Quindi avviso.
    """
    warn = []
    t_net, t_vcd, t_win = (os.path.getmtime(p) for p in (netlist, vcd, windows_file))

    if t_net > t_vcd:
        warn.append("la netlist e' PIU' RECENTE del VCD: il VCD viene da un'altra "
                    "netlist, gli istanti non corrispondono")
    if abs(t_vcd - t_win) > 3600:
        warn.append("VCD e power_windows_pl.txt distano piu' di un'ora: "
                    "probabilmente sono di due simulazioni diverse")
    return warn


def genus_script(libs, vcd_name, scope, t0_ps, t1_ps, label, win_ns):
    lib_list = " ".join(f"lib/{os.path.basename(l)}" for l in libs)
    return f"""\
# ---------------------------------------------------------------------------
#  report_power - finestra di {label}
#
#  Finestra presa da sim/results/*/power_windows_pl.txt:
#      {win_ns[0]:.3f} ns .. {win_ns[1]:.3f} ns   ({win_ns[1] - win_ns[0]:.3f} ns)
#  convertita nelle unita' del VCD ($timescale 1ps), quindi x1000.
#
#      genus -files power_{label}.tcl
# ---------------------------------------------------------------------------

#  Da incollare al prompt di Genus, dalla directory che contiene lib/ netlist/
#  vcd/ reports/.
# ---------------------------------------------------------------------------

::legacy::set_attribute library {{{lib_list} }} /
::legacy::set_attribute lp_power_unit mW

read_netlist -top {DESIGN_TOP} netlist/6_final.v
read_sdc netlist/6_final.sdc
read_spef netlist/6_final.spef

read_vcd -static -vcd_scope {scope} vcd/{vcd_name} \\
         -start_time {t0_ps} -end_time {t1_ps}

report_power
report_power > reports/power_{label}.rpt
"""


README = """\
Pacchetto per la stima di potenza con Genus - {app}, variante ORFS {variant}, corner {corner}.

    genus -files power_idle.tcl
    genus -files power_inference.tcl

Vanno lanciati dalla radice di questo albero: i path dentro gli script sono
relativi (lib/, netlist/, vcd/).

CONTENUTO
    power_idle.tcl        finestra col clock fermo (gating attivo)
    power_inference.tcl   finestra di inferenza dell'SNN
    lib/                  {nlib} .lib, corner {corner}
    netlist/              6_final.v .sdc .spef  (post detailed route + fill)
    vcd/                  {vcd}
    reports/              vuota: ci finiscono power_idle.rpt e power_inference.rpt

Ogni script stampa report_power a schermo E lo scrive in reports/, cosi' le due
finestre si confrontano dopo senza ripescare lo stdout della sessione.

FINESTRE (da sim/results/{app}/power_windows_pl.txt)
    idle        {si:>16.3f} ns .. {ei:>16.3f} ns    durata {di:>12.3f} ns
    inference   {sf:>16.3f} ns .. {ef:>16.3f} ns    durata {df:>12.3f} ns

    Negli script sono in ps, le unita' del VCD ($timescale 1ps): x1000.

    La finestra di idle e' misurata sui fronti di clk_en, quella di inferenza
    da valid_snn a acc_snn_valid_mp. Il campionamento e' su i_clk e non su
    wb_clk, che durante l'idle e' fermo per definizione.

SCOPE DEL VCD
    {scope}
    E' l'istanza del soc dentro il testbench, cioe' la gerarchia che
    corrisponde al top '{top}' della netlist.
"""


def main():
    ap = argparse.ArgumentParser(description="Prepara il pacchetto Genus per report_power.")
    # Obbligatoria, senza default: puntare alla variante sbagliata non produce
    # un errore ma un pacchetto plausibile e sbagliato.
    ap.add_argument("--variant", required=True, help="variante ORFS (obbligatoria)")
    ap.add_argument("--app", default="emg", help="applicazione (default emg)")
    ap.add_argument("--corner", default="typ", choices=sorted(CORNERS), help="corner dei .lib")
    ap.add_argument("--vcd", default=None, help="VCD post-layout (default work/pl_tb_serv.vcd)")
    # Lo scope e' la cosa piu' facile da sbagliare qui, e sbagliandolo Genus NON
    # da' errore: annota lo 0% delle reti e calcola la potenza su attivita' di
    # default, cioe' due report identici per idle e inference. Parametrico cosi'
    # si prova un'altra forma senza ritoccare i tcl a mano.
    ap.add_argument("--vcd-scope", default=VCD_SCOPE,
                    help=f"scope del DUT dentro il VCD (default {VCD_SCOPE}); "
                         f"se l'annotazione resta a 0%% prova 'servant_sim_i.soc_i' "
                         f"o il percorso completo 'servant_tb.servant_sim_i.soc_i'")
    ap.add_argument("--outdir", default=None, help="dove costruire l'albero (default work/)")
    ap.add_argument("--no-zip", action="store_true", help="non creare lo zip")
    ap.add_argument("--zip-level", default="1", help="compressione zip 1..9 (default 1: i VCD sono enormi)")
    args = ap.parse_args()

    res = os.path.join(ORFS_RESULTS, args.variant)
    netlist = os.path.join(res, "6_final.v")
    sdc     = os.path.join(res, "6_final.sdc")
    spef    = os.path.join(res, "6_final.spef")
    for p in (netlist, sdc, spef):
        if not os.path.exists(p):
            die(f"{p} non esiste: la variante {args.variant} non e' arrivata a 6_final.")

    vcd = args.vcd or os.path.join(REPO, "work", "pl_tb_serv.vcd")
    if not os.path.exists(vcd):
        die(f"{vcd} non esiste.\n"
            f"  Il VCD lo produce 'make simulate_post_layout' SENZA +nodump.")

    win_file = os.path.join(REPO, "sim", "results", args.app, "power_windows_pl.txt")
    w = read_windows(win_file)
    libs = collect_libs(netlist, args.corner)

    warns = check_freshness(netlist, vcd, win_file)

    outdir = args.outdir or os.path.join(REPO, "work")
    stage = os.path.join(outdir, f"genus_power_{args.app}_v{args.variant}")
    if os.path.exists(stage):
        shutil.rmtree(stage)
    # reports/ va creata qui: "report_power > reports/..." non crea la directory
    # da solo e fallirebbe a fine run, cioe' dopo aver gia' speso tutto il tempo.
    for sub in ("lib", "netlist", "vcd", "reports"):
        os.makedirs(os.path.join(stage, sub))

    # Symlink invece di copie: il VCD da solo pesa qualche GB e copiarlo per poi
    # zipparlo vuol dire scriverne due volte. zip di default segue i link e
    # archivia il contenuto, quindi lo zip resta autoconsistente.
    for l in libs:
        os.symlink(l, os.path.join(stage, "lib", os.path.basename(l)))
    for p in (netlist, sdc, spef):
        os.symlink(p, os.path.join(stage, "netlist", os.path.basename(p)))
    os.symlink(os.path.abspath(vcd), os.path.join(stage, "vcd", os.path.basename(vcd)))

    specs = [
        ("idle",      w["start_idle"],      w["end_idle"]),
        ("inference", w["start_inference"], w["end_inference"]),
    ]
    for label, t0, t1 in specs:
        script = genus_script(libs, os.path.basename(vcd), args.vcd_scope,
                              ns_to_ps(t0), ns_to_ps(t1), label, (t0, t1))
        open(os.path.join(stage, f"power_{label}.tcl"), "w").write(script)

    open(os.path.join(stage, "README.txt"), "w").write(README.format(
        app=args.app, variant=args.variant, corner=args.corner, nlib=len(libs),
        vcd=os.path.basename(vcd), scope=args.vcd_scope, top=DESIGN_TOP,
        si=w["start_idle"], ei=w["end_idle"], di=w["end_idle"] - w["start_idle"],
        sf=w["start_inference"], ef=w["end_inference"],
        df=w["end_inference"] - w["start_inference"]))

    print(f"[gen_genus_power] albero: {os.path.relpath(stage, REPO)}")
    print(f"  corner {args.corner}, {len(libs)} lib, top {DESIGN_TOP}, scope {args.vcd_scope}")
    for label, t0, t1 in specs:
        print(f"  {label:<10} {t0:16.3f} .. {t1:16.3f} ns  ->  "
              f"{ns_to_ps(t0)} .. {ns_to_ps(t1)} ps")
    print(f"  VCD {os.path.basename(vcd)}  ({os.path.getsize(vcd) / 2**30:.1f} GiB)")

    for msg in warns:
        print(f"  ATTENZIONE: {msg}")

    if args.no_zip:
        return

    zpath = stage + ".zip"
    if os.path.exists(zpath):
        os.remove(zpath)
    print(f"[gen_genus_power] zip in corso ({os.path.basename(zpath)}), "
          f"col VCD ci vuole qualche minuto...")
    subprocess.run(["zip", f"-{args.zip_level}", "-r", os.path.basename(zpath),
                    os.path.basename(stage)],
                   cwd=outdir, check=True, stdout=subprocess.DEVNULL)
    print(f"[gen_genus_power] {os.path.relpath(zpath, REPO)}  "
          f"({os.path.getsize(zpath) / 2**30:.2f} GiB)")


if __name__ == "__main__":
    main()
