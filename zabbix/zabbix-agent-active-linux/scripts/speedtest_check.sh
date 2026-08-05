#!/bin/bash
# Speedtest via Ookla CLI (speedtest) ou speedtest-cli (python)
# Arg1: metrica (download | upload)

METRIC="${1:-download}"

# Tentar Ookla CLI primeiro, depois speedtest-cli python
if command -v speedtest &>/dev/null; then
    RAW=$(speedtest --format=json 2>/dev/null)
    case "$METRIC" in
        download) echo "$RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d['download']['bandwidth']*8/1000000,2))" 2>/dev/null ;;
        upload)   echo "$RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d['upload']['bandwidth']*8/1000000,2))" 2>/dev/null ;;
    esac
elif command -v speedtest-cli &>/dev/null; then
    case "$METRIC" in
        download) speedtest-cli --simple 2>/dev/null | awk '/Download/ {printf "%.2f\n", $2}' ;;
        upload)   speedtest-cli --simple 2>/dev/null | awk '/Upload/ {printf "%.2f\n", $2}' ;;
    esac
else
    echo "0"
fi
