#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
OUTPUT="${1:-../dist/windows}"
mkdir -p "$OUTPUT" build
clang++ -std=c++17 -Wall -Wextra -Werror EngineChecks.cpp -o build/engine-checks
build/engine-checks
x86_64-w64-mingw32-windres --codepage=65001 PayPulse.rc -O coff -o build/resources.o
x86_64-w64-mingw32-g++ -std=c++17 -O2 -Wall -Wextra -static -static-libgcc -static-libstdc++ -municode -mwindows PayPulse.cpp build/resources.o -o "$OUTPUT/PayPulse.exe" -lgdiplus -lcomctl32 -lshell32 -lole32 -luuid -lgdi32 -luser32 -ladvapi32 -Wl,--nxcompat -Wl,--dynamicbase -s
x86_64-w64-mingw32-g++ -std=c++17 -O2 -static EngineChecks.cpp -o "$OUTPUT/EngineChecks.exe" -s
x86_64-w64-mingw32-objdump -p "$OUTPUT/PayPulse.exe" > build/pe-inspection.txt
printf 'Built: %s/PayPulse.exe\n' "$OUTPUT"
