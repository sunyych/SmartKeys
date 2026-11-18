const CTRL: u8 = 1;
const ALT: u8 = 2;
const SHIFT: u8 = 4;
const MODIFIERS: u8 = CTRL | ALT | SHIFT;

#[repr(i32)]
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Outcome {
    Delivered = 0,
    Invalid = 1,
    WrongForeground = 2,
    NotMainChatGptWindow = 3,
    ModifierHeld = 4,
    ForegroundChanged = 5,
    UnavailableLayoutKey = 6,
    NotDelivered = 7,
    Partial = 8,
    PartialReleaseFailed = 9,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Key {
    pub virtual_key: u16,
    pub extended: bool,
}

impl Key {
    fn ordinary(virtual_key: u16) -> Self {
        Self {
            virtual_key,
            extended: false,
        }
    }

    fn extended(virtual_key: u16) -> Self {
        Self {
            virtual_key,
            extended: true,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct KeyEvent {
    pub key: Key,
    pub up: bool,
}

#[derive(Debug, PartialEq, Eq)]
enum LogicalKey {
    Virtual(Key),
    Character(u16),
}

impl LogicalKey {
    fn parse(name: &str) -> Option<Self> {
        // Named keys use the Win32 virtual-key codes. Navigation keys require
        // the extended flag for the dedicated key, rather than the keypad key.
        let key = match name {
            "BACKSPACE" => Key::ordinary(0x08),
            "TAB" => Key::ordinary(0x09),
            "ENTER" => Key::ordinary(0x0D),
            "ESC" => Key::ordinary(0x1B),
            "SPACE" => Key::ordinary(0x20),
            "PAGEUP" => Key::extended(0x21),
            "PAGEDOWN" => Key::extended(0x22),
            "END" => Key::extended(0x23),
            "HOME" => Key::extended(0x24),
            "LEFT" => Key::extended(0x25),
            "UP" => Key::extended(0x26),
            "RIGHT" => Key::extended(0x27),
            "DOWN" => Key::extended(0x28),
            "DELETE" => Key::extended(0x2E),
            "F1" => Key::ordinary(0x70),
            "F2" => Key::ordinary(0x71),
            "F3" => Key::ordinary(0x72),
            "F4" => Key::ordinary(0x73),
            "F5" => Key::ordinary(0x74),
            "F6" => Key::ordinary(0x75),
            "F7" => Key::ordinary(0x76),
            "F8" => Key::ordinary(0x77),
            "F9" => Key::ordinary(0x78),
            "F10" => Key::ordinary(0x79),
            "F11" => Key::ordinary(0x7A),
            "F12" => Key::ordinary(0x7B),
            _ => {
                let [character] = name.as_bytes() else {
                    return None;
                };
                return match character {
                    b'A'..=b'Z' | b'0'..=b'9' | b'[' | b']' | b'`' | b'/' | b'\\' | b'-' | b'=' => {
                        Some(Self::Character(u16::from(character.to_ascii_lowercase())))
                    }
                    _ => None,
                };
            }
        };
        Some(Self::Virtual(key))
    }
}

pub(crate) struct Shortcut<'a> {
    key: LogicalKey,
    modifiers: u8,
    allowed_processes: &'a str,
}

impl<'a> Shortcut<'a> {
    pub fn parse(key: &str, modifiers: u32, allowed_processes: &'a str) -> Option<Self> {
        let modifiers = u8::try_from(modifiers).ok()?;
        if modifiers & !MODIFIERS != 0
            || allowed_processes.len() > 256
            || (!allowed_processes.is_empty()
                && allowed_processes.split(',').any(|name| {
                    name.is_empty()
                        || !name
                            .bytes()
                            .all(|part| part.is_ascii_alphanumeric() || b" -_".contains(&part))
                }))
        {
            return None;
        }
        Some(Self {
            key: LogicalKey::parse(key)?,
            modifiers,
            allowed_processes,
        })
    }
}

pub(crate) trait ShortcutPlatform {
    type Window: Copy + PartialEq;

    fn foreground(&mut self) -> Option<Self::Window>;
    fn process_id(&mut self, window: Self::Window) -> Option<u32>;
    fn process_name(&mut self, process_id: u32) -> Option<String>;
    fn is_main_window(&mut self, window: Self::Window) -> bool;
    fn modifier_held(&mut self) -> bool;
    fn character_key(&mut self, window: Self::Window, character: u16) -> Option<(Key, u8)>;
    fn send(&mut self, events: &[KeyEvent]) -> usize;
}

pub(crate) fn deliver(platform: &mut impl ShortcutPlatform, shortcut: &Shortcut<'_>) -> Outcome {
    let Some(window) = platform.foreground() else {
        return Outcome::WrongForeground;
    };
    let mut expected_pid = None;
    if !shortcut.allowed_processes.is_empty() {
        let Some(process_id) = platform.process_id(window) else {
            return Outcome::WrongForeground;
        };
        let Some(name) = platform.process_name(process_id) else {
            return Outcome::WrongForeground;
        };
        if !shortcut
            .allowed_processes
            .split(',')
            .any(|allowed| allowed.eq_ignore_ascii_case(&name))
        {
            return Outcome::WrongForeground;
        }
        if shortcut
            .allowed_processes
            .split(',')
            .any(|name| name == "chatgpt")
            && !platform.is_main_window(window)
        {
            return Outcome::NotMainChatGptWindow;
        }
        expected_pid = Some(process_id);
    }

    let (key, modifiers) = match shortcut.key {
        LogicalKey::Virtual(key) => (key, shortcut.modifiers),
        LogicalKey::Character(character) => {
            let Some((key, implied)) = platform.character_key(window, character) else {
                return Outcome::UnavailableLayoutKey;
            };
            (key, shortcut.modifiers | implied)
        }
    };
    let events = key_events(key, modifiers);
    if platform.modifier_held() {
        return Outcome::ModifierHeld;
    }
    if expected_pid.is_some_and(|expected| platform.process_id(window) != Some(expected))
        || platform.foreground() != Some(window)
    {
        return Outcome::ForegroundChanged;
    }
    let inserted = platform.send(&events);
    if inserted == events.len() {
        return Outcome::Delivered;
    }
    if inserted == 0 {
        return Outcome::NotDelivered;
    }

    // SendInput serially inserts events. Release any still-held keys in the
    // inserted prefix, in reverse order, without replaying the shortcut.
    let mut held = Vec::new();
    for event in events.iter().take(inserted) {
        if event.up {
            held.retain(|&key| key != event.key);
        } else {
            held.push(event.key);
        }
    }
    let release: Vec<_> = held
        .into_iter()
        .rev()
        .map(|key| KeyEvent { key, up: true })
        .collect();
    if !release.is_empty() && platform.send(&release) != release.len() {
        return Outcome::PartialReleaseFailed;
    }
    Outcome::Partial
}

fn key_events(key: Key, modifiers: u8) -> Vec<KeyEvent> {
    let modifier_keys = [
        (CTRL, Key::ordinary(0x11)),
        (ALT, Key::ordinary(0x12)),
        (SHIFT, Key::ordinary(0x10)),
    ];
    let mut events = Vec::with_capacity(8);
    for (flag, modifier) in modifier_keys {
        if modifiers & flag != 0 {
            events.push(KeyEvent {
                key: modifier,
                up: false,
            });
        }
    }
    events.push(KeyEvent { key, up: false });
    events.push(KeyEvent { key, up: true });
    for (flag, modifier) in modifier_keys.into_iter().rev() {
        if modifiers & flag != 0 {
            events.push(KeyEvent {
                key: modifier,
                up: true,
            });
        }
    }
    events
}

/// Maps VkKeyScanExW's Shift/Ctrl/Alt bits to the ABI modifier mask.
#[cfg(any(windows, test))]
pub(crate) fn layout_key(scan: i16) -> Option<(Key, u8)> {
    let [virtual_key, layout_modifiers] = scan.to_le_bytes();
    if virtual_key == 0 || virtual_key == 0xff || layout_modifiers & !7 != 0 {
        return None;
    }
    let implied = ((layout_modifiers & 1) << 2)
        | ((layout_modifiers & 2) >> 1)
        | ((layout_modifiers & 4) >> 1);
    Some((Key::ordinary(u16::from(virtual_key)), implied))
}

#[cfg(test)]
mod tests;
