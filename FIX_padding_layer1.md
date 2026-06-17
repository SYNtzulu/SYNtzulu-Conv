# Fix padding — primo layer convoluzionale (16x16x16)

## Contesto

Con input 16×16×**2** la convoluzione funzionava; passando a 16×16×**16** il primo
layer convoluzionale produceva risultati errati sui bordi (righe di padding).

Causa: il buffer di lettura della spike memory ha **256 entry** (indirizzo a 8 bit)
e lo stride di indirizzamento per feature map e' fisso `<< 4` (16 slot/feature).
Con 16 canali × 16 righe = **256** il buffer e' saturo, senza alcun gap.

Due bug, finora mascherati perche' leggevano celle non scritte (= 0):

1. **Underflow indirizzo** — su una riga di padding `spike_mem_rd_addr` fa
   `0 + 0 - padding` → underflow → indirizzo 255.
2. **Gate di padding disallineato** — la pipeline di lettura ha latenza 2 cicli,
   ma il gate di azzeramento usava `first_row_padding`/`last_row_padding` non
   ritardati (sfasati di 1 ciclo). Le versioni ritardate erano dichiarate ma
   inutilizzate (dead code).

Con 2 canali l'indirizzo 255 era in memoria non scritta (= 0), quindi i bug si
autocompensavano. Con 16 canali l'indirizzo 255 contiene dati reali → corruzione.
Per lo stesso motivo i layer intermedi (feature map piu' piccole dopo il pooling)
non erano affetti: lasciano gap a zero nel buffer.

## Modifiche applicate

### 1. rtl/syntzulu/spike_mem2.sv — dichiarazione

Aggiunto il registro di ritardo per `last_row_padding`:

```verilog
reg first_row_padding_d, first_row_padding_dd;
reg last_row_padding_d;
```

### 2. rtl/syntzulu/spike_mem2.sv — allineamento del gate

L'always block registra anche `last_row_padding_d`, e il gate di azzeramento di
`spike_mem_out_16` usa le versioni ritardate di 1 ciclo (`_d`), allineate alla
latenza della pipeline di lettura:

```verilog
always @(posedge clk) begin
    if (rst) begin
        first_row_padding_d  <= 0;
        first_row_padding_dd <= 0;
        last_row_padding_d   <= 0;
    end else begin
        first_row_padding_d  <= first_row_padding;
        first_row_padding_dd <= first_row_padding_d;
        last_row_padding_d   <= last_row_padding;
    end
end

// gate:
if (first_row_padding_d || last_row_padding_d)
    spike_mem_out_16 <= 16'b0;
else
    spike_mem_out_16 <= spike_mem_out_bram;
```

Prima: `if (first_row_padding || last_row_padding)` (segnali non ritardati).

### 3. rtl/syntzulu/conv_controll_2.0.sv — clamp dell'underflow

Guardia contro la sottrazione negativa di `spike_mem_rd_addr` (riga ~231):

```verilog
assign spike_mem_rd_addr = (input_feature_cnt_shift + row_sum < padding)
                           ? 13'd0
                           : input_feature_cnt_shift + row_sum - padding;
```

Prima: `assign spike_mem_rd_addr = input_feature_cnt_shift + row_sum - padding;`

## Verifica

Esito: il primo layer con input 16×16×16 e padding ora produce risultati corretti.
A waveform: `spike_mem_out_16` vale `16'h0000` quando `first_row_padding_d` e' alto.
