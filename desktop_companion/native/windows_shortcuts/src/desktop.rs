use std::collections::HashSet;

pub const MAX_POINTER_INPUTS: usize = 32;
pub const MAX_OUTPUT_BYTES: u32 = 2 * 1024 * 1024;

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RawPointerInput {
    pub kind: i32,
    pub x: i32,
    pub y: i32,
    pub secondary: i32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PointerEvent {
    Move { x: i32, y: i32 },
    Wheel { delta: i32 },
    Button { secondary: bool, down: bool },
}

#[repr(i32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PointerOutcome {
    Delivered = 0,
    Invalid = 1,
    Rejected = 2,
    Partial = 3,
    PartialReleaseFailed = 4,
    Unsupported = 5,
    PermissionDenied = 6,
}

pub fn prepare_pointer_batch(inputs: &[RawPointerInput]) -> Option<Vec<PointerEvent>> {
    if inputs.is_empty() || inputs.len() > MAX_POINTER_INPUTS {
        return None;
    }
    let mut events = Vec::with_capacity(inputs.len() * 2);
    for &RawPointerInput {
        kind,
        x,
        y,
        secondary,
    } in inputs
    {
        let in_range = |axis| (-127..=127).contains(&axis);
        match kind {
            0 if secondary == 0 && in_range(x) && in_range(y) => {
                events.push(PointerEvent::Move { x, y });
            }
            1 if secondary == 0 && x == 0 && y != 0 && in_range(y) => {
                events.push(PointerEvent::Wheel { delta: y * 120 });
            }
            2 if x == 0 && y == 0 && matches!(secondary, 0 | 1) => {
                let secondary = secondary == 1;
                events.push(PointerEvent::Button {
                    secondary,
                    down: true,
                });
                events.push(PointerEvent::Button {
                    secondary,
                    down: false,
                });
            }
            _ => return None,
        }
    }
    Some(events)
}

pub fn deliver_pointer(
    inputs: &[RawPointerInput],
    send: impl FnMut(&[PointerEvent]) -> usize,
) -> PointerOutcome {
    let Some(events) = prepare_pointer_batch(inputs) else {
        return PointerOutcome::Invalid;
    };
    deliver_pointer_events(&events, send)
}

pub(crate) fn deliver_pointer_events(
    events: &[PointerEvent],
    mut send: impl FnMut(&[PointerEvent]) -> usize,
) -> PointerOutcome {
    let inserted = send(events);
    if inserted == events.len() {
        return PointerOutcome::Delivered;
    }
    if inserted == 0 || inserted > events.len() {
        return PointerOutcome::Rejected;
    }
    // Each button presses and releases consecutively. Only a trailing press
    // can need repair. No movement, wheel event, or click is replayed.
    if let PointerEvent::Button {
        secondary,
        down: true,
    } = events[inserted - 1]
        && send(&[PointerEvent::Button {
            secondary,
            down: false,
        }]) != 1
    {
        return PointerOutcome::PartialReleaseFailed;
    }
    PointerOutcome::Partial
}

pub fn supports_linux_x11(
    display: Option<&str>,
    wayland_display: Option<&str>,
    session_type: Option<&str>,
) -> bool {
    display.is_some_and(|value| !value.is_empty())
        && !wayland_display.is_some_and(|value| !value.is_empty())
        && !session_type.is_some_and(|value| value.trim().eq_ignore_ascii_case("wayland"))
}

fn valid_name(value: &str) -> bool {
    !value.is_empty() && !value.chars().any(|character| character.is_ascii_control())
}

fn normalize_process_name(value: &str) -> Option<String> {
    let value = value.trim();
    (valid_name(value) && !value.contains(['/', '\\'])).then(|| value.to_lowercase())
}

pub fn normalize_process_list(names: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    names
        .iter()
        .filter_map(|value| normalize_process_name(value))
        .filter(|value| seen.insert(value.clone()))
        .collect()
}

pub fn foreground_process_name(name: Option<&str>, is_main_window: bool) -> Option<String> {
    let name = normalize_process_name(name?)?;
    let stem = name.strip_suffix(".exe").unwrap_or(&name);
    (!stem.is_empty() && (stem != "chatgpt" || is_main_window)).then(|| stem.to_owned())
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AppPath {
    pub name: String,
    pub path: String,
}

fn is_absolute_windows_executable(path: &str) -> bool {
    if !valid_name(path)
        || !path.to_ascii_lowercase().ends_with(".exe")
        || path.contains(['"', '<', '>', '|', '*', '?'])
        || path.encode_utf16().count() > 4088
    {
        return false;
    }
    let separator = |value| matches!(value, '\\' | '/');
    let components = if let [drive, b':', b'\\' | b'/', ..] = path.as_bytes() {
        if !drive.is_ascii_alphabetic() || path[2..].contains(':') {
            return false;
        }
        &path[3..]
    } else if path.starts_with("\\\\") || path.starts_with("//") {
        let network = &path[2..];
        let mut parts = network.split(separator);
        let valid_component = |value: &str| !value.is_empty() && value != "." && value != "..";
        if !parts.next().is_some_and(valid_component)
            || !parts.next().is_some_and(valid_component)
            || !parts.clone().any(valid_component)
            || network.contains(':')
        {
            return false;
        }
        network
    } else {
        return false;
    };
    !components.is_empty()
}

pub fn normalize_app_paths(paths: &[AppPath]) -> Vec<AppPath> {
    let mut seen = HashSet::new();
    paths
        .iter()
        .filter_map(|entry| {
            let name = entry.name.trim();
            let target = entry.path.trim();
            let target = target
                .strip_prefix('"')
                .and_then(|value| value.strip_suffix('"'))
                .unwrap_or(target)
                .trim();
            if !valid_name(name)
                || name.encode_utf16().count() > 256
                || !is_absolute_windows_executable(target)
                || !seen.insert(target.to_lowercase())
            {
                return None;
            }
            Some(AppPath {
                name: name.to_owned(),
                path: target.to_owned(),
            })
        })
        .collect()
}

pub fn output_length(length: usize, capacity: usize) -> Option<i32> {
    if length > capacity {
        return None;
    }
    i32::try_from(length).ok()
}
