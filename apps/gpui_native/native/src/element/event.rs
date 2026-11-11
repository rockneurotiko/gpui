use crate::*;

#[cfg(all(feature = "real-gpui", feature = "components"))]
pub(crate) fn attach_accessible_action_target(
    element: gpui::Stateful<gpui::Div>,
    test_id: String,
    event: String,
    accessibility: super::AccessibilitySemantics,
    runtime: SharedRuntime,
    window_id: u64,
    focus: gpui::FocusHandle,
) -> gpui::Stateful<gpui::Div> {
    use gpui::{AccessibleAction, InteractiveElement, StatefulInteractiveElement};

    let enabled = !accessibility.disabled;
    let mut element = super::apply_accessibility_semantics(element, accessibility);
    element = element.debug_selector(|| test_id.clone());
    let focus = focus.tab_stop(enabled);
    if enabled {
        if let Ok(mut handles) = runtime.focus_handles.lock() {
            handles.insert((window_id, test_id), focus.clone());
        }
        element = element.track_focus(&focus);

        let keyboard_runtime = runtime.clone();
        let keyboard_event = event.clone();
        element = element
            .key_context("GPUIAccessibleControl")
            .tab_index(0)
            .focus_visible(|style| style.border_2().border_color(gpui::rgb(0x60a5fa)))
            .on_key_down(move |key, _window, cx| {
                if matches!(key.keystroke.key.as_str(), "enter" | "space") {
                    emit_click_event(&keyboard_runtime, window_id, &keyboard_event);
                    cx.stop_propagation();
                }
            })
            .on_a11y_action(AccessibleAction::Click, move |_data, _window, _cx| {
                emit_click_event(&runtime, window_id, &event);
            });
    }

    element
}

/// Colors a container takes on while it is hovered, pressed, focused, or contains focus.
#[cfg(feature = "real-gpui")]
#[derive(Clone, Copy, Default)]
pub(crate) struct StateColors {
    background: Option<u32>,
    color: Option<u32>,
    border_color: Option<u32>,
    opacity: Option<f32>,
}

#[cfg(feature = "real-gpui")]
impl StateColors {
    pub(crate) fn from_style(style: &StyleAttrs) -> Self {
        Self {
            background: style.hover_background,
            color: style.hover_color,
            border_color: style.hover_border_color,
            opacity: style.hover_opacity,
        }
    }

    pub(crate) fn from_active(style: &StyleAttrs) -> Self {
        Self {
            background: style.active_background,
            color: style.active_color,
            border_color: style.active_border_color,
            opacity: style.active_opacity,
        }
    }

    pub(crate) fn from_focus(style: &StyleAttrs) -> Self {
        Self {
            background: style.focus_background,
            color: style.focus_color,
            border_color: style.focus_border_color,
            opacity: style.focus_opacity,
        }
    }

    pub(crate) fn from_focus_within(style: &StyleAttrs) -> Self {
        Self {
            background: style.focus_within_background,
            color: style.focus_within_color,
            border_color: style.focus_within_border_color,
            opacity: style.focus_within_opacity,
        }
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.background.is_none()
            && self.color.is_none()
            && self.border_color.is_none()
            && self.opacity.is_none()
    }

    pub(crate) fn apply(self, mut style: gpui::StyleRefinement) -> gpui::StyleRefinement {
        use gpui::Styled;

        if let Some(value) = self.background {
            style = style.bg(gpui::rgba(value));
        }
        if let Some(value) = self.color {
            style = style.text_color(gpui::rgba(value));
        }
        if let Some(value) = self.border_color {
            style = style.border_color(gpui::rgba(value));
        }
        if let Some(value) = self.opacity {
            style = style.opacity(value);
        }
        style
    }
}

#[cfg(feature = "real-gpui")]
#[allow(clippy::too_many_arguments)]
pub(crate) fn apply_click_event(
    element: gpui::Div,
    element_id: String,
    event: Option<String>,
    accessibility: super::AccessibilitySemantics,
    runtime: SharedRuntime,
    window_id: u64,
    motion: super::ContainerMotion,
    window_control: Option<String>,
    hover: StateColors,
    active: StateColors,
    focus: StateColors,
    focus_within: StateColors,
) -> gpui::AnyElement {
    use gpui::{AccessibleAction, InteractiveElement, StatefulInteractiveElement};

    let debug_selector = element_id.clone();
    let element_id = if event.is_some() {
        format!("gpui-elixir-click-{window_id}-{element_id}")
    } else {
        element_id
    };
    let element = element.debug_selector(|| debug_selector).id(element_id);
    let element = if hover.is_empty() {
        element
    } else {
        element.hover(move |style| hover.apply(style))
    };
    // Pressed styles need the element id set above.
    let element = if active.is_empty() {
        element
    } else {
        element.active(move |style| active.apply(style))
    };
    // Focus styles only apply once the element tracks a focus handle.
    let element = if focus.is_empty() {
        element
    } else {
        element.focus(move |style| focus.apply(style))
    };
    let element = if focus_within.is_empty() {
        element
    } else {
        element.in_focus(move |style| focus_within.apply(style))
    };
    let element = super::apply_window_control(element, window_control, runtime.clone(), window_id);

    if let Some(event) = event {
        let enabled = !accessibility.disabled;
        let activatable = enabled
            && accessibility
                .role
                .as_ref()
                .is_some_and(AccessibilityRole::is_activatable);
        let element = super::apply_accessibility_semantics(element, accessibility.clone());
        let element = if activatable {
            let keyboard_runtime = runtime.clone();
            let keyboard_event = event.clone();
            element
                .key_context("GPUIAccessibleControl")
                .tab_index(0)
                .focus_visible(|style| style.border_2().border_color(gpui::rgb(0x60a5fa)))
                .on_key_down(move |key, _window, cx| {
                    if matches!(key.keystroke.key.as_str(), "enter" | "space") {
                        emit_click_event(&keyboard_runtime, window_id, &keyboard_event);
                        cx.stop_propagation();
                    }
                })
        } else {
            element
        };
        let pointer_runtime = runtime.clone();
        let pointer_event = event.clone();

        let element = if enabled {
            element
                .on_click(move |_event, _window, _cx| {
                    emit_click_event(&pointer_runtime, window_id, &pointer_event);
                })
                .on_a11y_action(AccessibleAction::Click, move |_data, _window, _cx| {
                    emit_click_event(&runtime, window_id, &event);
                })
        } else {
            element
        };

        let actions = if enabled {
            vec![AccessibleAction::Click]
        } else {
            vec![]
        };
        super::apply_container_motion(element, motion, accessibility, actions)
    } else {
        super::apply_container_motion(element, motion, accessibility, vec![])
    }
}

#[cfg(feature = "real-gpui")]
pub(crate) fn emit_click_event(runtime: &SharedRuntime, window_id: u64, event: &str) {
    let _ = push_event(
        runtime,
        NativeEvent::Click {
            window_id,
            event: event.to_string(),
        },
    );
}

#[cfg(feature = "real-gpui")]
pub(crate) fn apply_input_events(
    element: gpui::Div,
    input_id: String,
    keydown: Option<String>,
    keyup: Option<String>,
    runtime: SharedRuntime,
    window_id: u64,
) -> gpui::AnyElement {
    use gpui::{InteractiveElement, IntoElement};

    let mut element = element.key_context("GPUIInput").tab_index(0).id(input_id);

    if let Some(event) = keydown {
        let runtime = runtime.clone();
        element = element.on_key_down(move |key_event, _window, _cx| {
            let value = key_event
                .keystroke
                .key_char
                .clone()
                .or_else(|| Some(key_event.keystroke.key.clone()))
                .map(EventValue::String);

            let _ = push_event(
                &runtime,
                NativeEvent::Input {
                    kind: InputKind::KeyDown,
                    window_id,
                    event: event.clone(),
                    value,
                },
            );
        });
    }

    if let Some(event) = keyup {
        element = element.on_key_up(move |key_event, _window, _cx| {
            let value = key_event
                .keystroke
                .key_char
                .clone()
                .or_else(|| Some(key_event.keystroke.key.clone()))
                .map(EventValue::String);

            let _ = push_event(
                &runtime,
                NativeEvent::Input {
                    kind: InputKind::KeyUp,
                    window_id,
                    event: event.clone(),
                    value,
                },
            );
        });
    }

    element.into_any_element()
}

#[cfg(all(test, feature = "real-gpui"))]
mod tests {
    use super::emit_click_event;
    use crate::{event::NativeEvent, runtime::RuntimeState, AccessibilityRole};
    use std::sync::Arc;

    #[test]
    fn accessible_action_attachment_uses_the_shared_click_event_path() {
        let runtime = Arc::new(RuntimeState::new());
        emit_click_event(&runtime, 9, "open-settings");

        let events = runtime.events.lock().expect("event queue");
        assert!(matches!(
            events.as_slice(),
            [NativeEvent::Click { window_id: 9, event }] if event == "open-settings"
        ));
    }

    #[test]
    fn generated_role_policy_only_tab_stops_simple_activation_controls() {
        for role in [
            AccessibilityRole::Button,
            AccessibilityRole::Checkbox,
            AccessibilityRole::Link,
            AccessibilityRole::Radio,
            AccessibilityRole::Switch,
        ] {
            assert!(role.is_activatable());
        }

        for role in [
            AccessibilityRole::Group,
            AccessibilityRole::List,
            AccessibilityRole::TabList,
            AccessibilityRole::Tree,
            AccessibilityRole::Slider,
        ] {
            assert!(!role.is_activatable());
        }
    }

    #[test]
    fn pointer_and_accessible_activation_share_the_same_native_event_path() {
        let runtime = Arc::new(RuntimeState::new());

        emit_click_event(&runtime, 7, "toggle");
        emit_click_event(&runtime, 7, "toggle");

        let events = runtime.events.lock().expect("event queue");
        assert_eq!(events.len(), 2);
        for event in events.iter() {
            assert!(matches!(
                event,
                NativeEvent::Click { window_id: 7, event } if event == "toggle"
            ));
        }
    }
}
