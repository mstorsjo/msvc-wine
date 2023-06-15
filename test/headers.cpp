// These attributes pick a different implementation within sal.h,
// that include CodeAnalysis/sourceannotations.h in sal.h, checking that
// such paths with originally mixed casing works.
// The attributes based implementation in sal.h doesn't work with clang-cl,
// only with MSVC.
//
// Enabling these codepaths makes Wine print the following messages while
// executing cl.exe:
// 070c:err:winediag:nodrv_CreateWindow Application tried to create a window, but no driver could be loaded.
// 070c:err:winediag:nodrv_CreateWindow L"The explorer process failed to start."
// 070c:err:systray:initialize_systray Could not create tray window
#define _USE_DECLSPECS_FOR_SAL 0
#define _USE_ATTRIBUTES_FOR_SAL 1
#include <windows.h>
#include <sal.h>

#include <GL/gl.h>

// comdef.h can only be included in C++ mode. It includes Ole2.h and OleCtl.h
// which exist with a different casing in the WinSDK.
// This includes MSVC STL headers, which strictly require a very recent
// version of Clang.
#include <comdef.h>
