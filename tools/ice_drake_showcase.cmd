@echo off
rem Startet eine Spielrunde mit dem Eisdrachen (Doppelklick genuegt). Karte: --map=citadel, Held: --hero=arcanist
start "" "C:\Users\phant\Godot\Godot_v4.4.1-stable_win64.exe" --path "%~dp0.." res://tools/hexer_showcase.tscn -- --enemy=ice_drake
