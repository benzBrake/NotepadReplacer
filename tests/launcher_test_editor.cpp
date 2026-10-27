#include <windows.h>
#include <fstream>
#include <string>

int wmain(int argc, wchar_t** argv) {
    wchar_t output[32768]{};
    if (!GetEnvironmentVariableW(L"NOTEPAD_REPLACER_TEST_OUTPUT", output, 32768)) return 1;
    const std::wstring temporary = std::wstring(output) + L".tmp";
    std::ofstream file(temporary, std::ios::binary);
    file.write(reinterpret_cast<const char*>(&argc), sizeof(argc));
    for (int i = 1; i < argc; ++i) {
        const DWORD length = static_cast<DWORD>(wcslen(argv[i]));
        file.write(reinterpret_cast<const char*>(&length), sizeof(length));
        file.write(reinterpret_cast<const char*>(argv[i]), length * sizeof(wchar_t));
    }
    file.close();
    if (!file) return 2;
    return MoveFileExW(temporary.c_str(), output, MOVEFILE_REPLACE_EXISTING) ? 0 : 3;
}
