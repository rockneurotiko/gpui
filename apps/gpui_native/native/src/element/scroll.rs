//! Scroll containers keep a handle per stable ID so the host can report and reset their offset.

use crate::*;
use std::{cell::RefCell, collections::HashMap, rc::Rc, time::Duration};

/// Offset reports are at most this far apart; the final offset of a burst always follows.
const REPORT_INTERVAL: Duration = Duration::from_millis(50);

// shortcut: containers past this many are left untracked (still scrollable), raise it if a
// view legitimately keeps more scroll containers alive at once.
const MAX_TRACKED: usize = 1024;

#[derive(Default)]
pub(crate) struct ReportState {
    sent: Option<f64>,
    latest: f64,
    timer_running: bool,
}

#[derive(Clone)]
pub(crate) struct ScrollEntry {
    pub(crate) handle: gpui::ScrollHandle,
    pub(crate) report: Rc<RefCell<ReportState>>,
}

thread_local! {
    // GPUI renders and handles window commands on one thread, so handles never cross threads.
    static SCROLLS: RefCell<HashMap<(u64, String), ScrollEntry>> = RefCell::new(HashMap::new());
}

/// Returns the persistent handle for a scroll container, or `None` once the table is full.
pub(crate) fn entry(window_id: u64, id: &str) -> Option<ScrollEntry> {
    SCROLLS.with(|scrolls| {
        let mut scrolls = scrolls.borrow_mut();
        let key = (window_id, id.to_string());
        if !scrolls.contains_key(&key) && scrolls.len() >= MAX_TRACKED {
            return None;
        }
        Some(
            scrolls
                .entry(key)
                .or_insert_with(|| ScrollEntry {
                    handle: gpui::ScrollHandle::new(),
                    report: Rc::new(RefCell::new(ReportState::default())),
                })
                .clone(),
        )
    })
}

/// Scrolls every container with this ID to the top; an unknown ID does nothing.
pub(crate) fn scroll_to_top(id: &str) {
    SCROLLS.with(|scrolls| {
        for ((_window_id, key), entry) in scrolls.borrow().iter() {
            if key == id {
                let mut offset = entry.handle.offset();
                offset.y = gpui::px(0.);
                entry.handle.set_offset(offset);
            }
        }
    });
}

/// Called every frame: reports the offset immediately when idle, otherwise leaves it to the
/// running timer, which sends the latest offset when the interval ends.
pub(crate) fn observe(
    entry: &ScrollEntry,
    runtime: &SharedRuntime,
    window_id: u64,
    event: &str,
    cx: &mut gpui::App,
) {
    let offset = f64::from(-f32::from(entry.handle.offset().y)).max(0.0);
    let mut report = entry.report.borrow_mut();
    report.latest = offset;
    if report.timer_running || report.sent == Some(offset) {
        return;
    }
    report.sent = Some(offset);
    report.timer_running = true;
    drop(report);
    emit(runtime, window_id, event, offset);

    let report = entry.report.clone();
    let runtime = runtime.clone();
    let event = event.to_string();
    let timer = cx.background_executor().clone();
    cx.spawn(async move |_cx| loop {
        timer.timer(REPORT_INTERVAL).await;
        let mut report = report.borrow_mut();
        if report.sent == Some(report.latest) {
            report.timer_running = false;
            return;
        }
        report.sent = Some(report.latest);
        emit(&runtime, window_id, &event, report.latest);
    })
    .detach();
}

fn emit(runtime: &SharedRuntime, window_id: u64, event: &str, offset_y: f64) {
    let _ = push_event(
        runtime,
        NativeEvent::Scroll {
            window_id,
            event: event.to_string(),
            offset_y,
        },
    );
}
