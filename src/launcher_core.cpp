#include "launcher_core.h"

#include <algorithm>
#include <cwctype>
#include <vector>

namespace notepad_replacer {
namespace {

std::wstring Trim(std::wstring_view value) {
    size_t first = 0;
    size_t last = value.size();
    while (first < last && std::iswspace(value[first])) ++first;
    while (last > first && std::iswspace(value[last - 1])) --last;
    return std::wstring(value.substr(first, last - first));
}

bool EndsWithInsensitive(std::wstring_view value, std::wstring_view suffix) {
    if (value.size() < suffix.size()) return false;
    const size_t offset = value.size() - suffix.size();
    for (size_t i = 0; i < suffix.size(); ++i) {
        if (std::towlower(value[offset + i]) != std::towlower(suffix[i])) return false;
    }
    return true;
}

} // namespace

bool IsNotepadImage(std::wstring_view value) {
    const std::wstring trimmed = Trim(value);
    return EndsWithInsensitive(trimmed, L"\\notepad.exe") ||
           EndsWithInsensitive(trimmed, L"/notepad.exe");
}

std::vector<std::wstring> BuildForwardedArgs(int argc, wchar_t* const* argv) {
    std::vector<std::wstring> forwarded;
    if (!argv || argc <= 2) return forwarded;

    for (int i = 2; i < argc; ++i) {
        if (argv[i] && argv[i][0] != L'\0') forwarded.emplace_back(argv[i]);
    }
    if (!forwarded.empty() && IsNotepadImage(forwarded.front())) {
        forwarded.erase(forwarded.begin());
    }
    return forwarded;
}

std::wstring QuoteWindowsCommandLineArg(std::wstring_view value) {
    if (value.empty()) return L"\"\"";

    bool needs_quotes = false;
    for (wchar_t ch : value) {
        if (std::iswspace(ch) || ch == L'\"') {
            needs_quotes = true;
            break;
        }
    }
    if (!needs_quotes) return std::wstring(value);

    std::wstring result;
    result.reserve(value.size() + 2);
    result.push_back(L'\"');
    size_t backslashes = 0;
    for (wchar_t ch : value) {
        if (ch == L'\\') {
            ++backslashes;
        } else if (ch == L'\"') {
            result.append(backslashes * 2 + 1, L'\\');
            result.push_back(L'\"');
            backslashes = 0;
        } else {
            result.append(backslashes, L'\\');
            backslashes = 0;
            result.push_back(ch);
        }
    }
    result.append(backslashes * 2, L'\\');
    result.push_back(L'\"');
    return result;
}

bool LaunchTarget(std::wstring_view target,
                  const std::vector<std::wstring>& args,
                  DWORD* error_code) {
    if (error_code) *error_code = ERROR_SUCCESS;
    if (target.empty()) return true;

    std::wstring command_line = QuoteWindowsCommandLineArg(target);
    for (const auto& arg : args) {
        command_line.push_back(L' ');
        command_line += QuoteWindowsCommandLineArg(arg);
    }

    std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
    mutable_command.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    const BOOL created = CreateProcessW(
        std::wstring(target).c_str(), mutable_command.data(), nullptr, nullptr, FALSE,
        CREATE_UNICODE_ENVIRONMENT, nullptr, nullptr, &startup, &process);
    if (!created) {
        if (error_code) *error_code = GetLastError();
        return false;
    }

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}

bool IsValidConfiguredTarget(std::wstring_view target) {
    if (target.empty()) return false;
    const std::wstring path(target);
    const DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

bool ReadConfiguredTarget(std::wstring* target, REGSAM extra_access) {
    if (!target) return false;
    target->clear();
    HKEY key = nullptr;
    const REGSAM access = KEY_QUERY_VALUE | extra_access;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"Software\\NotepadReplacer", 0,
                      access | KEY_WOW64_64KEY, &key) != ERROR_SUCCESS) {
        return false;
    }
    DWORD type = 0;
    DWORD bytes = 0;
    LONG result = RegQueryValueExW(key, L"TargetPath", nullptr, &type, nullptr, &bytes);
    if (result == ERROR_SUCCESS && type == REG_SZ && bytes > sizeof(wchar_t)) {
        std::vector<wchar_t> buffer(bytes / sizeof(wchar_t) + 1, L'\0');
        result = RegQueryValueExW(key, L"TargetPath", nullptr, &type,
                                  reinterpret_cast<LPBYTE>(buffer.data()), &bytes);
        if (result == ERROR_SUCCESS) *target = buffer.data();
    }
    RegCloseKey(key);
    return result == ERROR_SUCCESS && IsValidConfiguredTarget(*target);
}

} // namespace notepad_replacer
