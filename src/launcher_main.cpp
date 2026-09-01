#include "launcher_core.h"

#include <shellapi.h>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return static_cast<int>(GetLastError());

    int result = 0;
    if (argc >= 2 && argv[1] && argv[1][0] != L'\0') {
        const auto forwarded = notepad_replacer::BuildForwardedArgs(argc, argv);
        DWORD error_code = ERROR_SUCCESS;
        if (!notepad_replacer::LaunchTarget(argv[1], forwarded, &error_code)) {
            result = static_cast<int>(error_code ? error_code : ERROR_FUNCTION_FAILED);
        }
    }

    LocalFree(argv);
    return result;
}
