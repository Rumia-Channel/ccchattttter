//! キー名称変換 — old/Unit1.pas getKeyName の移植。
//!
//! JIS キーボード基準の名称を元実装から踏襲。
//! ※元実装では VK_PRIOR/VK_NEXT の表示名が入れ替わっていたため修正済み。

use crate::engine;

/// LLKHF_EXTENDED (KF_EXTENDED shr 8)
const EXTENDED: u32 = 0x01;

pub fn key_name(vk: u32, flags: u32) -> String {
    let ext = flags & EXTENDED != 0;
    let name: String = match vk {
        0x01 => "LBUTTON",
        0x02 => "RBUTTON",
        0x03 => "CANCEL",
        0x04 => "MBUTTON",
        0x08 => "BS",
        0x09 => "TAB",
        0x0C => "CLEAR",
        0x0D => {
            return if ext { "NumEnter".into() } else { "Enter".into() };
        }
        0x10 => "SHIFT",
        0x11 => "CONTROL",
        0x12 => "MENU",
        0x13 => "PAUSE",
        0x14 => "CAPITAL",
        0x15 => "KANA",
        0x17 => "JUNJA",
        0x18 => "FINAL",
        0x19 => "KANJI",
        0x1C => "変換",
        0x1D => "無変換",
        0x1E => "ACCEPT",
        0x1F => "MODECHANGE",
        0x1B => "ESC",
        0x20 => "SPACE",
        0x21 => "PageUp",   // 元実装では PageDown 表記だったのを修正
        0x22 => "PageDown", // 元実装では PageUp 表記だったのを修正
        0x23 => "END",
        0x24 => "HOME",
        0x25 => "←",
        0x26 => "↑",
        0x27 => "→",
        0x28 => "↓",
        0x29 => "SELECT",
        0x2A => "PRINT",
        0x2B => "EXECUTE",
        0x2C => "PrintSc",
        0x2D => "INSERT",
        0x2E => "DELETE",
        0x2F => "HELP",
        0x30..=0x39 => return char::from(b'0' + (vk - 0x30) as u8).to_string(),
        0x41..=0x5A => return char::from(vk as u8).to_string(),
        0x5B => "LWIN",
        0x5C => "RWIN",
        0x5D => "APPS",
        0x60..=0x69 => return format!("Num{}", vk - 0x60),
        0x6A => "Num*",
        0x6B => "Num+",
        0x6C => "SEPARATOR",
        0x6D => "Num-",
        0x6E => "Num.",
        0x6F => "Num/",
        0x70..=0x87 => {
            return format!("F{}", vk - 0x70 + 1);
        }
        0x90 => "NumLock",
        0x91 => "SCROLL",
        0xA0 => "LSHIFT",
        0xA1 => "RSHIFT",
        0xA2 => "LCTRL",
        0xA3 => "RCTRL",
        0xA4 => "LAlt",
        0xA5 => "RAlt",
        0xE5 => "PROCESSKEY",
        0xF2 => "カタひら",
        0xF6 => "ATTN",
        0xF7 => "CRSEL",
        0xF8 => "EXSEL",
        0xF9 => "EREOF",
        0xFA => "PLAY",
        0xFB => "ZOOM",
        0xFC => "NONAME",
        0xFD => "PA1",
        0xFE => "OEM_CLEAR",
        0xBC => "COMMA",
        0xBE => "PERIOD",
        0xBF => "/",
        0xDE => "^",   // 222
        0xBD => "-",   // 189
        0xDD => "]",   // 221
        0xBA => "ｺﾛﾝ",   // 186
        0xBB => "ｾﾐｺﾛﾝ", // 187
        0xDB => "[",   // 219
        0xC0 => "@",   // 192
        _ => return format!("VK({vk})"),
    }
    .into();
    name
}

/// WndProc のログ行整形 (元実装: 名称\tDOWN|UP\t{ms}ms[\tchattering!?])
pub fn format_line(o: &engine::Outcome) -> String {
    let mut line = format!(
        "{}\t{}\t{}ms",
        key_name(o.vk, o.flags),
        if o.transition == engine::Transition::Down { "DOWN" } else { "UP" },
        o.elapsed_ms
    );
    if o.chatter {
        line.push_str("\tchattering!?");
    }
    line
}
