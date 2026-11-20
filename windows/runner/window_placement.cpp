#include "window_placement.h"

#include <filesystem>
#include <fstream>

namespace {

const wchar_t kLocalAppDataVariable[] = L"LOCALAPPDATA";
const wchar_t kAppFolderName[] = L"NotePocket";
const wchar_t kPlacementFileName[] = L"window.txt";

std::filesystem::path PlacementFilePath() {
	wchar_t local_app_data[MAX_PATH];
	const DWORD length = GetEnvironmentVariableW(kLocalAppDataVariable, local_app_data, MAX_PATH);
	if (length == 0 || length >= MAX_PATH) {
		return {};
	}
	return std::filesystem::path(local_app_data) / kAppFolderName / kPlacementFileName;
}

}  // namespace

void RestoreWindowPlacement(HWND window) {
	const std::filesystem::path path = PlacementFilePath();
	if (path.empty()) {
		return;
	}
	std::ifstream file(path);
	RECT bounds = {};
	if (!(file >> bounds.left >> bounds.top >> bounds.right >> bounds.bottom)) {
		return;
	}

	WINDOWPLACEMENT placement = {};
	placement.length = sizeof(WINDOWPLACEMENT);
	if (!GetWindowPlacement(window, &placement)) {
		return;
	}
	placement.rcNormalPosition = bounds;
	placement.showCmd = SW_HIDE;
	SetWindowPlacement(window, &placement);
}

void SaveWindowPlacement(HWND window) {
	const std::filesystem::path path = PlacementFilePath();
	WINDOWPLACEMENT placement = {};
	placement.length = sizeof(WINDOWPLACEMENT);
	if (path.empty() || !GetWindowPlacement(window, &placement)) {
		return;
	}

	std::error_code error;
	std::filesystem::create_directories(path.parent_path(), error);
	std::ofstream file(path);
	const RECT& bounds = placement.rcNormalPosition;
	file << bounds.left << ' ' << bounds.top << ' ' << bounds.right << ' ' << bounds.bottom;
}
