##########################################################################
#  IHP SG13G2 pad ring - soc
##########################################################################
# Sourced by ORFS at the floorplan stage (FOOTPRINT_TCL in config_soc.mk),
# right after initialize_floorplan/make_tracks.
#
# The signal pads are NOT created here: soc.v (rtl/servant/soc.v) already
# instantiates them, so the names below must match the RTL instance names
# (pad_i_clk, pad_i_rst, ...). place_pad is only told where to put them.
# The supply pads are the opposite case: they carry no logic and do not exist
# in the netlist, so they are created here with -master.
#
# Geometry (all in um, all measured from the die edge):
#
#   0 .. 70     bondpad ring (place_bondpad, offset -70 in y)
#   70 .. 250   IO row: pad cells are 80 wide x 180 deep
#   250 .. 285  PowRingSpace: the core power ring lives here (pdn_soc.tcl)
#   285 ..      CORE_AREA
#
# So CORE_AREA must be inset by 70+180+35 = 285 on every side, and DIE_AREA
# must be CORE_AREA + 570 in both directions. Change one, change the other.
#
# NOTE: with make_io_sites -offset 70 the bondpads sit at 0..70, i.e. flush
# with the die edge, and no room is left for a seal ring. This mirrors the
# SYNtzulA setup; if a seal ring is required at tapeout, raise the offset to
# 70+seal and grow DIE_AREA accordingly.
##########################################################################

set IO_LENGTH     180 ; # pad depth, die edge -> core
set IO_WIDTH       80 ; # pad width along the row (beachfront)
set IO_OFFSET      70 ; # die edge -> IO row (the bondpad band)
set CORNER_SIZE   180 ; # sg13g2_Corner is 180 x 180

make_io_sites -horizontal_site sg13g2_ioSite \
    -vertical_site       sg13g2_ioSite \
    -corner_site         sg13g2_ioSite \
    -offset              $IO_OFFSET \
    -rotation_horizontal R0 \
    -rotation_vertical   R0 \
    -rotation_corner     R0

set DIE_W [expr {[lindex $::env(DIE_AREA) 2] - [lindex $::env(DIE_AREA) 0]}]
set DIE_H [expr {[lindex $::env(DIE_AREA) 3] - [lindex $::env(DIE_AREA) 1]}]

##########################################################################
#  Even spreading over one side
##########################################################################
# The usable beachfront of a side runs from the end of one corner cell to the
# start of the other one; the pads are spread uniformly over it and the gaps
# are closed later by place_io_fill. Spreading (instead of packing the pads
# next to each other) keeps the supply pads distributed around the ring, which
# is what the core power ring wants: add_pdn_ring -connect_to_pads picks the
# supply up from the pad cells themselves.
#
# Each element of $pads is an {instance master net} triple. Master and net are
# only used when the instance is NOT in the netlist: the supply pads never are
# (and have no net, they are fed by connect_by_abutment plus the global
# connections in pdn_soc.tcl), and a signal pad may not be either, because
# yosys drops a pad whose core side ends up unused. Today that happens to
# pad_i_rxd: servant.v:388 connects .i_rxd only under `ifdef RICEZIONE, which
# is undefined, so the whole receive chain is optimized away. The pad is
# created here anyway, so the pin stays on the package and the ring does not
# change if RICEZIONE is ever turned on.
#
# Reattaching it to the top level net is not cosmetic, and it is all that is
# needed. ORFS does not run place_pins when FOOTPRINT_TCL is set
# (scripts/io_placement.tcl:6): the BTERMs get their location from
# place_bondpad, through the pad they hang off. A port whose pad is missing
# keeps a null location and the macro placer stops with
#   [ERROR MPL-0002] Floorplan has not been initialized? Pin location error
# Do NOT also call place_io_terminals on these pins: place_bondpad has already
# created the BTERM pin, a second one gives
#   [ERROR DRT-0302] Unsupported multiple pins on bterm i_rxd
# at global route. The list below is only used to report them.
set ::physical_only_pins {}

proc place_row {row length pads {fixed_pitch ""}} {
    global IO_OFFSET IO_LENGTH IO_WIDTH CORNER_SIZE
    set start [expr {$IO_OFFSET + $CORNER_SIZE}]
    set span  [expr {$length - 2*$start}]
    set n     [llength $pads]
    if {$span < $n * $IO_WIDTH} {
        utl::error FLW 100 "row $row: $n pads need [expr {$n*$IO_WIDTH}] um of\
                          beachfront, only $span um available. Grow DIE_AREA."
    }
    if {$fixed_pitch ne ""} {
        # uniform pitch, whole row centred on the side - see PAD_NS_PITCH
        set used [expr {($n-1)*$fixed_pitch + $IO_WIDTH}]
        if {$used > $span} {
            utl::error FLW 103 "row $row: $n pads at pitch $fixed_pitch need\
                                $used um of beachfront, only $span um available."
        }
        set pitch $fixed_pitch
        set base  [expr {$start + ($span - $used)/2.0}]
    } else {
        set pitch [expr {double($span) / $n}]
        set base  [expr {$start + ($pitch - $IO_WIDTH)/2.0}]
    }
    set block [ord::get_db_block]
    set i 0
    foreach p $pads {
        lassign $p inst master net
        # rounded to the um: the io site is 1 um wide, so this is on-grid
        set loc [expr {round($base + $i*$pitch)}]
        if {[$block findInst $inst] ne "NULL"} {
            place_pad -row $row -location $loc $inst
        } else {
            place_pad -row $row -location $loc $inst -master $master
            # a supply pad has no net and needs nothing else: it is fed by
            # connect_by_abutment and the global connections in pdn_soc.tcl
            if {$net ne ""} {
                utl::warn FLW 101 "$inst was dropped by synthesis and is placed\
                                 as a physical only pad: the chip pin $net\
                                 exists but the core side of the pad is not\
                                 connected."
                set dbnet [$block findNet $net]
                if {$dbnet eq "NULL"} {
                    utl::error FLW 102 "no net $net in the netlist for pad $inst."
                }
                odb::dbITerm_connect [[$block findInst $inst] findITerm pad] $dbnet
                lappend ::physical_only_pins ${inst}/pad
            }
        }
        incr i
    }
}

##########################################################################
#  Pad assignment
##########################################################################
# 15 signal pads (soc.v) + 18 supply pads = 33.
#
# Every side gets its own IOVss/IOVdd (3.3 V pad supply) and Vss/Vdd (1.2 V
# core supply) pair, placed at the two ends of the side. The core supply pads
# are what feeds the core ring, the pad supply pads what feeds the ring
# itself; one set per side keeps the IR drop symmetric. South carries a second
# core pair, for the reason explained right below.
#
# Signal grouping:
#   WEST   clock, reset and buttons - the quiet, mostly static inputs, kept
#          away from the switching outputs
#   EAST   the SPI flash port, all four wires on the same side so the board
#          side traces stay short and length matched
#   SOUTH  the UART pair
#   NORTH  the four LEDs
#
# NORTH AND SOUTH MUST STAY THE SAME LENGTH, AND KEEP PAD_NS_PITCH.
#
# The TopMetal2 core straps of pdn_soc.tcl run vertically and therefore end on
# these two rows. A strap landing where a pad hands its supply to the core ring
# does not come out, so each strap PAIR is centred on a pad and straddles it,
# one strap per side. That only works if a single uniform pitch describes both
# rows: with north on 8 pads and south on 6 (i.e. two different pitches) the
# forbidden x intervals interleave, and no pitch/offset whatsoever avoids them
# all - which is why south carries two extra supply pads to reach 8.
#
# pdn_soc.tcl does not repeat these numbers, it measures the placed pads.
set PAD_NS_PITCH 280

place_row IO_WEST $DIE_H {
    {pad_vssio_w      sg13g2_IOPadIOVss}
    {pad_vddio_w      sg13g2_IOPadIOVdd}
    {pad_i_clk        sg13g2_IOPadIn        i_clk}
    {pad_i_rst        sg13g2_IOPadIn        i_rst}
    {pad_buttons_0    sg13g2_IOPadIn        buttons[0]}
    {pad_buttons_1    sg13g2_IOPadIn        buttons[1]}
    {pad_buttons_2    sg13g2_IOPadIn        buttons[2]}
    {pad_vdd_w        sg13g2_IOPadVdd}
    {pad_vss_w        sg13g2_IOPadVss}
}

place_row IO_EAST $DIE_H {
    {pad_vssio_e      sg13g2_IOPadIOVss}
    {pad_vddio_e      sg13g2_IOPadIOVdd}
    {pad_i_flash_miso sg13g2_IOPadIn        i_flash_miso}
    {pad_o_flash_sck  sg13g2_IOPadOut16mA   o_flash_sck}
    {pad_o_flash_ss   sg13g2_IOPadOut16mA   o_flash_ss}
    {pad_o_flash_mosi sg13g2_IOPadOut16mA   o_flash_mosi}
    {pad_vdd_e        sg13g2_IOPadVdd}
    {pad_vss_e        sg13g2_IOPadVss}
}

place_row IO_SOUTH $DIE_W {
    {pad_vssio_s      sg13g2_IOPadIOVss}
    {pad_vddio_s      sg13g2_IOPadIOVdd}
    {pad_vss_s0       sg13g2_IOPadVss}
    {pad_vdd_s0       sg13g2_IOPadVdd}
    {pad_i_rxd        sg13g2_IOPadIn        i_rxd}
    {pad_o_txd        sg13g2_IOPadOut16mA   o_txd}
    {pad_vdd_s1       sg13g2_IOPadVdd}
    {pad_vss_s1       sg13g2_IOPadVss}
} $PAD_NS_PITCH

place_row IO_NORTH $DIE_W {
    {pad_vssio_n      sg13g2_IOPadIOVss}
    {pad_vddio_n      sg13g2_IOPadIOVdd}
    {pad_led_0        sg13g2_IOPadOut16mA   led[0]}
    {pad_led_1        sg13g2_IOPadOut16mA   led[1]}
    {pad_led_2        sg13g2_IOPadOut16mA   led[2]}
    {pad_led_3        sg13g2_IOPadOut16mA   led[3]}
    {pad_vdd_n        sg13g2_IOPadVdd}
    {pad_vss_n        sg13g2_IOPadVss}
} $PAD_NS_PITCH

##########################################################################
#  Corners, filler, abutment, bondpads
##########################################################################
set iocorner sg13g2_Corner
set iofill [list sg13g2_Filler10000 sg13g2_Filler4000 sg13g2_Filler2000 \
                 sg13g2_Filler1000  sg13g2_Filler400  sg13g2_Filler200]

place_corners $iocorner

place_io_fill -row IO_NORTH {*}$iofill
place_io_fill -row IO_SOUTH {*}$iofill
place_io_fill -row IO_WEST  {*}$iofill
place_io_fill -row IO_EAST  {*}$iofill

# The supply nets (vdd/vss/iovdd/iovss) run through every pad and every filler
# cell: this is what ties the whole ring together, and what the supply pads
# created above with -master actually drive.
connect_by_abutment

place_bondpad -bond bondpad_70x70 -offset {5.0 -70.0} pad_*

if {[llength $::physical_only_pins]} {
    utl::report "physical only pads: $::physical_only_pins"
}

remove_io_rows
