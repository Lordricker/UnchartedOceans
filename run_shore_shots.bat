@echo off
cd /d "%~dp0"
"C:\Users\Victus\Documents\GitHub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path uncharted-oceans --resolution 1280x720 --log-file "%~dp0renders\shore_shots_v2\log.txt" --script res://tests/shore_shot.gd -- out=%~dp0renders/shore_shots_v2 sea=2 hour=11
