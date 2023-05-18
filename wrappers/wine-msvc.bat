@echo off

setlocal EnableDelayedExpansion

%* !WINE_MSVC_ARGS0!!WINE_MSVC_ARGS1!!WINE_MSVC_ARGS2!!WINE_MSVC_ARGS3!!WINE_MSVC_ARGS4!!WINE_MSVC_ARGS5!!WINE_MSVC_ARGS6!!WINE_MSVC_ARGS7!!WINE_MSVC_ARGS8!!WINE_MSVC_ARGS9! >!WINE_MSVC_STDOUT! 2>!WINE_MSVC_STDERR!

REM https://gitlab.kitware.com/cmake/cmake/-/blob/0991023c30ed5b83bcb1446b5bcc9c1eae028835/Source/cmcmd.cxx#L2388
if /I "%~n1"=="mt" (
    if %errorlevel%==1090650113 (exit 187)
)
