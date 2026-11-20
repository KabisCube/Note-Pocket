#ifndef RUNNER_WINDOW_PLACEMENT_H_
#define RUNNER_WINDOW_PLACEMENT_H_

#include <windows.h>

// Saves and restores the window's size and position between runs,
// as "left top right bottom" in %LOCALAPPDATA%\NotePocket\window.txt.
void RestoreWindowPlacement(HWND window);
void SaveWindowPlacement(HWND window);

#endif  // RUNNER_WINDOW_PLACEMENT_H_
