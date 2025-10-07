#!/bin/bash
# Uso: ./report_stats.sh design.json output/module_stats.txt

if [ $# -lt 2 ]; then
  echo "Uso: $0 <netlist.json> <report.txt>"
  exit 1
fi

JSON="$1"
REPORT="$2"

# Estrai i nomi dei moduli
MODULES=$(yosys -q -p "read_json $JSON; ls" | xargs)

echo "Moduli trovati: $MODULES"

# Reset file report
: > "$REPORT"

# Genera report per ciascun modulo
for mod in $MODULES; do
  echo "=== $mod ===" >> "$REPORT"
  yosys -q -p "read_json $JSON; stat -top $mod -liberty +/ice40/cells.lib" >> "$REPORT"
  echo "" >> "$REPORT"
done

echo "Report salvato in $REPORT"

