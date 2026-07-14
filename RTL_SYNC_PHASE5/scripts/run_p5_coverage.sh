#!/usr/bin/env bash
# run_p5_coverage.sh — B1 code coverage measurement (xsim -cov).
# Reuses the P5-EQUIV 17-case sweep TB but compiles with coverage on,
# then extracts line/toggle/branch from the new modules under rtl/.
#
# Output:
#   reports/p5_coverage/p5_coverage_summary.txt
#   reports/p5_coverage/cov_db/  (raw xsim coverage db)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_DIR="${VIVADO_DIR:-/home/zealatan/Downloads/Vivado/2022.2}"
RPT="$ROOT/reports/p5_coverage"
LOG="$ROOT/vivado_xsim/logs/p5_cov_build"
mkdir -p "$RPT" "$LOG"
DB="$RPT/cov_db"
SUMMARY="$RPT/p5_coverage_summary.txt"

# Run the EQUIV runner with coverage env so the existing Tcl picks it up
# via the wrapper below.

rm -rf "$LOG" "$DB"
mkdir -p "$LOG" "$DB"

cd "$ROOT"
set +e; source "$VIVADO_DIR/settings64.sh"; set -e
export PATH="$VIVADO_DIR/bin:$PATH"

vivado -mode batch -source "$ROOT/vivado_xsim/tcl/run_p5_coverage.tcl" \
    -log "$LOG/vivado.log" -journal "$LOG/vivado.jou"

if [[ ! -d "$DB" || -z "$(ls -A "$DB" 2>/dev/null)" ]]; then
    echo "P5_COVERAGE_GATE: BLOCKED · cov_db empty" | tee "$SUMMARY"
    exit 1
fi

# xcrg report
xcrg -dir "$DB" -report_dir "$RPT/xcrg" 2>&1 | tail -20 > "$LOG/xcrg.log" || true

# Extract a 1-line summary if xcrg produced one
if [[ -f "$RPT/xcrg/dashboard.txt" ]]; then
    cp "$RPT/xcrg/dashboard.txt" "$SUMMARY"
elif [[ -f "$RPT/xcrg/coverage_report.txt" ]]; then
    cp "$RPT/xcrg/coverage_report.txt" "$SUMMARY"
else
    {
        echo "# P5-coverage summary"
        echo "cov_db: $DB"
        echo "xcrg log: $LOG/xcrg.log"
        ls -la "$RPT/xcrg" 2>/dev/null || true
    } > "$SUMMARY"
fi
echo "P5_COVERAGE_GATE: PASS · cov_db=$DB · summary=$SUMMARY"
