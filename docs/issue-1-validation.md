# Issue #1 validation

Automated tests use unique HKCU registry keys, a test-only Launcher entry point
that redirects HKLM reads with `RegOverridePredefKey`, and a test editor that
records received arguments. The installed Launcher has no registry override or
test environment hooks. Shell tests register a unique executable name in App
Paths; they do not replace the real `notepad.exe` entry.

Build both architectures and their test targets before running CTest:

```powershell
.\build.ps1 -Configuration Release
cmake --build dist/x64 --config Release --target launcher_core_tests launcher_test_entry launcher_test_editor
cmake --build dist/x86 --config Release --target launcher_core_tests launcher_test_entry launcher_test_editor
ctest --test-dir dist/x64 -C Release --output-on-failure
ctest --test-dir dist/x86 -C Release --output-on-failure
powershell -ExecutionPolicy Bypass -File tests/app_paths_tests.ps1
```

The registry tests cover default values that are absent, empty, `REG_SZ`, or
unexpanded `REG_EXPAND_SZ`; other values and subkeys; repeated installation;
upgrade commit and rollback; external changes, including value-type changes;
invalid backups; missing backups; and injected write/restore failures with retry.
Process tests check child creation, arguments, IFEO arguments, configuration
errors, missing editors, invalid executable images, and Shell App Paths launches.

On 2026-10-09, both x64 and x86 Release components built successfully and each
architecture passed all three CTest suites. Inno Setup 6.7.3 compiled the installer
to `dist/installer-validation/NotepadReplacerSetup.exe` using the existing signed
MSIX and certificate. Packaging did not regenerate signing material or run the
installer on the development host.

## Disposable Windows 11 acceptance environment

Use a VM snapshot, not the developer's Windows installation. Installation removes
Store Notepad and its provisioned package, and rollback does not restore them.

| Scenario | Acceptance check |
| --- | --- |
| System Notepad entry exists | Install, use Win+R with `notepad` and `notepad "C:\folder with spaces\file.txt"`; check the selected editor and document. |
| System Notepad entry is absent, preferably 25H2 build 26200.9457 | Repeat both Win+R checks after installation; record the actual build and file state. |
| ShellExecute | Launch `notepad.exe` with and without a document through a ShellExecute caller; confirm the editor and arguments. |
| Existing App Paths default | Test absent, empty, `REG_SZ`, and unexpanded `REG_EXPAND_SZ`; uninstall must restore the exact default and type. |
| Reinstall / upgrade | Install twice or change editor; uninstall must restore the value before the first installation. |
| External edit | Change the default after installation; uninstall must preserve the new value. |
| Restore denied | Deny restoration in the disposable VM; uninstall must stop before deleting files/configuration and retain the backup. Resolve the cause and retry. |
| Start menu search | Search for Notepad separately and record the selected result and launch outcome; this is not implied by App Paths success. |
| Missing hardcoded System32 path | Record as outside this fix's scope; no placeholder executable is installed. |

The development host is Windows 11 26H1, build 28000.2956, with system Notepad
files present. No disposable 25H2 environment was available during implementation;
real `notepad` Win+R, missing-system-entry installation, Start menu search, and
installer failure/uninstall UI checks remain unverified there.
