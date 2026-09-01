#include "../src/launcher_core.h"

#include <cassert>

using notepad_replacer::BuildForwardedArgs;
using notepad_replacer::IsNotepadImage;
using notepad_replacer::QuoteWindowsCommandLineArg;

int wmain() {
    assert(IsNotepadImage(L"C:\\Windows\\notepad.exe"));
    assert(IsNotepadImage(L"  C:/Windows/NOTEPAD.EXE  "));
    assert(!IsNotepadImage(L"notepad.exe"));
    assert(!IsNotepadImage(L"C:\\Windows\\notepad.exe.bak"));

    wchar_t a0[] = L"launcher";
    wchar_t a1[] = L"target.exe";
    wchar_t a2[] = L"  C:\\Windows\\NOTEPAD.EXE  ";
    wchar_t a3[] = L"file with spaces.txt";
    wchar_t a4[] = L"";
    wchar_t* argv[] = {a0, a1, a2, a3, a4};
    const auto forwarded = BuildForwardedArgs(5, argv);
    assert(forwarded.size() == 1 && forwarded[0] == L"file with spaces.txt");

    assert(QuoteWindowsCommandLineArg(L"") == L"\"\"");
    assert(QuoteWindowsCommandLineArg(L"plain") == L"plain");
    assert(QuoteWindowsCommandLineArg(L"a b") == L"\"a b\"");
    assert(QuoteWindowsCommandLineArg(L"C:\\path\\") == L"C:\\path\\");
    assert(QuoteWindowsCommandLineArg(L"a\\\"b") == L"\"a\\\\\\\"b\"");
    return 0;
}
