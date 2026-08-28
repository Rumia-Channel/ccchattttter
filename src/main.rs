#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
//! ccchattttter — キーボードチャタリング抑止ツール (GPUI 移植版)
//!
//! 旧構成 (ccchattttter.exe + hooookk.dll) を単一バイナリに統合したもの。
//! 設定ファイルは旧 ccchattttter.ini と互換。
//!
//! 起動すると即座にタスクトレイへ格納され、トレイのダブルクリックまたは
//! メニュー「ウィンドウ表示」で GUI を呼び出す。×ボタンは終了ではなく
//! トレイへの再格納。終了はトレイメニューの「終了」から行う。
//! 多重起動時は既存インスタンスのウィンドウを呼び出して終了する。
//! ゲームモード用ホットキーは ini の `HotKey` (既定 Ctrl+Alt+G) で抑止を
//! 開始/停止できる。

mod engine;
mod hook;
mod hotkey;
mod keyname;
mod settings;
mod tray;
mod ui;
mod win32;

use std::iter::once;

use gpui::{point, px, prelude::*, size, App, Application, Bounds, WindowBounds, WindowOptions};
use windows::core::{HSTRING, PCWSTR};
use windows::Win32::Foundation::{GetLastError, ERROR_ALREADY_EXISTS, WAIT_OBJECT_0};
use windows::Win32::System::Threading::{
    CreateEventW, CreateMutexW, EVENT_MODIFY_STATE, INFINITE, OpenEventW, SetEvent,
    SYNCHRONIZATION_SYNCHRONIZE, WaitForSingleObject,
};
use windows::Win32::UI::WindowsAndMessaging::{
    MessageBoxW, MB_ICONERROR, MB_OK, MB_SETFOREGROUND,
};

const SHOW_EVENT_NAME: &str = "ccchattttter-show-event";

fn log_file_main(msg: &str) {
    if let Some(p) = settings::Settings::default_path().and_then(|p| p.parent().map(|d| d.join("ccchattttter.log"))) {
        let _ = std::fs::OpenOptions::new().create(true).append(true).open(&p).and_then(|mut f| {
            use std::io::Write;
            let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs();
            writeln!(f, "[{secs}] {msg}")
        });
    }
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(once(0)).collect()
}

fn save_ini(snapshot: &std::sync::Arc<parking_lot::Mutex<settings::Settings>>) {
    if let Some(p) = settings::Settings::default_path() {
        let _ = snapshot.lock().save(&p);
    }
}

/// 元 dpr の CreateMutex による多重起動抑止。
/// 既に起動済みの場合はシグナルを送ってウィンドウを呼び出してから終了する。
fn single_instance() {
    unsafe {
        let name = HSTRING::from("ccchattttter");
        if CreateMutexW(None, false, &name).is_err()
            || GetLastError() == ERROR_ALREADY_EXISTS
        {
            // 既存インスタンスへ表示要求を送る
            let ev = OpenEventW(
                SYNCHRONIZATION_SYNCHRONIZE | EVENT_MODIFY_STATE,
                false,
                PCWSTR(HSTRING::from(SHOW_EVENT_NAME).as_ptr()),
            );
            if let Ok(ev) = ev {
                let _ = SetEvent(ev);
                std::process::exit(0);
            }
            let text = wide("既に実行されています。");
            let caption = wide("多重起動エラー - ccchattttter");
            MessageBoxW(
                None,
                PCWSTR(text.as_ptr()),
                PCWSTR(caption.as_ptr()),
                MB_ICONERROR | MB_OK | MB_SETFOREGROUND,
            );
            std::process::exit(1);
        }
    }
}

fn load_icon() -> (Vec<u8>, u32, u32) {
    const ICO: &[u8] = include_bytes!("../assets/icon.ico");
    match image::load_from_memory(ICO) {
        Ok(img) => {
            let rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();
            (rgba.into_raw(), w, h)
        }
        Err(_) => (vec![0, 0, 0, 255], 1, 1),
    }
}

fn main() {
    single_instance();

    let ini_path = settings::Settings::default_path();
    let st = ini_path
        .as_deref()
        .map(settings::Settings::load)
        .unwrap_or_default();

    // フックスレッド起動 (元 startHook 相当。起動時から有効)
    let cfg = engine::Config {
        chater_threshold: st.chattering_threshold,
        repeat_threshold: st.key_repeat_threshold,
        updown_threshold: st.key_updown_threshold,
        ignore_key_repeat: st.ignore_key_repeat,
        ignore_ten_key: st.ignore_ten_key,
        high_accuracy: st.accuracy,
        chatter_cancel: st.chatter_cancel,
        key_up_chatter: st.view_up,
    };
    let (key_tx, key_rx) = crossbeam_channel::unbounded::<engine::Outcome>();
    hook::spawn(engine::Engine::new(cfg), key_tx);

    let (icon_rgba, icon_w, icon_h) = load_icon();

    let (ui_tx, ui_rx) = async_channel::unbounded::<ui::UiEvent>();

    tray::spawn(icon_rgba, (icon_w, icon_h), ui_tx.clone());

    // ゲームモード用グローバルホットキー
    hotkey::spawn(&st.hotkey, ui_tx.clone());
    // 二重起動シグナル → ウィンドウ表示
    {
        let ui_tx = ui_tx.clone();
        std::thread::spawn(move || unsafe {
            if let Ok(ev) = CreateEventW(None, false, false, &HSTRING::from(SHOW_EVENT_NAME)) {
                loop {
                    if WaitForSingleObject(ev, INFINITE) != WAIT_OBJECT_0 {
                        break;
                    }
                    let _ = ui_tx.send_blocking(ui::UiEvent::ShowWindow);
                }
            }
        });
    }

    // ブリッジ: フック/トレイの各ソースを UiEvent ストリームへ集約
    {
        let ui_tx = ui_tx.clone();
        std::thread::spawn(move || {
            let menu_rx = tray_icon::menu::MenuEvent::receiver();
            let tray_rx = tray_icon::TrayIconEvent::receiver();
            loop {
                crossbeam_channel::select! {
                    recv(key_rx) -> r => if let Ok(o) = r {
                        let _ = ui_tx.send_blocking(ui::UiEvent::Key(o));
                    },
                    recv(menu_rx) -> r => if let Ok(m) = r {
                        let id = m.id().as_ref().to_string();
                        eprintln!("[bridge] menu id={id:?}");
                        log_file_main(&format!("[bridge] menu {id}"));
                        match id.as_str() {
                            tray::MENU_SHOW => { let _ = ui_tx.send_blocking(ui::UiEvent::ShowWindow); }
                            tray::MENU_TOGGLE => { let _ = ui_tx.send_blocking(ui::UiEvent::ToggleRunning); }
                            tray::MENU_QUIT => { let _ = ui_tx.send_blocking(ui::UiEvent::Quit); }
                            other => { eprintln!("[bridge] unknown menu id {other:?}"); }
                        }
                    },
                    recv(tray_rx) -> r => if let Ok(t) = r {
                        use tray_icon::{MouseButton, TrayIconEvent};
                        // 左クリック/ダブルクリックでウィンドウを出す
                        let show = match t {
                            TrayIconEvent::Click { button: MouseButton::Left, .. }
                            | TrayIconEvent::DoubleClick { button: MouseButton::Left, .. } => true,
                            _ => false,
                        };
                        if show {
                            let _ = ui_tx.send_blocking(ui::UiEvent::ShowWindow);
                        }
                    },
                }
            }
        });
    }

    Application::new().run(move |cx: &mut App| {
        let w = st.width as f32;
        let h = st.height as f32;
        let bounds = if st.top >= 0 && st.left >= 0 {
            Bounds {
                origin: point(px(st.left as f32), px(st.top as f32)),
                size: size(px(w), px(h)),
            }
        } else {
            Bounds::centered(None, size(px(w), px(h)), cx)
        };

        let snapshot = std::sync::Arc::new(parking_lot::Mutex::new(st.clone()));

        let handle = cx
            .open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(bounds)),
                    titlebar: Some(gpui::TitlebarOptions {
                        title: Some("ccchattttter".into()),
                        appears_transparent: false,
                        ..Default::default()
                    }),
                    ..Default::default()
                },
                {
                    let st = st.clone();
                    move |window, cx| {
                        // ×ボタンは終了ではなくトレイへ再格納
                        window.on_window_should_close(cx, |_window, cx| {
                            win32::set_main_window_visible(false);
                            if let Some(s) = cx.try_global::<ui::Session>() {
                                save_ini(&s.settings);
                            }
                            false // クロスをキャンセル
                        });
                        cx.new(|_| ui::ChattApp::new(st))
                    }
                },
            )
            .expect("open main window");

        // gpui 0.2 の Windows バックエンドは最小化状態で生成されるため
        // いったん明示的に表示してから、起動時はトレイへ格納する
        let _ = handle.update(cx, |_, window, _| window.activate_window());
        win32::set_main_window_visible(false);

        let entity = handle.entity(cx).expect("root entity");
        cx.set_global(ui::Session {
            settings: snapshot.clone(),
        });

        // UiEvent 消費ループ
        cx.spawn(async move |cx| {
            loop {
                match ui_rx.recv().await {
                    Ok(ui::UiEvent::Key(o)) => {
                        let _ = entity.update(cx, |app, cx| app.apply_key(o, cx));
                    }
                    Ok(ui::UiEvent::ShowWindow) => {
                        let _ = cx.update(|cx| {
                            win32::set_main_window_visible(true);
                            if let Some(w) = cx.windows().first().copied() {
                                let _ = cx.update_window(w, |_view, window, _app| {
                                    window.activate_window();
                                });
                            }
                        });
                    }
                    Ok(ui::UiEvent::ToggleRunning) => {
                        let _ = entity.update(cx, |app, cx| app.toggle_running(cx));
                    }
                    Ok(ui::UiEvent::Quit) => {
                        eprintln!("[ui] Quit received");
                        log_file_main("[ui] Quit received");
                        let _ = cx.update(|cx| {
                            save_ini(&snapshot);
                            cx.quit();
                        });
                        log_file_main("[ui] cx.quit called, will exit");
                        // gpui 0.2 の quit が隠しウィンドウ状態で効かない場合の保険
                        std::thread::sleep(std::time::Duration::from_millis(200));
                        std::process::exit(0);
                    }
                    Err(_) => break,
                }
            }
        })
        .detach();
    });
}
