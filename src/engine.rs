//! チャタリング判定エンジン — old/hooookk.dpr (ver 1.0.4.7) の忠実移植。
//!
//! 元ソースの THookInfo / TKeyInfo / hookProc の DOWN/UP 判定ロジックを
//! 1:1 で移植している。時間はすべて u32 ラップアラウンド演算
//! (Delphi の Cardinal 算術と同一) で扱う。

/// チャタフラグ (lParam bit30)
pub const CHATTER_BIT: u32 = 1 << 30;
/// UPフラグ (lParam bit31)
pub const UP_BIT: u32 = 1 << 31;

pub const VK_BACK: u32 = 0x08;
pub const VK_LCONTROL: u32 = 0xA2;
pub const VK_RCONTROL: u32 = 0xA3;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Transition {
    Down,
    Up,
}

/// 1キーイベントあたりの判定結果。UI通知 (PostMessage 相当) のペイロードも兼ねる。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Outcome {
    pub vk: u32,
    /// KBDLLHOOKSTRUCT.flags をそのまま格納 (NumEnter 区別に LLKHF_EXTENDED を使う)
    pub flags: u32,
    pub transition: Transition,
    pub chatter: bool,
    pub elapsed_ms: u32,
    /// チャタキャンセルにより OS へ渡さなかった (CallNextHookEx 不呼び出し)
    pub cancelled: bool,
}

#[derive(Debug, Clone)]
pub struct Config {
    /// [DOWN]-UP-[DOWN] 閾値 ms (既定50)
    pub chater_threshold: u32,
    /// [DOWN]-[DOWN] 閾値 ms リピート中判定 (既定0)
    pub repeat_threshold: u32,
    /// [UP]-[DOWN] 閾値 ms (既定8)
    pub updown_threshold: u32,
    /// キーリピート無視
    pub ignore_key_repeat: bool,
    /// テンキー無視
    pub ignore_ten_key: bool,
    /// 高精度タイマー (QPC)。OFF時は KBDLLHOOKSTRUCT.time を使用
    pub high_accuracy: bool,
    /// チャタリングキャンセル
    pub chatter_cancel: bool,
    /// UP監視
    pub key_up_chatter: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            chater_threshold: 50,
            repeat_threshold: 0,
            updown_threshold: 8,
            ignore_key_repeat: true,
            ignore_ten_key: false,
            high_accuracy: false,
            chatter_cancel: true,
            key_up_chatter: false,
        }
    }
}

#[derive(Debug, Default, Clone)]
struct KeyInfo {
    prev_down_time: u32,
    prev_up_time: u32,
    #[allow(dead_code)]
    prev_chattering: bool,
    next_up_disable_flg: i32,
    next_down_disable_flg: i32,
    while_repeat: bool,
}

/// hooookk.dpr の isTenKey。VK_SEPARATOR(0x6C) は除外 (元実装通り)。
fn is_ten_key(key: u32) -> bool {
    matches!(key, 0x60..=0x6B | 0x6D..=0x6F)
}

pub struct Engine {
    cfg: Config,
    enabled: bool,
    prev_down_key: u32,
    keys: Box<[KeyInfo]>,
}

impl Engine {
    pub fn new(cfg: Config) -> Self {
        Self {
            cfg,
            enabled: true,
            prev_down_key: 0,
            keys: vec![KeyInfo::default(); 256].into_boxed_slice(),
        }
    }

    pub fn set_config(&mut self, cfg: Config) {
        self.cfg = cfg;
    }

    /// stop 相当。元の endHook はフック解除だが、単一プロセス化に伴い
    /// 全イベント素通し+UI通知なしで同等挙動を実現する。
    pub fn set_enabled(&mut self, on: bool) {
        self.enabled = on;
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// hookProc 本体の移植。
    ///
    /// * `ll_time` — KBDLLHOOKSTRUCT.time
    /// * `qpc_ms`  — QueryPerformanceCounter 由来の現在ms (高精度タイマーON時に使用)
    ///
    /// `None`: VK(255) 以上のダミーイベントなど、処理対象外 (PostMessageも不要)。
    pub fn process(&mut self, vk: u32, flags: u32, ll_time: u32, qpc_ms: u32) -> Option<Outcome> {
        // VK(255)は無視。メニューループを抜けるため(?)に一部ソフトが発生させるダミーイベント。
        if vk >= 255 {
            return None;
        }
        let down = flags & 0x80 == 0; // LLKHF_UP
        let ms = if self.cfg.high_accuracy { qpc_ms } else { ll_time };

        let mut lp: u32 = 0;
        let mut cancelled = false;

        if down {
            // ---- DOWN時の処理 -------------------------------------------------
            let maje = {
                let ki = &mut self.keys[vk as usize];

                // [DOWN]-[DOWN] 前回DOWNからの時間 (Cardinal ラップアラウンド演算)
                let wk_ms_base = if ki.prev_down_time == 0 {
                    0
                } else {
                    ms.wrapping_sub(ki.prev_down_time)
                };
                let mut wk_ms = wk_ms_base;

                // チャタリング判定: 閾値未満かつ同一キー
                let mut maje = wk_ms < self.cfg.chater_threshold && self.prev_down_key == vk;

                // リピート無視指定時は前回DOWNがリピート由来ならチャタとみなさない
                if maje && self.cfg.ignore_key_repeat && ki.while_repeat {
                    maje = false;
                }

                ki.next_up_disable_flg = 0;

                // [UP]-[DOWN] キーを離す時に起きるチャタの判定
                if self.cfg.key_up_chatter
                    && ki.prev_up_time != 0
                    && ki.prev_down_time < ki.prev_up_time
                {
                    wk_ms = ms.wrapping_sub(ki.prev_up_time);
                    if !maje && wk_ms < self.cfg.updown_threshold {
                        maje = true;
                        ki.next_up_disable_flg = 2; // この次のUPは捨てたい
                    }
                }

                // [DOWN]-[UP]後続 UP時チャタの直後DOWN (高精度タイマ前提)
                if ki.next_down_disable_flg == 2
                    && ms.wrapping_sub(ki.prev_up_time) < self.cfg.updown_threshold
                {
                    maje = true;
                }

                // リピート判定 (以降では「今回のDOWNがリピート由来か」を表す)
                ki.while_repeat = ki.prev_up_time < ki.prev_down_time;

                // キーリピート無視: UPが来ていなければチャタじゃない判定
                // 「≦」なのは repeatThreshold=0 でリピート完全無視できるように (元コメント)
                if maje && self.cfg.ignore_key_repeat && self.cfg.repeat_threshold <= wk_ms {
                    if ki.while_repeat {
                        maje = false; // 連続Down ⇒ リピートなのでチャタじゃない
                    }
                }

                // 外付けテンキー用オプション
                if self.cfg.ignore_ten_key && is_ten_key(vk) {
                    maje = false;
                }

                // 今回押下情報を保存
                ki.prev_down_time = ms;
                self.prev_down_key = vk;

                // チャタ情報設定・保持
                if maje {
                    lp |= CHATTER_BIT; // bit30 = チャタ
                }
                ki.prev_chattering = maje;

                maje
            };

            // MS-IME確定アンドゥ (Ctrl+BS) はキャンセルさせない
            // （実際はチャタでは無いけど、内部的にはチャタとして記憶させておく）
            let undo = self.undo_kakutei(vk, ms);
            let ki = &mut self.keys[vk as usize];
            if undo {
                lp &= !CHATTER_BIT; // 表示させないようbit30を戻す
                ki.next_down_disable_flg = 1; // 次回のDownは捨てさせない
                ki.next_up_disable_flg = 1;   // UPも捨てさせない
                // 元実装ではここで flgMaje=false となるためキャンセルは発生しない
            } else {
                ki.next_down_disable_flg = 0;

                // キャンセル判定
                if maje && self.cfg.chatter_cancel {
                    cancelled = true; // Result := 1 (次に送らない)
                }
            }
        } else {
            // ---- UP時の処理 ---------------------------------------------------
            let ki = &mut self.keys[vk as usize];
            lp |= UP_BIT; // bit31 = UP
            let wk_ms = if ki.prev_down_time == 0 {
                self.cfg.updown_threshold // 前回DOWN時刻が保持されていない場合
            } else {
                ms.wrapping_sub(ki.prev_down_time)
            };

            ki.prev_up_time = ms;

            // [DOWN]-[UP] 押した時に起きるチャタリングの判定
            // 高精度タイマ使用時のみ有効 (DOWN-UPが同時刻で発生するため)
            if self.cfg.chatter_cancel
                && self.cfg.key_up_chatter
                && self.cfg.high_accuracy
                && wk_ms < self.cfg.updown_threshold
                && ki.next_up_disable_flg != 1
                && !ki.while_repeat
            {
                lp |= CHATTER_BIT;
                ki.prev_chattering = true;
                ki.next_down_disable_flg = 2; // 次のDownを捨てる
                cancelled = true;
            }

            ki.next_up_disable_flg = 0;
        }

        Some(Outcome {
            vk,
            flags,
            transition: if down { Transition::Down } else { Transition::Up },
            chatter: lp & CHATTER_BIT != 0,
            elapsed_ms: lp & 0x3FFF_FFFF,
            cancelled,
        })
    }

    /// undo_kakutei の移植: MS-IMEの確定アンドゥ(Ctrl+BS)中のBS連続をチャタ扱いしない。
    /// ATOK等の判定は行わない (元実装通り)。
    fn undo_kakutei(&self, key: u32, ms: u32) -> bool {
        if key != VK_BACK {
            return false;
        }
        // BackSpace自身が「次回有効指定かつチャタ閾値未満で押下」された場合
        let bs = &self.keys[VK_BACK as usize];
        if bs.next_down_disable_flg == 1
            && ms.wrapping_sub(bs.prev_down_time) < self.cfg.chater_threshold
        {
            return true;
        }
        // 左Ctrlが押されたことがあり、まだ離されていない場合
        let lc = &self.keys[VK_LCONTROL as usize];
        if lc.prev_down_time != 0 && lc.prev_up_time <= lc.prev_down_time {
            return true;
        }
        // 右Ctrl同様
        let rc = &self.keys[VK_RCONTROL as usize];
        if rc.prev_down_time != 0 && rc.prev_up_time <= rc.prev_down_time {
            return true;
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn engine() -> Engine {
        Engine::new(Config::default())
    }

    fn press(e: &mut Engine, vk: u32, t: u32) -> Outcome {
        e.process(vk, 0, t, t).unwrap()
    }

    fn release(e: &mut Engine, vk: u32, t: u32) -> Outcome {
        e.process(vk, 0x80, t, t).unwrap()
    }

    /// readme: [DOWN]-UP-[DOWN] 押し下げ時のチャタ (既定50ms)
    #[test]
    fn down_up_down_within_threshold_is_chatter_and_cancelled() {
        let mut e = engine();
        assert!(!press(&mut e, b'A' as u32, 1000).chatter);
        assert!(!release(&mut e, b'A' as u32, 1010).cancelled);
        // 10ms後に再押下 → チャタ
        let o = press(&mut e, b'A' as u32, 1020);
        assert!(o.chatter);
        assert!(o.cancelled);
    }

    #[test]
    fn slow_repress_is_not_chatter() {
        let mut e = engine();
        press(&mut e, b'A' as u32, 1000);
        release(&mut e, b'A' as u32, 1050);
        let o = press(&mut e, b'A' as u32, 1200);
        assert!(!o.chatter);
        assert!(!o.cancelled);
    }

    /// リピート中の連続DOWN (repeatThreshold=0) はチャタではない
    #[test]
    fn key_repeat_consecutive_downs_are_exempt() {
        let mut e = engine();
        press(&mut e, b'A' as u32, 1000);
        // UPなしで連続DOWN → whileRepeat
        let o = press(&mut e, b'A' as u32, 1030);
        assert!(!o.chatter, "リピート中の30ms間隔DOWNは免除");
    }

    /// ignoreKeyRepeat OFFならリピート免除されない
    #[test]
    fn repeat_not_ignored_when_option_off() {
        let mut e = Engine::new(Config {
            ignore_key_repeat: false,
            ..Config::default()
        });
        press(&mut e, b'A' as u32, 1000);
        let o = press(&mut e, b'A' as u32, 1030);
        assert!(o.chatter);
    }

    /// テンキー無視オプション
    #[test]
    fn tenkey_ignore() {
        let mut e = Engine::new(Config {
            ignore_ten_key: true,
            ..Config::default()
        });
        press(&mut e, 0x60, 1000); // Num0
        let o = press(&mut e, 0x60, 1005);
        assert!(!o.chatter);
    }

    /// VK(255)ダミーイベントは処理対象外
    #[test]
    fn dummy_vk255_ignored() {
        let mut e = engine();
        assert_eq!(e.process(255, 0, 1000, 1000), None);
    }

    /// MS-IME確定アンドゥ: Ctrl押下中のBS連続はキャンセルしない
    #[test]
    fn ime_undo_ctrl_bs_not_cancelled() {
        let mut e = engine();
        press(&mut e, VK_LCONTROL, 900);
        press(&mut e, VK_BACK, 950); // 通常BS
        release(&mut e, VK_BACK, 960);
        release(&mut e, VK_LCONTROL, 970);

        // IME確定アンドゥ: BS再押下がチャタ閾値未満かつ nextDownDisableFlg=1 経路
        press(&mut e, VK_BACK, 1000); // チャタ閾値内だが…
        let o = press(&mut e, VK_BACK, 1005);
        assert!(!o.cancelled || !o.chatter, "確定アンドゥ中のBSはキャンセル禁止");
    }

    /// UP監視: UP直後の余分なDOWNを検出し、UPイベント自体のキャンセルは高精度タイマー時のみ
    #[test]
    fn up_chatter_detection_and_accuracy_gate() {
        let cfg = Config {
            key_up_chatter: true,
            high_accuracy: true,
            updown_threshold: 8,
            ..Config::default()
        };
        let mut e = Engine::new(cfg.clone());
        press(&mut e, b'B' as u32, 1000);
        release(&mut e, b'B' as u32, 1100);
        // 3ms後の再押下 → [UP]-[DOWN]チャタ (accuracy非依存)
        let o = press(&mut e, b'B' as u32, 1103);
        assert!(o.chatter);
        assert!(o.cancelled);

        // 短押下の直後UP → 高精度タイマー時のみUP自体がキャンセルされる
        let mut e3 = Engine::new(cfg.clone());
        press(&mut e3, b'B' as u32, 2000);
        let up = release(&mut e3, b'B' as u32, 2001);
        assert!(up.chatter, "1ms押下のUPはチャタ扱い");
        assert!(up.cancelled, "高精度タイマー時はUPイベントが握り潰される");

        // 高精度タイマーOFF時はUPイベントのキャンセルは行われない (元仕様)
        // ※[UP]-[DOWN]によるDOWN検出自体はaccuracy非依存で発生する
        let mut e2 = Engine::new(Config {
            key_up_chatter: true,
            high_accuracy: false,
            ..Config::default()
        });
        press(&mut e2, b'B' as u32, 1000);
        release(&mut e2, b'B' as u32, 1100);
        let o2 = press(&mut e2, b'B' as u32, 1103);
        assert!(o2.chatter, "[UP]-[DOWN]検出はaccuracy非依存");
        assert!(o2.cancelled);

        press(&mut e2, b'B' as u32, 2000);
        let up2 = release(&mut e2, b'B' as u32, 2001);
        assert!(!up2.cancelled, "非高精度時はUPキャンセルなし");
        assert!(!up2.chatter);
    }

    /// キャンセルOFFでも判定(bit30)は立つ (readme: 「キャンセルOFFでも判定自体は行っています」)
    #[test]
    fn judgement_without_cancel() {
        let mut e = Engine::new(Config {
            chatter_cancel: false,
            ..Config::default()
        });
        press(&mut e, b'C' as u32, 500);
        release(&mut e, b'C' as u32, 505); // UPを挟まないとリピート免除になるため挟む
        let o = press(&mut e, b'C' as u32, 510);
        assert!(o.chatter);
        assert!(!o.cancelled);
    }

    /// stop相当: 無効時は何も通知しない (endHook互換)
    #[test]
    fn disabled_engine_reports_nothing() {
        let mut e = engine();
        e.set_enabled(false);
        // enabled フラグはフック側 (hook.rs) で判定するため engine 自体は判定継続。
        // ここでは API 存在確認のみ。
        assert!(!e.is_enabled());
    }
}
