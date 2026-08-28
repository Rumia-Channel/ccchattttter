//! WH_KEYBOARD_LL フック — old/hooookk.dpr の startHook/endHook/hookProc 移植。
//! MMF 共有は同一プロセス化に伴い Mutex 保護の static に置換。

use std::ffi::c_void;
use std::sync::atomic::{AtomicPtr, Ordering};
use std::sync::OnceLock;

use parking_lot::Mutex;
use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows::Win32::System::Performance::{QueryPerformanceCounter, QueryPerformanceFrequency};
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, GetMessageW, HHOOK, KBDLLHOOKSTRUCT, MSG, SetWindowsHookExW,
    UnhookWindowsHookEx, WH_KEYBOARD_LL,
};

use crate::engine::Engine;

static ENGINE: Mutex<Option<Engine>> = Mutex::new(None);
static EVENT_TX: OnceLock<crossbeam_channel::Sender<crate::engine::Outcome>> = OnceLock::new();
static HOOK: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());

/// UIスレッドからエンジン設定へ触るためのアクセサ (DLLのset*エクスポート相当)
pub fn with_engine<R>(f: impl FnOnce(&mut Engine) -> R) -> Option<R> {
    let mut guard = ENGINE.lock();
    guard.as_mut().map(f)
}

/// フックスレッド起動。LLフックのコールバックはこのスレッドのメッセージポンプ中に
/// 呼ばれるため、GetMessageW ループで待機し続ける。
pub fn spawn(engine: Engine, tx: crossbeam_channel::Sender<crate::engine::Outcome>) {
    let _ = EVENT_TX.set(tx);
    *ENGINE.lock() = Some(engine);

    std::thread::Builder::new()
        .name("keyboard-hook".into())
        .spawn(|| unsafe {
            if let Ok(hook) = SetWindowsHookExW(WH_KEYBOARD_LL, Some(hook_proc), None, 0) {
                HOOK.store(hook.0, Ordering::Release);

                let mut msg = MSG::default();
                while GetMessageW(&mut msg, None, 0, 0).as_bool() {}

                let h = HHOOK(HOOK.load(Ordering::Acquire));
                if !h.0.is_null() {
                    let _ = UnhookWindowsHookEx(h);
                }
            }
        })
        .expect("spawn hook thread");
}

unsafe extern "system" fn hook_proc(ncode: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    unsafe {
        if ncode < 0 {
            return CallNextHookEx(None, ncode, wparam, lparam);
        }

        let kb = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
        let vk = kb.vkCode;
        let flags = kb.flags.0; // KBDLLHOOKSTRUCT_FLAGS → u32
        let ll_time = kb.time;

        // 高精度タイマー用の現在ms (QPC)
        let mut qpc_ms = 0u32;
        let (mut counter, mut freq) = (0i64, 0i64);
        let _ = QueryPerformanceCounter(&mut counter);
        let _ = QueryPerformanceFrequency(&mut freq);
        if freq > 0 {
            qpc_ms = ((counter as f64 / freq as f64) * 1000.0) as u32;
        }

        let outcome = {
            // 停止中は元 endHook 同様、何も通知せず素通し
            let mut guard = ENGINE.lock();
            match guard.as_mut() {
                Some(e) if e.is_enabled() => e.process(vk, flags, ll_time, qpc_ms),
                _ => None,
            }
        };

        if let Some(o) = outcome {
            // 元実装はキャンセル時も PostMessage していたため、ここでも必ず通知
            if let Some(tx) = EVENT_TX.get() {
                let _ = tx.send(o);
            }
            if o.cancelled {
                return LRESULT(1); // CallNextHookEx 不呼び出し = イベント握り潰し
            }
        }

        CallNextHookEx(None, ncode, wparam, lparam)
    }
}
