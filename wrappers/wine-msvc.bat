@echo off

%* %WINE_MSVC_ARGS% >%WINE_MSVC_STDOUT% 2>%WINE_MSVC_STDERR%

REM https://gitlab.kitware.com/cmake/cmake/-/blob/0991023c30ed5b83bcb1446b5bcc9c1eae028835/Source/cmcmd.cxx#L2388
if /I "%~n1"=="mt" (
    if %errorlevel%==1090650113 (exit 187)
)
