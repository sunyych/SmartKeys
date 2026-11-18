use std::collections::VecDeque;

use super::*;

struct FakeDesktop {
    windows: VecDeque<Option<u32>>,
    process_ids: VecDeque<Option<u32>>,
    process_name: Option<String>,
    main_window: bool,
    modifier_held: bool,
    layout_scan: i16,
    layout_queries: Vec<(u32, u16)>,
    main_window_checks: usize,
    send_results: VecDeque<usize>,
    sent: Vec<Vec<KeyEvent>>,
}

impl Default for FakeDesktop {
    fn default() -> Self {
        Self {
            windows: [Some(42), Some(42)].into(),
            process_ids: [Some(7), Some(7)].into(),
            process_name: None,
            main_window: true,
            modifier_held: false,
            layout_scan: 0xdb,
            layout_queries: Vec::new(),
            main_window_checks: 0,
            send_results: VecDeque::new(),
            sent: Vec::new(),
        }
    }
}

impl ShortcutPlatform for FakeDesktop {
    type Window = u32;

    fn foreground(&mut self) -> Option<Self::Window> {
        self.windows.pop_front().flatten()
    }

    fn process_id(&mut self, _window: Self::Window) -> Option<u32> {
        self.process_ids.pop_front().flatten()
    }

    fn process_name(&mut self, _process_id: u32) -> Option<String> {
        self.process_name.clone()
    }

    fn is_main_window(&mut self, _window: Self::Window) -> bool {
        self.main_window_checks += 1;
        self.main_window
    }

    fn modifier_held(&mut self) -> bool {
        self.modifier_held
    }

    fn character_key(&mut self, window: Self::Window, character: u16) -> Option<(Key, u8)> {
        self.layout_queries.push((window, character));
        layout_key(self.layout_scan)
    }

    fn send(&mut self, events: &[KeyEvent]) -> usize {
        self.sent.push(events.to_vec());
        self.send_results.pop_front().unwrap_or(events.len())
    }
}

fn down(virtual_key: u16) -> KeyEvent {
    KeyEvent {
        key: Key::ordinary(virtual_key),
        up: false,
    }
}

fn up(virtual_key: u16) -> KeyEvent {
    KeyEvent {
        key: Key::ordinary(virtual_key),
        up: true,
    }
}

#[test]
fn accepts_canonical_keys_and_targets_from_the_shared_fixture() {
    let fixture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../test/fixtures/windows_shortcuts.json"
    ))
    .unwrap();
    for example in fixture["accepted"].as_array().unwrap() {
        let key = example["key"].as_str().unwrap();
        let modifiers = example["modifiers"]
            .as_array()
            .unwrap()
            .iter()
            .fold(0, |mask, name| {
                mask | match name.as_str().unwrap() {
                    "CTRL" => CTRL,
                    "ALT" => ALT,
                    "SHIFT" => SHIFT,
                    _ => panic!("Unknown modifier: {name}"),
                }
            });
        let processes: Vec<_> = example["allowedProcesses"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|name| name.as_str().unwrap())
            .collect();
        let allowed = processes.join(",");
        let mut desktop = FakeDesktop {
            process_name: processes
                .first()
                .map(|process| process.to_ascii_uppercase()),
            ..FakeDesktop::default()
        };
        let shortcut = Shortcut::parse(key, u32::from(modifiers), &allowed).unwrap();
        assert_eq!(
            deliver(&mut desktop, &shortcut),
            Outcome::Delivered,
            "{}",
            example["id"]
        );
        assert_eq!(desktop.sent.len(), 1);
        assert_eq!(
            desktop.sent[0].len(),
            2 + 2 * modifiers.count_ones() as usize
        );
        let requires_main_window = example["requireMainWindow"].as_bool().unwrap_or(false);
        assert_eq!(
            desktop.main_window_checks,
            usize::from(requires_main_window)
        );
    }
}

#[test]
fn invalid_abi_inputs_are_rejected() {
    for (key, modifiers, allowed) in [
        ("A", 8, ""),
        ("A", 256, ""),
        ("A", 0, "chatgpt,"),
        ("A", 0, "app.exe"),
        ("F13", 0, ""),
        ("ENTER A", 0, ""),
        ("", 0, ""),
    ] {
        assert!(Shortcut::parse(key, modifiers, allowed).is_none());
    }
}

#[test]
fn sends_extended_navigation_and_balanced_modifier_events() {
    let mut desktop = FakeDesktop::default();
    let shortcut = Shortcut::parse("LEFT", u32::from(CTRL | ALT | SHIFT), "").unwrap();
    assert_eq!(deliver(&mut desktop, &shortcut), Outcome::Delivered);
    let left = Key::extended(0x25);
    assert_eq!(
        desktop.sent,
        [vec![
            down(0x11),
            down(0x12),
            down(0x10),
            KeyEvent {
                key: left,
                up: false
            },
            KeyEvent {
                key: left,
                up: true
            },
            up(0x10),
            up(0x12),
            up(0x11)
        ]]
    );
    assert!(desktop.layout_queries.is_empty());
}

#[test]
fn punctuation_uses_the_target_window_layout_and_its_implied_modifiers() {
    let mut desktop = FakeDesktop {
        layout_scan: 0x01db,
        ..FakeDesktop::default()
    };
    let shortcut = Shortcut::parse("[", u32::from(CTRL), "").unwrap();
    assert_eq!(deliver(&mut desktop, &shortcut), Outcome::Delivered);
    assert_eq!(desktop.layout_queries, [(42, u16::from(b'['))]);
    assert_eq!(
        desktop.sent[0],
        [
            down(0x11),
            down(0x10),
            down(0xdb),
            up(0xdb),
            up(0x10),
            up(0x11)
        ]
    );
    assert_eq!(layout_key(0x06db), Some((Key::ordinary(0xdb), CTRL | ALT)));
    assert_eq!(layout_key(-1), None);
    assert_eq!(layout_key(0x08db), None);
}

#[test]
fn validation_failures_send_nothing() {
    let guarded = Shortcut::parse("N", u32::from(CTRL), "codex,chatgpt").unwrap();
    let current_main = || FakeDesktop {
        process_name: Some("ChatGPT".into()),
        ..FakeDesktop::default()
    };
    let cases = [
        (
            FakeDesktop {
                windows: [None].into(),
                ..current_main()
            },
            Outcome::WrongForeground,
        ),
        (
            FakeDesktop {
                process_name: Some("editor".into()),
                ..current_main()
            },
            Outcome::WrongForeground,
        ),
        (
            FakeDesktop {
                process_name: None,
                ..current_main()
            },
            Outcome::WrongForeground,
        ),
        (
            FakeDesktop {
                main_window: false,
                ..current_main()
            },
            Outcome::NotMainChatGptWindow,
        ),
        (
            FakeDesktop {
                modifier_held: true,
                ..current_main()
            },
            Outcome::ModifierHeld,
        ),
        (
            FakeDesktop {
                windows: [Some(42), Some(12)].into(),
                ..current_main()
            },
            Outcome::ForegroundChanged,
        ),
        (
            FakeDesktop {
                process_ids: [Some(7), Some(8)].into(),
                ..current_main()
            },
            Outcome::ForegroundChanged,
        ),
        (
            FakeDesktop {
                layout_scan: -1,
                ..current_main()
            },
            Outcome::UnavailableLayoutKey,
        ),
    ];
    for (mut desktop, expected) in cases {
        assert_eq!(deliver(&mut desktop, &guarded), expected);
        assert!(desktop.sent.is_empty());
    }
}

#[test]
fn partial_delivery_releases_only_keys_in_the_inserted_prefix() {
    let shortcut = Shortcut::parse("ENTER", u32::from(CTRL | ALT), "").unwrap();
    let remaining_releases = [
        vec![],
        vec![up(0x11)],
        vec![up(0x12), up(0x11)],
        vec![up(0x0d), up(0x12), up(0x11)],
        vec![up(0x12), up(0x11)],
        vec![up(0x11)],
    ];
    for (inserted, expected_release) in remaining_releases.into_iter().enumerate() {
        let mut desktop = FakeDesktop {
            send_results: [inserted].into(),
            ..FakeDesktop::default()
        };
        let outcome = deliver(&mut desktop, &shortcut);
        if inserted == 0 {
            assert_eq!(outcome, Outcome::NotDelivered);
            assert_eq!(desktop.sent.len(), 1);
        } else {
            assert_eq!(outcome, Outcome::Partial);
            assert_eq!(desktop.sent.len(), 2);
            assert_eq!(desktop.sent[1], expected_release);
        }
    }
}

#[test]
fn failed_partial_release_reports_incomplete_delivery_without_retry() {
    let shortcut = Shortcut::parse("ENTER", u32::from(CTRL), "").unwrap();
    let mut desktop = FakeDesktop {
        send_results: [2, 0].into(),
        ..FakeDesktop::default()
    };
    assert_eq!(
        deliver(&mut desktop, &shortcut),
        Outcome::PartialReleaseFailed
    );
    assert_eq!(desktop.sent.len(), 2);
    assert_eq!(desktop.sent[1], [up(0x0d), up(0x11)]);
}
