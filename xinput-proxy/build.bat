@echo off
REM Build the XINPUT1_3.dll proxy with MSVC x64
setlocal
set VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat
call "%VCVARS%"
cl /nologo /LD /O2 /EHsc /utf-8 dllmain.cpp /Fe:XINPUT1_3.dll /link /OUT:XINPUT1_3.dll /DEF:exports.def user32.lib
if exist XINPUT1_3.dll (
    echo.
    echo BUILD OK: XINPUT1_3.dll
) else (
    echo.
    echo BUILD FAILED
    exit /b 1
)
endlocal
