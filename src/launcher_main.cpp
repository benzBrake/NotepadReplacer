#include "launcher_core.h"

#include <shellapi.h>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return static_cast<int>(GetLastError());

    int result = 0;
    if (argc >= 2 && argv[1] && argv[1][0] != L'\0') {
        // IFEO supplies an editor executable; file associations supply a document.
        const bool explicit_target = notepad_replacer::IsExplicitTarget(argv[1]);
        std::wstring target;
        DWORD error_code = ERROR_SUCCESS;
        if (explicit_target) {
            target = argv[1];
        } else if (!notepad_replacer::ReadConfiguredTarget(&target)) {
            error_code = ERROR_BAD_CONFIGURATION;
        }
        const auto forwarded = notepad_replacer::BuildForwardedArgs(
            argc, argv, explicit_target ? 2 : 1);
        if (error_code != ERROR_SUCCESS ||
            !notepad_replacer::LaunchTarget(target, forwarded, &error_code)) {
            result = static_cast<int>(error_code ? error_code : ERROR_FUNCTION_FAILED);
            const std::wstring message = error_code == ERROR_BAD_CONFIGURATION
                ? L"The configured editor is missing or invalid. Reinstall NotepadReplacer to select an editor."
                : L"Could not start the editor:\n" + target + L"\n\nWindows error: " +
                      std::to_wstring(result);
            MessageBoxW(nullptr, message.c_str(), L"Notepad Replacer Launcher",
                        MB_OK | MB_ICONERROR);
        }
    }

    LocalFree(argv);
    return result;
}
