//! ゲームモード用グローバルホットキー。
//! ini の `HotKey` (例: `Ctrl+Alt+G`) を RegisterHotKey で登録し、
//! 押下で抑止の開始/停止をトグルする。変更は再起動後に反映。

use windows::Win32::Foundation::WPARAM;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    RegisterHotKey, HOT_KEY_MODIFIERS, MOD_ALT, MOD_CONTROL, MOD_SHIFT, MOD_WIN,
};
use windows::Win32::UI::WindowsAndMessaging::{GetMessageW, MSG, WM_HOTKEY};

use crate::ui::UiEvent;

const HOTKEY_ID: i32 = 1;

/// "Ctrl+Alt+G" 等の表記を (修飾子, 仮想キーコード) へ変換する
pub fn parse(s: &str) -> Option<(HOT_KEY_MODIFIERS, u32)> {
    let mut mods = HOT_KEY_MODIFIERS(0);
    let mut vk: Option<u32> = None;
    for part in s.split('+') {
        match part.trim().to_ascii_lowercase().as_str() {
            "" => {}
            "ctrl" | "control" => mods |= MOD_CONTROL,
            "alt" => mods |= MOD_ALT,
            "shift" => mods |= MOD_SHIFT,
            "win" | "windows" => mods |= MOD_WIN,
            key => vk = Some(key_to_vk(key)?),
        }
    }
    vk.map(|v| (mods, v))
}

fn key_to_vk(key: &str) -> Option<u32> {
    let up = key.to_ascii_uppercase();
    let bytes = up.as_bytes();
    if bytes.len() == 1 && bytes[0].is_ascii_alphanumeric() {
        return Some(u32::from(bytes[0]));
    }
    if let Ok(n) = up[1..].parse::<u32>() {
        if up.starts_with('F') && (1..=24).contains(&n) {
            return Some(0x70 + n - 1); // VK_F1..VK_F24
        }
    }
    match up.as_str() {
        "SPACE" => Some(0x20),
        "ESC" | "ESCAPE" => Some(0x1B),
        "TAB" => Some(0x09),
        "UP" => Some(0x26),
        "DOWN" => Some(0x28),
        "LEFT" => Some(0x25),
        "RIGHT" => Some(0x27),
        "PRINTSCREEN" => Some(0x2C),
        _ => None,
    }
}

/// ホットキー登録スレッド。WM_HOTKEY を受けたらトグルイベントを送る。
/// (登録解除はプロセス終了時に OS が行う)
pub fn spawn(hotkey: &str, tx: async_channel::Sender<UiEvent>) {
    let Some((mods, vk)) = parse(hotkey) else {
        eprintln!("[hotkey] 解釈できないホットキー指定: {hotkey:?} (無効)");
        return;
    };

    std::thread::Builder::new()
        .name("hotkey".into())
        .spawn(move || unsafe {
            if RegisterHotKey(None, HOTKEY_ID, mods, vk).is_err() {
                eprintln!("[hotkey] 登録に失敗 (他アプリが使用中の可能性)");
                return;
            }
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                if msg.message == WM_HOTKEY && msg.wParam == WPARAM(HOTKEY_ID as usize) {
                    let _ = tx.send_blocking(UiEvent::ToggleRunning);
                }
            }
        })
        .expect("spawn hotkey thread");
}
