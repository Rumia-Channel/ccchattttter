//! GPUI ウィンドウ UI — old/Unit1.pas TForm1 の移植。
//! テキスト入力欄はステッパーボタンに置換、リストは uniform_list を使用。

use std::path::Path;

use gpui::{
    div, prelude::*, rgb, uniform_list, ClickEvent, Context, Div, Global, IntoElement,
    ParentElement, Render, SharedString, Stateful, Styled, Window,
};
use parking_lot::Mutex;
use windows::Win32::Media::Audio::{PlaySoundW, SND_ASYNC, SND_FILENAME};
use windows::core::PCWSTR;

use crate::engine::{Config, Outcome, Transition};
use crate::hook;
use crate::keyname;
use crate::settings::Settings;

const BG: u32 = 0x00f0f0f0;
const PANEL: u32 = 0x00e2e2e6;
const BTN_ON: u32 = 0x00398a41;
const BTN_OFF: u32 = 0x00a83c32;
const BTN_NEUTRAL: u32 = 0x00606066;
const CHATTER_COLOR: u32 = 0x00c02020;

/// アプリ全体から参照するセッション状態 (トレイイベント→UI更新の架け橋)
pub struct Session {
    pub settings: std::sync::Arc<Mutex<Settings>>,
}
impl Global for Session {}

/// ブリッジスレッドから UI へ流すイベント
#[derive(Debug)]
pub enum UiEvent {
    Key(Outcome),
    ShowWindow,
    ToggleRunning,
    Quit,
}

#[derive(Clone, Debug)]
struct LogEntry {
    line: String,
    chatter: bool,
}

pub struct ChattApp {
    pub st: Settings,
    running: bool,
    logs: Vec<LogEntry>,
    chats: Vec<LogEntry>,
}

impl ChattApp {
    pub fn new(st: Settings) -> Self {
        let running = hook::with_engine(|e| e.is_enabled()).unwrap_or(true);
        Self {
            st,
            running,
            logs: Vec::new(),
            chats: Vec::new(),
        }
    }

    /// 設定変更をエンジンへ反映 (DLLのset*エクスポート相当) し、終了時保存用へ公開
    fn sync_config(&self, cx: &mut Context<Self>) {
        let cfg = Config {
            chater_threshold: self.st.chattering_threshold,
            repeat_threshold: self.st.key_repeat_threshold,
            updown_threshold: self.st.key_updown_threshold,
            ignore_key_repeat: self.st.ignore_key_repeat,
            ignore_ten_key: self.st.ignore_ten_key,
            high_accuracy: self.st.accuracy,
            chatter_cancel: self.st.chatter_cancel,
            key_up_chatter: self.st.view_up,
        };
        hook::with_engine(|e| {
            e.set_config(cfg);
            e.set_enabled(self.running);
        });
        if let Some(session) = cx.try_global::<Session>() {
            *session.settings.lock() = self.st.clone();
        }
    }

    /// 元 WndProc のログ振り分け処理
    pub fn apply_key(&mut self, o: Outcome, cx: &mut Context<Self>) {
        let line = keyname::format_line(&o);
        let entry = LogEntry {
            line,
            chatter: o.chatter,
        };
        let up = o.transition == Transition::Up;

        // 押下一覧 (左): DOWNは常に、UPはUP監視時のみ。ログチェック時のみ記録。
        let show_main = if !up {
            self.st.logging
        } else {
            self.st.logging && self.st.view_up
        };
        if show_main {
            push_trim(&mut self.logs, entry.clone(), self.st.log_max);
        }

        // チャタ一覧 (右): 判定ビットが立ったもの。UPはUP監視時のみ。
        if (self.st.logging || self.st.log_chatter) && o.chatter && (!up || self.st.view_up) {
            push_trim(&mut self.chats, entry, self.st.log_max);
        }

        // 警告音: DOWN時のチャタ検出で再生
        if !up && o.chatter && self.st.sound_on && Path::new(&self.st.wave_file_name).is_file() {
            play_sound(&self.st.wave_file_name);
        }

        cx.notify();
    }


    pub fn toggle_running(&mut self, cx: &mut Context<Self>) {
        self.running = !self.running;
        self.sync_config(cx);
        cx.notify();
    }

    // ---- UI部品 -----------------------------------------------------------

    fn button(
        id: &'static str,
        label: &str,
        color: u32,
        handler: impl Fn(&ClickEvent, &mut Window, &mut gpui::App) + 'static,
    ) -> Stateful<Div> {
        div()
            .id(id)
            .px_3()
            .py_1()
            .rounded_sm()
            .text_color(rgb(0x00ffffff))
            .cursor_pointer()
            .bg(rgb(color))
            .on_click(handler)
            .child(SharedString::from(label.to_string()))
    }

    fn checkbox(
        this_id: &'static str,
        label: &str,
        checked: bool,
        cx: &mut Context<Self>,
    ) -> Stateful<Div> {
        let handler = cx.listener(move |this, _e: &ClickEvent, _w, _cx| match this_id {
            "ignore-repeat" => this.st.ignore_key_repeat = !this.st.ignore_key_repeat,
            "chatter-cancel" => this.st.chatter_cancel = !this.st.chatter_cancel,
            "view-up" => this.st.view_up = !this.st.view_up,
            "accuracy" => this.st.accuracy = !this.st.accuracy,
            "ignore-tenkey" => this.st.ignore_ten_key = !this.st.ignore_ten_key,
            "logging" => this.st.logging = !this.st.logging,
            "log-chatter" => this.st.log_chatter = !this.st.log_chatter,
            "sound-on" => this.st.sound_on = !this.st.sound_on,
            _ => {}
        });
        div()
            .id(this_id)
            .flex()
            .items_center()
            .gap_1()
            .px_1()
            .py_0p5()
            .cursor_pointer()
            .hover(|s| s.bg(rgb(PANEL)))
            .rounded_sm()
            .on_click(handler)
            .child(
                div()
                    .size_3()
                    .flex_none()
                    .border_1()
                    .border_color(rgb(0x00444444))
                    .rounded_xs()
                    .when(checked, |d| d.bg(rgb(BTN_ON)))
                    .when(!checked, |d| d.bg(rgb(0x00ffffff))),
            )
            .child(SharedString::from(label.to_string()))
    }

    fn stepper(
        &self,
        dec_id: &'static str,
        inc_id: &'static str,
        label: &str,
        value: u32,
        cx: &mut Context<Self>,
    ) -> Div {
        let dec = cx.listener(move |this, _e: &ClickEvent, _w, cx| {
            adjust(this, dec_id, false, cx);
        });
        let inc = cx.listener(move |this, _e: &ClickEvent, _w, cx| {
            adjust(this, inc_id, true, cx);
        });
        div()
            .flex()
            .items_center()
            .gap_1()
            .child(SharedString::from(label.to_string()))
            .child(Self::button(dec_id, "-", BTN_NEUTRAL, dec))
            .child(
                div()
                    .min_w_12()
                    .px_2()
                    .py_0p5()
                    .bg(rgb(0x00ffffff))
                    .border_1()
                    .border_color(rgb(0x00999999))
                    .rounded_xs()
                    .text_center()
                    .child(format!("{value}")),
            )
            .child(Self::button(inc_id, "+", BTN_NEUTRAL, inc))
    }

    fn log_list(
        id: &'static str,
        entries: &[LogEntry],
        title: &str,
    ) -> impl IntoElement + use<> {
        let len = entries.len();
        let entries_owned: Vec<LogEntry> = entries.to_vec();
        div()
            .flex()
            .flex_col()
            .flex_grow()
            .min_h_0()
            .min_w_0()
            .border_1()
            .border_color(rgb(0x00999999))
            .bg(rgb(0x00ffffff))
            .child(
                div()
                    .px_1()
                    .text_xs()
                    .bg(rgb(PANEL))
                    .child(SharedString::from(title.to_string())),
            )
            .child(
                uniform_list(id, len.max(1), move |range, _window, _cx| {
                    range
                        .filter_map(|i| {
                            let e = entries_owned.get(i)?;
                            let mut row =
                                div().px_1().text_xs().child(e.line.replace('\t', "  "));
                            if e.chatter {
                                row = row.text_color(rgb(CHATTER_COLOR));
                            }
                            Some(row.into_any_element())
                        })
                        .collect()
                })
                .h_full(),
            )
    }
}

fn adjust(app: &mut ChattApp, what: &str, inc: bool, cx: &mut Context<ChattApp>) {
    let dir: i64 = if inc { 1 } else { -1 };
    let clamp_u32 = |v: i64| v.clamp(0, u32::MAX as i64) as u32;
    match what {
        "chater" => {
            app.st.chattering_threshold =
                clamp_u32(app.st.chattering_threshold as i64 + dir * 5).max(1)
        }
        "repeat" => app.st.key_repeat_threshold =
            clamp_u32(app.st.key_repeat_threshold as i64 + dir * 5),
        "updown" => {
            app.st.key_updown_threshold =
                clamp_u32(app.st.key_updown_threshold as i64 + dir).max(1)
        }
        "logmax" => {
            app.st.log_max = clamp_u32(app.st.log_max as i64 + dir * 100);
            let cap = if app.st.log_max == 0 {
                usize::MAX
            } else {
                app.st.log_max as usize
            };
            app.logs.truncate(cap);
            app.chats.truncate(cap);
        }
        _ => {}
    }
    app.sync_config(cx);
    cx.notify();
}

fn push_trim(v: &mut Vec<LogEntry>, e: LogEntry, max: u32) {
    v.push(e);
    let max = max as usize;
    if max > 0 {
        while v.len() > max {
            v.remove(0);
        }
    }
}

impl Render for ChattApp {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let toggle_label = if self.running { "stop" } else { "start" };
        let toggle_color = if self.running { BTN_OFF } else { BTN_ON };

        let clear_handler = cx.listener(|this, _e: &ClickEvent, _w, cx| {
            if this.logs.is_empty() {
                this.chats.clear();
            } else {
                this.logs.clear();
            }
            cx.notify();
        });

        let sound_pick = cx.listener(|this, _e: &ClickEvent, _w, cx| {
            if let Some(file) = rfd::FileDialog::new()
                .add_filter("wave", &["wav"])
                .set_title("警告音の選択")
                .pick_file()
            {
                this.st.wave_file_name = file.to_string_lossy().into_owned();
                this.sync_config(cx);
                cx.notify();
            }
        });

        // リスト領域の表示ロジック (元 chkLogingClick 相当)
        let show_lists = self.st.logging || self.st.log_chatter;
        let left_hidden = !self.st.logging && self.st.log_chatter;

        let logs_snapshot: Vec<LogEntry> = self.logs.clone();
        let chats_snapshot: Vec<LogEntry> = self.chats.clone();

        div()
            .id("root")
            .font_family("Yu Gothic UI")
            .text_color(rgb(0x00101010))
            .bg(rgb(BG))
            .size_full()
            .flex()
            .flex_col()
            .gap_1()
            .p_2()
            .text_sm()
            .child(
                // 操作ボタン行
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(Self::button(
                        "toggle",
                        toggle_label,
                        toggle_color,
                        cx.listener(|this, _e: &ClickEvent, _w, cx| this.toggle_running(cx)),
                    ))
                    .child(Self::button("clear", "clear", BTN_NEUTRAL, clear_handler))
                    .child(if self.running {
                        div().text_color(rgb(BTN_ON)).child("監視中")
                    } else {
                        div().text_color(rgb(BTN_OFF)).child("停止中")
                    }),
            )
            .child(
                // 閾値行
                div()
                    .flex()
                    .flex_wrap()
                    .gap_x_3()
                    .gap_y_1()
                    .items_center()
                    .child(self.stepper(
                        "dec-chater",
                        "inc-chater",
                        "DOWN-UP-DOWN(ms)",
                        self.st.chattering_threshold,
                        cx,
                    ))
                    .child(self.stepper(
                        "dec-repeat",
                        "inc-repeat",
                        "DOWN-DOWN(ms)",
                        self.st.key_repeat_threshold,
                        cx,
                    ))
                    .child(self.stepper(
                        "dec-updown",
                        "inc-updown",
                        "UP-DOWN(ms)",
                        self.st.key_updown_threshold,
                        cx,
                    ))
                    .child(self.stepper(
                        "dec-logmax",
                        "inc-logmax",
                        "ログ行数",
                        self.st.log_max,
                        cx,
                    )),
            )
            .child(
                // オプション群
                div()
                    .flex()
                    .flex_wrap()
                    .gap_x_2()
                    .gap_y_1()
                    .items_center()
                    .child(Self::checkbox(
                        "ignore-repeat",
                        "リピート無視",
                        self.st.ignore_key_repeat,
                        cx,
                    ))
                    .child(Self::checkbox(
                        "chatter-cancel",
                        "チャタキャンセル",
                        self.st.chatter_cancel,
                        cx,
                    ))
                    .child(Self::checkbox("view-up", "UP監視", self.st.view_up, cx))
                    .child(Self::checkbox(
                        "accuracy",
                        "高精度タイマー",
                        self.st.accuracy,
                        cx,
                    ))
                    .child(Self::checkbox(
                        "ignore-tenkey",
                        "テンキー無視",
                        self.st.ignore_ten_key,
                        cx,
                    ))
                    .child(Self::checkbox("logging", "ログ", self.st.logging, cx))
                    .child(
                        div()
                            .when(self.st.logging, |d| d.opacity(0.4))
                            .child(Self::checkbox(
                                "log-chatter",
                                "チャタのみ記録",
                                self.st.log_chatter,
                                cx,
                            )),
                    )
                    .child(Self::checkbox("sound-on", "警告音", self.st.sound_on, cx))
                    .child(Self::button("sound-pick", "音選択", BTN_NEUTRAL, sound_pick)),
            )
            .child(
                // ログ領域
                if show_lists {
                    div()
                        .flex()
                        .flex_row()
                        .flex_1()
                        .min_h_0()
                        .gap_1()
                        .when(left_hidden, |d| {
                            d.child(Self::log_list("chat-list", &chats_snapshot, "チャタ一覧"))
                        })
                        .when(!left_hidden, |d| {
                            d.child(Self::log_list("key-list", &logs_snapshot, "押下一覧"))
                                .child(Self::log_list(
                                    "chat-list",
                                    &chats_snapshot,
                                    "チャタ一覧",
                                ))
                        })
                        .into_any_element()
                } else {
                    div()
                        .flex_1()
                        .min_h_0()
                        .flex()
                        .items_center()
                        .justify_center()
                        .text_color(rgb(0x00888888))
                        .child("ログ無効 (「ログ」または「チャタのみ記録」を有効にすると表示されます)")
                        .into_any_element()
                },
            )
    }
}

fn play_sound(path: &str) {
    let wide: Vec<u16> = path.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        let _ = PlaySoundW(
            PCWSTR(wide.as_ptr()),
            None,
            SND_FILENAME | SND_ASYNC,
        );
    }
}
