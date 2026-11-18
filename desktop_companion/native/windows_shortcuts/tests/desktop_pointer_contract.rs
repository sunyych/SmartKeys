use lumiakeys_windows_shortcuts::desktop::{
    PointerEvent, PointerOutcome, RawPointerInput, deliver_pointer, prepare_pointer_batch,
};

fn input(kind: i32, x: i32, y: i32, secondary: i32) -> RawPointerInput {
    RawPointerInput {
        kind,
        x,
        y,
        secondary,
    }
}

fn button(secondary: bool, down: bool) -> PointerEvent {
    PointerEvent::Button { secondary, down }
}

#[test]
fn pointer_batch_preserves_order_axes_and_direction() {
    let inputs = [
        input(0, -127, 127, 0),
        input(1, 0, -127, 0),
        input(2, 0, 0, 0),
        input(0, 0, 0, 0),
        input(1, 0, 127, 0),
        input(2, 0, 0, 1),
    ];
    let expected = [
        PointerEvent::Move { x: -127, y: 127 },
        PointerEvent::Wheel { delta: -15_240 },
        button(false, true),
        button(false, false),
        PointerEvent::Move { x: 0, y: 0 },
        PointerEvent::Wheel { delta: 15_240 },
        button(true, true),
        button(true, false),
    ];
    assert_eq!(prepare_pointer_batch(&inputs).unwrap(), expected);
    let mut calls = 0;
    let outcome = deliver_pointer(&inputs, |events| {
        calls += 1;
        assert_eq!(events, expected);
        events.len()
    });
    assert_eq!(outcome, PointerOutcome::Delivered);
    assert_eq!(calls, 1);
}

#[test]
fn pointer_batch_bound_counts_commands_before_button_expansion() {
    let first = [input(1, 0, 1, 0)];
    assert_eq!(
        prepare_pointer_batch(&first).unwrap(),
        [PointerEvent::Wheel { delta: 120 }],
    );
    let maximum: Vec<_> = (0..32).map(|_| input(2, 0, 0, 1)).collect();
    let events = prepare_pointer_batch(&maximum).unwrap();
    assert_eq!(events, [button(true, true), button(true, false)].repeat(32));

    let exceeded: Vec<_> = (0..33).map(|_| input(0, 1, -1, 0)).collect();
    for batch in [&[][..], exceeded.as_slice()] {
        assert!(prepare_pointer_batch(batch).is_none());
        assert_eq!(
            deliver_pointer(batch, |_| panic!("invalid batch reached the sink")),
            PointerOutcome::Invalid,
        );
    }
}

#[test]
fn any_malformed_item_rejects_the_entire_batch_before_delivery() {
    let malformed = [
        input(-1, 0, 0, 0),
        input(3, 0, 0, 0),
        input(0, -128, 0, 0),
        input(0, 0, 128, 0),
        input(0, i32::MIN, i32::MAX, 0),
        input(0, 1, 1, 1),
        input(1, 0, 0, 0),
        input(1, 1, 1, 0),
        input(1, 0, -128, 0),
        input(1, 0, 128, 0),
        input(1, 0, 1, 1),
        input(2, 1, 0, 0),
        input(2, 0, 1, 1),
        input(2, 0, 0, -1),
        input(2, 0, 0, 2),
    ];
    for (i, invalid) in malformed.into_iter().enumerate() {
        let batch = [input(0, 1, -1, 0), invalid, input(2, 0, 0, 0)];
        assert!(prepare_pointer_batch(&batch).is_none(), "case {i}");
        assert_eq!(
            deliver_pointer(&batch, |_| panic!("invalid case {i} reached the sink")),
            PointerOutcome::Invalid,
        );
    }
}

#[test]
fn partial_delivery_only_releases_the_last_inserted_unpaired_button() {
    let batch = [
        input(0, 1, 2, 0),
        input(2, 0, 0, 0),
        input(2, 0, 0, 1),
        input(1, 0, -1, 0),
    ];
    let events = prepare_pointer_batch(&batch).unwrap();
    let release_for_prefix = [
        None,
        None,
        Some(button(false, false)),
        None,
        Some(button(true, false)),
        None,
        None,
    ];
    assert_eq!(events.len() + 1, release_for_prefix.len());
    for (inserted, release) in release_for_prefix.into_iter().enumerate() {
        let mut calls = Vec::new();
        let outcome = deliver_pointer(&batch, |attempt| {
            calls.push(attempt.to_vec());
            if calls.len() == 1 {
                inserted
            } else {
                attempt.len()
            }
        });
        let expected_outcome = if inserted == 0 {
            PointerOutcome::Rejected
        } else if inserted == events.len() {
            PointerOutcome::Delivered
        } else {
            PointerOutcome::Partial
        };
        assert_eq!(outcome, expected_outcome, "inserted prefix {inserted}");
        let mut expected_calls = vec![events.clone()];
        if let Some(release) = release {
            expected_calls.push(vec![release]);
        }
        assert_eq!(calls, expected_calls, "inserted prefix {inserted}");
    }
}

#[test]
fn failed_button_release_is_reported_without_replaying_input() {
    let batch = [input(2, 0, 0, 1), input(0, 1, 1, 0)];
    let mut calls = Vec::new();
    let outcome = deliver_pointer(&batch, |attempt| {
        calls.push(attempt.to_vec());
        usize::from(calls.len() == 1)
    });
    assert_eq!(outcome, PointerOutcome::PartialReleaseFailed);
    assert_eq!(
        calls,
        [
            vec![
                button(true, true),
                button(true, false),
                PointerEvent::Move { x: 1, y: 1 }
            ],
            vec![button(true, false)],
        ],
    );
}

#[test]
fn an_impossible_reported_count_is_rejected_without_repair() {
    let mut calls = 0;
    let outcome = deliver_pointer(&[input(2, 0, 0, 0)], |events| {
        calls += 1;
        events.len() + 1
    });
    assert_eq!(outcome, PointerOutcome::Rejected);
    assert_eq!(calls, 1);
}
