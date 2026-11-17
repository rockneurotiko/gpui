//! Scroll containers keep a handle per stable ID so the host can report and reset their offset.

use crate::*;
use std::{
    cell::{Cell, RefCell},
    collections::HashMap,
    rc::Rc,
    time::Duration,
};

/// Offset reports are at most this far apart; the final offset of a burst always follows.
const REPORT_INTERVAL: Duration = Duration::from_millis(50);

// Containers past this many live ones are left untracked (still scrollable) and a warning is
// printed once; raise it if a view legitimately keeps more scroll containers alive at once.
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

#[derive(Default)]
struct Registry {
    entries: HashMap<(u64, String), (ScrollEntry, u64)>,
    /// Latest frame number per window; entries stamped with an older one were not rendered.
    frames: HashMap<u64, u64>,
}

thread_local! {
    // GPUI renders and handles window commands on one thread, so handles never cross threads.
    static SCROLLS: RefCell<Registry> = RefCell::new(Registry::default());
    static WARNED: Cell<bool> = const { Cell::new(false) };
}

/// Marks the start of a window's render; containers not requested again before `end_frame` go.
pub(crate) fn begin_frame(window_id: u64) {
    SCROLLS.with(|scrolls| *scrolls.borrow_mut().frames.entry(window_id).or_insert(0) += 1);
}

/// Drops the window's containers that this frame did not render.
pub(crate) fn end_frame(window_id: u64) {
    SCROLLS.with(|scrolls| {
        let registry = &mut *scrolls.borrow_mut();
        let frame = registry.frames.get(&window_id).copied().unwrap_or(0);
        registry
            .entries
            .retain(|(window, _), (_, seen)| *window != window_id || *seen == frame);
    });
}

/// Forgets everything held for a closed window.
pub(crate) fn drop_window(window_id: u64) {
    SCROLLS.with(|scrolls| {
        let registry = &mut *scrolls.borrow_mut();
        registry.frames.remove(&window_id);
        registry
            .entries
            .retain(|(window, _), _| *window != window_id);
    });
}

/// Returns the persistent handle for a scroll container, or `None` once the table is full.
pub(crate) fn entry(window_id: u64, id: &str) -> Option<ScrollEntry> {
    SCROLLS.with(|scrolls| {
        let registry = &mut *scrolls.borrow_mut();
        let frame = registry.frames.get(&window_id).copied().unwrap_or(0);
        let key = (window_id, id.to_string());
        if !registry.entries.contains_key(&key) && registry.entries.len() >= MAX_TRACKED {
            if !WARNED.replace(true) {
                eprintln!(
                    "gpui: more than {MAX_TRACKED} scroll containers; extra ones are not tracked"
                );
            }
            return None;
        }
        let (entry, seen) = registry.entries.entry(key).or_insert_with(|| {
            (
                ScrollEntry {
                    handle: gpui::ScrollHandle::new(),
                    report: Rc::new(RefCell::new(ReportState::default())),
                },
                frame,
            )
        });
        *seen = frame;
        Some(entry.clone())
    })
}

/// Scrolls every container with this ID to the top; an unknown ID does nothing.
pub(crate) fn scroll_to_top(id: &str) {
    SCROLLS.with(|scrolls| {
        for ((_window_id, key), (entry, _)) in scrolls.borrow().entries.iter() {
            if key == id {
                let mut offset = entry.handle.offset();
                offset.y = gpui::px(0.);
                entry.handle.set_offset(offset);
            }
        }
    });
}

/// GPUI offsets are zero or negative; reports are pixels from the top, exactly +0.0 at rest.
fn report_offset(y: f32) -> f64 {
    if y < 0.0 {
        f64::from(-y)
    } else {
        0.0
    }
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
    let offset = report_offset(f32::from(entry.handle.offset().y));
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rest_offset_is_positive_zero() {
        for y in [0.0_f32, -0.0] {
            let offset = report_offset(y);
            assert_eq!(offset, 0.0);
            assert!(offset.is_sign_positive());
        }
        assert_eq!(report_offset(12.5), 0.0);
        assert_eq!(report_offset(-12.5), 12.5);
    }

    #[test]
    fn remounting_with_new_ids_does_not_grow_the_registry() {
        let count = || SCROLLS.with(|s| s.borrow().entries.len());
        for round in 0..(MAX_TRACKED * 3) {
            begin_frame(7);
            assert!(entry(7, &format!("row-{round}")).is_some());
            assert!(entry(7, "stable").is_some());
            end_frame(7);
            assert_eq!(count(), 2);
        }
        begin_frame(8);
        entry(8, "other").unwrap();
        end_frame(8);
        drop_window(7);
        assert_eq!(count(), 1);
        drop_window(8);
        assert_eq!(count(), 0);
    }
}
