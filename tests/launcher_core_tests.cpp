#include "../src/launcher_core.h"

#include <cassert>

using notepad_replacer::BuildForwardedArgs;
using notepad_replacer::IsNotepadImage;
using notepad_replacer::IsExplicitTarget;
using notepad_replacer::QuoteWindowsCommandLineArg;

int wmain() {
    // These are synthetic strings; argument parsing does not access the filesystem.
    assert(IsExplicitTarget(L"C:\\Program Files\\Example Editor\\editor.EXE"));
    assert(IsExplicitTarget(L"target.exe"));
    assert(!IsExplicitTarget(L"C:\\example\\settings.ini"));
    assert(!IsExplicitTarget(L"editor.exe.ini"));
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

    wchar_t document[] = L"C:\\example folder\\settings.ini";
    wchar_t* direct_argv[] = {a0, document, a3};
    const auto direct = BuildForwardedArgs(3, direct_argv, 1);
    assert(direct.size() == 2 && direct[0] == document && direct[1] == a3);
    const auto single = BuildForwardedArgs(2, direct_argv, 1);
    assert(single.size() == 1 && single[0] == document);
    wchar_t* editor_argv[] = {a0, a1, a3};
    const auto editor = BuildForwardedArgs(3, editor_argv);
    assert(editor.size() == 1 && editor[0] == a3);

    assert(QuoteWindowsCommandLineArg(L"") == L"\"\"");
    assert(QuoteWindowsCommandLineArg(L"plain") == L"plain");
    assert(QuoteWindowsCommandLineArg(L"a b") == L"\"a b\"");
    assert(QuoteWindowsCommandLineArg(L"C:\\path\\") == L"C:\\path\\");
    assert(QuoteWindowsCommandLineArg(L"a\\\"b") == L"\"a\\\\\\\"b\"");
    return 0;
}
