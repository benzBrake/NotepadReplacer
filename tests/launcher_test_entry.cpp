#include <windows.h>
#include <string>

int TestMessageBox(HWND, LPCWSTR, LPCWSTR, UINT) { return IDOK; }
#define MessageBoxW TestMessageBox
#define wWinMain LauncherMain
#include "../src/launcher_main.cpp"
#undef wWinMain
#undef MessageBoxW

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command, int show) {
    wchar_t key_path[256]{};
    if (!GetEnvironmentVariableW(L"NOTEPAD_REPLACER_TEST_KEY", key_path, 256)) return 100;
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, key_path, 0, KEY_ALL_ACCESS, &key) != ERROR_SUCCESS) return 101;
    if (RegOverridePredefKey(HKEY_LOCAL_MACHINE, key) != ERROR_SUCCESS) {
        RegCloseKey(key);
        return 102;
    }
    const int result = LauncherMain(instance, previous, command, show);
    RegOverridePredefKey(HKEY_LOCAL_MACHINE, nullptr);
    RegCloseKey(key);
    return result;
}
