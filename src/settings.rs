//! INI設定 — 元 ccchattttter.ini と同一セクション/キー名を継続し、
//! 既存ユーザーの設定ファイルをそのまま引き継げるようにする。

use std::path::{Path, PathBuf};

use ini::Ini;

#[derive(Debug, Clone)]
pub struct Settings {
    // [setting]
    pub chattering_threshold: u32,
    pub key_repeat_threshold: u32,
    pub key_updown_threshold: u32,
    pub ignore_key_repeat: bool,
    pub chatter_cancel: bool,
    pub view_up: bool,
    pub logging: bool,
    pub accuracy: bool,
    pub log_chatter: bool,
    pub log_max: u32,
    pub ignore_ten_key: bool,
    /// ゲームモード用グローバルホットキー (例: Ctrl+Alt+G)
    pub hotkey: String,
    // [sound]
    pub sound_on: bool,
    pub wave_file_name: String,
    // [form]
    pub top: i32,
    pub left: i32,
    pub width: i32,
    pub height: i32,
    pub minimized: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            chattering_threshold: 50,
            key_repeat_threshold: 0,
            key_updown_threshold: 8,
            ignore_key_repeat: true,
            chatter_cancel: true,
            view_up: false,
            logging: false,
            accuracy: false,
            log_chatter: false,
            log_max: 1000,
            ignore_ten_key: false,
            hotkey: "Ctrl+Alt+G".to_string(),
            sound_on: false,
            wave_file_name: String::new(),
            top: -1,
            left: -1,
            width: 523,
            height: 280,
            minimized: false,
        }
    }
}

impl Settings {
    fn from_ini(ini: &Ini) -> Self {
        let d = Self::default();
        let g = |sec: Option<&str>, k: &str| ini.get_from(sec, k);
        let gi = |sec: Option<&str>, k: &str, def: i64| {
            g(sec, k).and_then(|v| v.parse::<i64>().ok()).unwrap_or(def)
        };
        let gb = |sec: Option<&str>, k: &str, def: bool| match g(sec, k) {
            Some("true" | "1" | "yes") => true,
            Some("false" | "0" | "no") => false,
            _ => def,
        };
        let clamp_u32 = |v: i64| v.clamp(0, u32::MAX as i64) as u32;
        const SET: Option<&str> = Some("setting");
        const SND: Option<&str> = Some("sound");
        const FRM: Option<&str> = Some("form");
        Self {
            chattering_threshold: clamp_u32(gi(SET, "chattering-Threshold", 50)),
            key_repeat_threshold: clamp_u32(gi(SET, "KeyRepeat-Threshold", 0)),
            key_updown_threshold: clamp_u32(gi(SET, "KeyUpDown-Threshold", 8)),
            ignore_key_repeat: gb(SET, "IgnoreKeyRepert", true),
            chatter_cancel: gb(SET, "chatterCancel", true),
            view_up: gb(SET, "ViewUp", false),
            logging: gb(SET, "Loging", false),
            log_chatter: gb(SET, "LogChatter", false),
            accuracy: gb(SET, "accuracy", false),
            hotkey: g(SET, "HotKey").unwrap_or("Ctrl+Alt+G").to_string(),
            log_max: clamp_u32(gi(SET, "LogMax", 1000)),
            ignore_ten_key: gb(SET, "IgnoreTenKey", false),
            sound_on: gb(SND, "on", false),
            wave_file_name: g(SND, "waveFileName").unwrap_or_default().to_string(),
            top: gi(FRM, "top", i64::from(d.top)).clamp(-32768, 32767) as i32,
            left: gi(FRM, "left", i64::from(d.left)).clamp(-32768, 32767) as i32,
            width: gi(FRM, "width", 523).clamp(300, 16384) as i32,
            height: gi(FRM, "height", 280).clamp(200, 16384) as i32,
            minimized: gb(FRM, "Minimized", false),
        }
    }

    /// exe と同じディレクトリの ccchattttter.ini
    pub fn default_path() -> Option<PathBuf> {
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.join("ccchattttter.ini")))
    }

    pub fn load(path: &Path) -> Self {
        match Ini::load_from_file(path) {
            Ok(ini) => Self::from_ini(&ini),
            Err(_) => Self::default(),
        }
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        let mut ini = Ini::new();
        let mut s = ini.with_section(Some("setting"));
        s.set("chattering-Threshold", self.chattering_threshold.to_string());
        s.set("KeyRepeat-Threshold", self.key_repeat_threshold.to_string());
        s.set("KeyUpDown-Threshold", self.key_updown_threshold.to_string());
        s.set("IgnoreKeyRepert", self.ignore_key_repeat.to_string());
        s.set("chatterCancel", self.chatter_cancel.to_string());
        s.set("ViewUp", self.view_up.to_string());
        s.set("Loging", self.logging.to_string());
        s.set("accuracy", self.accuracy.to_string());
        s.set("LogChatter", self.log_chatter.to_string());
        s.set("LogMax", self.log_max.to_string());
        s.set("IgnoreTenKey", self.ignore_ten_key.to_string());
        s.set("HotKey", self.hotkey.as_str());

        let mut snd = ini.with_section(Some("sound"));
        snd.set("on", self.sound_on.to_string());
        snd.set("waveFileName", self.wave_file_name.as_str());

        let mut f = ini.with_section(Some("form"));
        f.set("top", self.top.to_string());
        f.set("left", self.left.to_string());
        f.set("width", self.width.to_string());
        f.set("height", self.height.to_string());
        f.set("Minimized", self.minimized.to_string());

        ini.write_to_file(path)
    }
}
