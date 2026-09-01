#include "launcher_core.h"

#include <shobjidl.h>
#include <windows.h>

#include <atomic>
#include <new>
#include <string>
#include <vector>

namespace {
constexpr CLSID kClassId = {0x7f0d3f1a, 0x1f33, 0x4f90, {0x9a, 0x1d, 0x3c, 0x83, 0x1e, 0x9d, 0x5a, 0x42}};
std::atomic_ulong g_server_locks{0}, g_object_count{0};
HINSTANCE g_instance = nullptr;
bool IsChineseUi() { return PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_CHINESE; }

class ExplorerCommand final : public IExplorerCommand {
public:
    ExplorerCommand() { ++g_object_count; }
    ~ExplorerCommand() { --g_object_count; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (riid == IID_IUnknown || riid == IID_IExplorerCommand) { *out = static_cast<IExplorerCommand*>(this); AddRef(); return S_OK; }
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
    ULONG STDMETHODCALLTYPE Release() override { auto n = --refs_; if (!n) delete this; return n; }
    HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray*, LPWSTR* out) override {
        if (!out) return E_POINTER;
        const wchar_t* title = IsChineseUi() ? L"使用记事本打开" : L"Open with Notepad";
        const size_t bytes = (wcslen(title) + 1) * sizeof(wchar_t);
        *out = static_cast<LPWSTR>(CoTaskMemAlloc(bytes)); if (!*out) return E_OUTOFMEMORY;
        CopyMemory(*out, title, bytes); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray*, LPWSTR* out) override {
        if (!out) return E_POINTER; wchar_t path[MAX_PATH]{};
        if (!GetModuleFileNameW(g_instance, path, ARRAYSIZE(path))) return HRESULT_FROM_WIN32(GetLastError());
        std::wstring icon = std::wstring(path) + L",-101";
        *out = static_cast<LPWSTR>(CoTaskMemAlloc((icon.size() + 1) * sizeof(wchar_t))); if (!*out) return E_OUTOFMEMORY;
        CopyMemory(*out, icon.c_str(), (icon.size() + 1) * sizeof(wchar_t)); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray*, LPWSTR* out) override { return GetTitle(nullptr, out); }
    HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* out) override { if (!out) return E_POINTER; *out = kClassId; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) override {
        if (!state) return E_POINTER; *state = ECS_HIDDEN; std::wstring target;
        if (!notepad_replacer::ReadConfiguredTarget(&target) || !items) return S_OK;
        DWORD count = 0; if (FAILED(items->GetCount(&count)) || !count) return S_OK;
        for (DWORD i = 0; i < count; ++i) { IShellItem* item = nullptr; if (FAILED(items->GetItemAt(i, &item)) || !item) return S_OK; SFGAOF attrs = 0; HRESULT hr = item->GetAttributes(SFGAO_FOLDER, &attrs); item->Release(); if (FAILED(hr) || (attrs & SFGAO_FOLDER)) return S_OK; }
        *state = ECS_ENABLED; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray* items, IBindCtx*) override {
        std::wstring target; if (!items || !notepad_replacer::ReadConfiguredTarget(&target)) return S_FALSE;
        DWORD count = 0; if (FAILED(items->GetCount(&count)) || !count) return S_FALSE; std::vector<std::wstring> paths; paths.reserve(count);
        for (DWORD i = 0; i < count; ++i) { IShellItem* item = nullptr; if (FAILED(items->GetItemAt(i, &item)) || !item) return E_FAIL; PWSTR path = nullptr; HRESULT hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path); item->Release(); if (FAILED(hr) || !path) return E_FAIL; paths.emplace_back(path); CoTaskMemFree(path); }
        DWORD error = 0; return notepad_replacer::LaunchTarget(target, paths, &error) ? S_OK : HRESULT_FROM_WIN32(error ? error : ERROR_FUNCTION_FAILED);
    }
    HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* flags) override { if (!flags) return E_POINTER; *flags = ECF_DEFAULT; return S_OK; }
    HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** out) override { if (out) *out = nullptr; return E_NOTIMPL; }
private: std::atomic_ulong refs_{1};
};

class ClassFactory final : public IClassFactory {
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** out) override { if (!out) return E_POINTER; *out = nullptr; if (riid == IID_IUnknown || riid == IID_IClassFactory) { *out = static_cast<IClassFactory*>(this); AddRef(); return S_OK; } return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
    ULONG STDMETHODCALLTYPE Release() override { auto n = --refs_; if (!n) delete this; return n; }
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID riid, void** out) override { if (outer) return CLASS_E_NOAGGREGATION; auto* c = new (std::nothrow) ExplorerCommand(); if (!c) return E_OUTOFMEMORY; HRESULT hr = c->QueryInterface(riid, out); c->Release(); return hr; }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override { if (lock) ++g_server_locks; else --g_server_locks; return S_OK; }
private: std::atomic_ulong refs_{1};
};
}
extern "C" BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) { if (reason == DLL_PROCESS_ATTACH) { g_instance = instance; DisableThreadLibraryCalls(instance); } return TRUE; }
extern "C" HRESULT STDAPICALLTYPE DllCanUnloadNow() { return !g_object_count.load() && !g_server_locks.load() ? S_OK : S_FALSE; }
extern "C" HRESULT STDAPICALLTYPE DllGetClassObject(REFCLSID clsid, REFIID riid, void** out) { if (!IsEqualCLSID(clsid, kClassId)) return CLASS_E_CLASSNOTAVAILABLE; auto* f = new (std::nothrow) ClassFactory(); if (!f) return E_OUTOFMEMORY; HRESULT hr = f->QueryInterface(riid, out); f->Release(); return hr; }
