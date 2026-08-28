//! タスクトレイ — tray-icon クレートによる実装。
//! Windows ではアイコン生成スレッド上で Win32 メッセージループが必要なため専用スレッドで動かす。

use windows::Win32::UI::WindowsAndMessaging::{DispatchMessageW, GetMessageW, TranslateMessage, MSG};

pub const MENU_SHOW: &str = "ccchattttter-show";
pub const MENU_TOGGLE: &str = "ccchattttter-toggle";
pub const MENU_QUIT: &str = "ccchattttter-quit";

fn log_file(msg: &str) {
    if let Some(p) = crate::settings::Settings::default_path().and_then(|p| p.parent().map(|d| d.join("ccchattttter.log"))) {
        let _ = std::fs::OpenOptions::new().create(true).append(true).open(&p).and_then(|mut f| {
            use std::io::Write;
            writeln!(f, "[{}] {msg}", chrono_like_now())
        });
    }
}
fn chrono_like_now() -> String {
    // windows SystemTime で簡易時刻
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs();
    format!("{secs}")
}

pub fn spawn(icon_rgba: Vec<u8>, icon_size: (u32, u32), ui_tx: async_channel::Sender<crate::ui::UiEvent>) {
    std::thread::Builder::new()
        .name("tray".into())
        .spawn(move || {
            let menu = tray_icon::menu::Menu::new();
            let show =
                tray_icon::menu::MenuItem::with_id(MENU_SHOW, "ウィンドウ表示", true, None);
            let toggle = tray_icon::menu::MenuItem::with_id(
                MENU_TOGGLE,
                "抑止 有効/無効 切替",
                true,
                None,
            );
            let quit = tray_icon::menu::MenuItem::with_id(MENU_QUIT, "終了", true, None);
            let sep = tray_icon::menu::PredefinedMenuItem::separator();
            let _ = menu.append_items(&[&show, &toggle, &sep, &quit]);

            let icon = tray_icon::Icon::from_rgba(icon_rgba, icon_size.0, icon_size.1)
                .expect("invalid icon rgba");

            // _tray はスレッド寿命まで生存させる必要がある
            let _tray = tray_icon::TrayIconBuilder::new()
                .with_tooltip("ccchattttter")
                .with_icon(icon)
                .with_menu(Box::new(menu))
                .with_menu_on_left_click(false)
                .build()
                .expect("failed to create tray icon");
            log_file("tray created");

            // メニュー/クリックイベントを ui_tx へ中継 (bridge の select! と二重化して確実に届ける)
            {
                let ui_tx = ui_tx.clone();
                std::thread::Builder::new()
                    .name("tray-events".into())
                    .spawn(move || {
                        let menu_rx = tray_icon::menu::MenuEvent::receiver();
                        let tray_rx = tray_icon::TrayIconEvent::receiver();
                        log_file("tray-events forwarder started");
                        loop {
                            crossbeam_channel::select! {
                                recv(menu_rx) -> r => if let Ok(m) = r {
                                    let id = m.id().as_ref().to_string();
                                    log_file(&format!("menu event {id}"));
                                    eprintln!("[tray-events] menu {id}");
                                    match id.as_str() {
                                        MENU_SHOW => { let _ = ui_tx.send_blocking(crate::ui::UiEvent::ShowWindow); }
                                        MENU_TOGGLE => { let _ = ui_tx.send_blocking(crate::ui::UiEvent::ToggleRunning); }
                                        MENU_QUIT => { let _ = ui_tx.send_blocking(crate::ui::UiEvent::Quit); }
                                        _ => {}
                                    }
                                },
                                recv(tray_rx) -> r => if let Ok(t) = r {
                                    log_file(&format!("tray event {t:?}"));
                                    use tray_icon::{MouseButton, TrayIconEvent};
                                    let show = match t {
                                        TrayIconEvent::Click { button: MouseButton::Left, .. }
                                        | TrayIconEvent::DoubleClick { button: MouseButton::Left, .. } => true,
                                        _ => false,
                                    };
                                    if show {
                                        let _ = ui_tx.send_blocking(crate::ui::UiEvent::ShowWindow);
                                    }
                                },
                            }
                        }
                    })
                    .expect("spawn tray-events");
            }

            // win32 メッセージポンプ (トレイの隠しウィンドウ用)
            let mut msg = MSG::default();
            unsafe {
                while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                    let _ = TranslateMessage(&msg);
                    DispatchMessageW(&msg);
                }
            }
        })
        .expect("spawn tray thread");
}
