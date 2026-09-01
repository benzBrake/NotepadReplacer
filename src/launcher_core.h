#pragma once

#include <string>
#include <string_view>
#include <vector>
#include <windows.h>

namespace notepad_replacer {

bool IsNotepadImage(std::wstring_view value);

std::vector<std::wstring> BuildForwardedArgs(int argc, wchar_t* const* argv);

std::wstring QuoteWindowsCommandLineArg(std::wstring_view value);

bool LaunchTarget(std::wstring_view target,
                  const std::vector<std::wstring>& args,
                  DWORD* error_code = nullptr);

bool ReadConfiguredTarget(std::wstring* target, REGSAM extra_access = 0);
bool IsValidConfiguredTarget(std::wstring_view target);

} // namespace notepad_replacer
