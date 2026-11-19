@echo off
rem Runs the wrapped-world and fast-time check in the real game (tests/wrap_fasttime_probe.tscn).
rem The report is written to uncharted-oceans\tests\wrap_fasttime_report.txt and the window closes when it is done.
cd /d "%~dp0"
"C:\Users\Victus\Documents\GitHub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path uncharted-oceans --import
"C:\Users\Victus\Documents\GitHub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path uncharted-oceans --resolution 1280x720 --log-file "%~dp0uncharted-oceans\tests\wrap_fasttime_log.txt" res://tests/wrap_fasttime_probe.tscn
