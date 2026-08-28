//! メインウィンドウの表示/非表示切替 (Win32直接操作)。
//! gpui 0.2 にはウィンドウを隠す公開APIがなく、かつ wndproc が WM_SHOWWINDOW を
//! 処理して DefWindowProc に渡さないため ShowWindow(Async) が効かない。
//! そこで SetWindowPos の SWP_SHOWWINDOW / SWP_HIDEWINDOW を使う
//! (WM_WINDOWPOSCHANGING は gpui 未処理のため DefWindowProc に流れる)。

use std::sync::atomic::{AtomicIsize, Ordering};

use windows::Win32::Foundation::{HWND, LPARAM};
use windows::Win32::System::Threading::GetCurrentProcessId;
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowTextW, GetWindowThreadProcessId, IsWindow, SetWindowPos,
    SWP_HIDEWINDOW, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER, SWP_SHOWWINDOW,
};
use windows::core::BOOL;

static MAIN_HWND: AtomicIsize = AtomicIsize::new(0);

fn title_utf16() -> Vec<u16> {
    "ccchattttter".encode_utf16().collect()
}

unsafe extern "system" fn find_cb(hwnd: HWND, _lparam: LPARAM) -> BOOL {
    unsafe {
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == GetCurrentProcessId() {
            let mut buf = [0u16; 32];
            let n = GetWindowTextW(hwnd, &mut buf) as usize;
            if n > 0 && buf[..n] == title_utf16()[..] {
                MAIN_HWND.store(hwnd.0 as isize, Ordering::Release);
                return BOOL(0); // 列挙打ち切り
            }
        }
        BOOL(1)
    }
}

fn main_hwnd() -> Option<HWND> {
    let cached = MAIN_HWND.load(Ordering::Acquire);
    if cached != 0 {
        let h = HWND(cached as *mut core::ffi::c_void);
        if unsafe { IsWindow(Some(h)) }.as_bool() {
            return Some(h);
        }
        MAIN_HWND.store(0, Ordering::Release);
    }
    unsafe {
        let _ = EnumWindows(Some(find_cb), LPARAM(0));
    }
    let v = MAIN_HWND.load(Ordering::Acquire);
    (v != 0).then(|| HWND(v as *mut core::ffi::c_void))
}

/// メインウィンドウの表示/非表示を切り替える。
pub fn set_main_window_visible(show: bool) {
    if let Some(h) = main_hwnd() {
        unsafe {
            let _ = SetWindowPos(
                h,
                None,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
                    | if show { SWP_SHOWWINDOW } else { SWP_HIDEWINDOW },
            );
        }
    }
}
