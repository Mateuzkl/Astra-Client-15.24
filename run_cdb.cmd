@echo off
set CDB="C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2603.20001.0_x64__8wekyb3d8bbwe\amd64\cdb.exe"
set EXE="c:\Users\joaoc\KoliseuOT\AstraClient\AstraClient_debug_x64.exe"
cd /d "c:\Users\joaoc\KoliseuOT\AstraClient"
rem On the 2nd-chance fault, walk the current thread stack with simple kb (no params),
rem which resolves even when frame parameter unwinding is flaky. .reload first.
%CDB% -g -c "g; .echo ===CRASH===; .reload; kb 100; .echo ===END===; q" %EXE% > "c:\Users\joaoc\KoliseuOT\AstraClient\cdb_crash.txt" 2>&1
