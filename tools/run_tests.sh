#!/usr/bin/env bash
# Führt alle Tests headless aus. Schlägt fehl, wenn ein Test fehlschlägt ODER ein Skriptfehler auftritt
# (Godot bricht eine Testfunktion bei Laufzeitfehlern sonst still ab).
# Nutzung: tools/run_tests.sh   (GODOT=<pfad> überschreibt den Godot-Pfad)
set -u
GODOT="${GODOT:-/c/Users/phant/Godot/Godot_v4.4.1-stable_win64_console.exe}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import > /dev/null 2>&1
OUT="$("$GODOT" --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd 2>&1)"
CODE=$?
echo "$OUT" | grep -v "^Godot Engine"
if echo "$OUT" | grep -qE "SCRIPT ERROR|Parse Error"; then
	echo "FEHLER: Skriptfehler während der Tests (siehe oben)"
	exit 1
fi
exit $CODE
