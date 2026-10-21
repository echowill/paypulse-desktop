@echo off
setlocal
where g++ >nul 2>nul || (echo Install the MSYS2 UCRT64 GCC toolchain and add its bin folder to PATH. & exit /b 1)
if not exist build mkdir build
g++ -std=c++17 -O2 EngineChecks.cpp -o build\EngineChecks.exe || exit /b 1
build\EngineChecks.exe || exit /b 1
windres --codepage=65001 PayPulse.rc -O coff -o build\resources.o || exit /b 1
g++ -std=c++17 -O2 -static -static-libgcc -static-libstdc++ -municode -mwindows PayPulse.cpp build\resources.o -o build\PayPulse.exe -lgdiplus -lcomctl32 -lshell32 -lole32 -luuid -lgdi32 -luser32 -ladvapi32 -Wl,--nxcompat -Wl,--dynamicbase -s || exit /b 1
echo Built build\PayPulse.exe
