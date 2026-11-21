@echo off
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -like '*studio.server*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo PeakCut stopped.
timeout /t 2 >nul
