use std::env;
use std::ffi::{c_char, c_int, c_void};
use std::fs::{self, File};
use std::io::Read;
use std::ptr::{null, null_mut};

use serde_json::json;

use crate::desktop::{PointerEvent, PointerOutcome, normalize_process_list, supports_linux_x11};

#[repr(C)]
struct Connection {
    _private: [u8; 0],
}

#[repr(C)]
struct Screen {
    root: u32,
}

#[repr(C)]
struct ScreenIterator {
    data: *mut Screen,
    remaining: c_int,
    index: c_int,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Cookie {
    sequence: u32,
}

#[repr(C)]
struct AtomReply {
    response_type: u8,
    padding: u8,
    sequence: u16,
    length: u32,
    atom: u32,
}

#[repr(C)]
struct PropertyReply {
    response_type: u8,
    format: u8,
    sequence: u16,
    length: u32,
    property_type: u32,
    bytes_after: u32,
    value_len: u32,
}

#[repr(C)]
struct XTestVersionReply {
    response_type: u8,
    major: u8,
    sequence: u16,
    length: u32,
    minor: u16,
}

#[link(name = "xcb")]
unsafe extern "C" {
    fn xcb_connect(display: *const c_char, screen: *mut c_int) -> *mut Connection;
    fn xcb_connection_has_error(connection: *mut Connection) -> c_int;
    fn xcb_disconnect(connection: *mut Connection);
    fn xcb_get_setup(connection: *mut Connection) -> *const c_void;
    fn xcb_setup_roots_iterator(setup: *const c_void) -> ScreenIterator;
    fn xcb_screen_next(iterator: *mut ScreenIterator);
    fn xcb_intern_atom(
        connection: *mut Connection,
        only_if_exists: u8,
        name_len: u16,
        name: *const c_char,
    ) -> Cookie;
    fn xcb_intern_atom_reply(
        connection: *mut Connection,
        cookie: Cookie,
        error: *mut *mut c_void,
    ) -> *mut AtomReply;
    fn xcb_get_property(
        connection: *mut Connection,
        delete: u8,
        window: u32,
        property: u32,
        property_type: u32,
        offset: u32,
        length: u32,
    ) -> Cookie;
    fn xcb_get_property_reply(
        connection: *mut Connection,
        cookie: Cookie,
        error: *mut *mut c_void,
    ) -> *mut PropertyReply;
    fn xcb_get_property_value(reply: *const PropertyReply) -> *mut c_void;
    fn xcb_get_property_value_length(reply: *const PropertyReply) -> c_int;
    fn xcb_request_check(connection: *mut Connection, cookie: Cookie) -> *mut c_void;
    fn free(pointer: *mut c_void);
}

#[link(name = "xcb-xtest")]
unsafe extern "C" {
    fn xcb_test_get_version(connection: *mut Connection, major: u8, minor: u16) -> Cookie;
    fn xcb_test_get_version_reply(
        connection: *mut Connection,
        cookie: Cookie,
        error: *mut *mut c_void,
    ) -> *mut XTestVersionReply;
    fn xcb_test_fake_input_checked(
        connection: *mut Connection,
        event_type: u8,
        detail: u8,
        time: u32,
        root: u32,
        root_x: i16,
        root_y: i16,
        device_id: u8,
    ) -> Cookie;
}

const ATOM_CARDINAL: u32 = 6;
const ATOM_WINDOW: u32 = 33;
const BUTTON_PRESS: u8 = 4;
const BUTTON_RELEASE: u8 = 5;
const MOTION_NOTIFY: u8 = 6;
const MAX_PROCESSES: usize = 16_384;

pub(crate) fn read(kind: u32) -> Option<Vec<u8>> {
    let value = match kind {
        1 => json!({
            "runningProcesses": running_processes()?,
            "foregroundProcess": foreground_name(),
        }),
        2 => json!(foreground_name()),
        _ => return None,
    };
    serde_json::to_vec(&value).ok()
}

fn running_processes() -> Option<Vec<String>> {
    let mut seen = 0;
    let mut names = Vec::new();
    for entry in fs::read_dir("/proc").ok()?.flatten() {
        let name = entry.file_name();
        let Some(pid) = name.to_str().and_then(|name| name.parse::<u32>().ok()) else {
            continue;
        };
        if pid == 0 {
            continue;
        }
        seen += 1;
        if seen > MAX_PROCESSES {
            return None;
        }
        if let Some(name) = process_name(pid) {
            names.push(name);
        }
    }
    Some(normalize_process_list(&names))
}

fn process_name(pid: u32) -> Option<String> {
    let file = File::open(format!("/proc/{pid}/comm")).ok()?;
    let mut bytes = Vec::with_capacity(32);
    file.take(256).read_to_end(&mut bytes).ok()?;
    let text = std::str::from_utf8(&bytes).ok()?.trim();
    if text.is_empty() || text.contains(['/', '\\']) || text.chars().any(|c| c.is_ascii_control()) {
        return None;
    }
    Some(text.to_lowercase())
}

fn foreground_name() -> Option<String> {
    let display = Display::open()?;
    let active_atom = display.atom(b"_NET_ACTIVE_WINDOW")?;
    let pid_atom = display.atom(b"_NET_WM_PID")?;
    let window = display.property(display.root, active_atom, ATOM_WINDOW)?;
    let pid = display.property(window, pid_atom, ATOM_CARDINAL)?;
    if window == 0 || pid == 0 {
        return None;
    }
    let name = process_name(pid)?;
    // A stale EWMH hint must not grant foreground identity during a switch.
    if display.property(display.root, active_atom, ATOM_WINDOW) != Some(window)
        || display.property(window, pid_atom, ATOM_CARDINAL) != Some(pid)
    {
        return None;
    }
    Some(name)
}

pub(crate) fn pointer_status() -> PointerOutcome {
    if Display::open().is_some_and(|display| display.supports_xtest()) {
        PointerOutcome::Delivered
    } else {
        PointerOutcome::Unsupported
    }
}

#[derive(Clone, Copy)]
enum XEvent {
    Move { x: i16, y: i16 },
    Button { button: u8, down: bool },
}

pub(crate) fn send_pointer_events(events: &[PointerEvent]) -> PointerOutcome {
    let Some(display) = Display::open().filter(Display::supports_xtest) else {
        return PointerOutcome::Unsupported;
    };
    let mut plan = Vec::new();
    for event in events {
        match *event {
            PointerEvent::Move { x, y } => plan.push(XEvent::Move {
                x: x as i16,
                y: y as i16,
            }),
            PointerEvent::Wheel { delta } => {
                let ticks = delta / 120;
                let button = if ticks > 0 { 4 } else { 5 };
                for _ in 0..ticks.unsigned_abs() {
                    plan.push(XEvent::Button { button, down: true });
                    plan.push(XEvent::Button {
                        button,
                        down: false,
                    });
                }
            }
            PointerEvent::Button { secondary, down } => {
                let button = if secondary { 3 } else { 1 };
                plan.push(XEvent::Button { button, down });
            }
        }
    }
    for (index, event) in plan.iter().copied().enumerate() {
        if !display.send(event) {
            if index == 0 {
                return PointerOutcome::Rejected;
            }
            if let XEvent::Button { button, down: true } = plan[index - 1]
                && !display.send(XEvent::Button {
                    button,
                    down: false,
                })
            {
                return PointerOutcome::PartialReleaseFailed;
            }
            return PointerOutcome::Partial;
        }
    }
    PointerOutcome::Delivered
}

struct Display {
    connection: *mut Connection,
    root: u32,
}

impl Display {
    fn open() -> Option<Self> {
        if !supports_linux_x11(
            env::var("DISPLAY").ok().as_deref(),
            env::var("WAYLAND_DISPLAY").ok().as_deref(),
            env::var("XDG_SESSION_TYPE").ok().as_deref(),
        ) {
            return None;
        }
        let mut screen = 0;
        let connection = unsafe { xcb_connect(null(), &mut screen) };
        if connection.is_null() {
            return None;
        }
        let mut display = Self {
            connection,
            root: 0,
        };
        if unsafe { xcb_connection_has_error(connection) } != 0 {
            return None;
        }
        let setup = unsafe { xcb_get_setup(connection) };
        if setup.is_null() {
            return None;
        }
        let mut iterator = unsafe { xcb_setup_roots_iterator(setup) };
        if screen < 0 || screen >= iterator.remaining {
            return None;
        }
        for _ in 0..screen {
            unsafe { xcb_screen_next(&mut iterator) };
        }
        display.root = unsafe { iterator.data.as_ref() }?.root;
        Some(display)
    }

    fn atom(&self, name: &[u8]) -> Option<u32> {
        let cookie =
            unsafe { xcb_intern_atom(self.connection, 1, name.len() as u16, name.as_ptr().cast()) };
        let reply = unsafe { xcb_intern_atom_reply(self.connection, cookie, null_mut()) };
        let reply = Allocation::new(reply)?;
        let atom = unsafe { (*reply.0).atom };
        (atom != 0).then_some(atom)
    }

    fn property(&self, window: u32, property: u32, property_type: u32) -> Option<u32> {
        let cookie =
            unsafe { xcb_get_property(self.connection, 0, window, property, property_type, 0, 1) };
        let reply = unsafe { xcb_get_property_reply(self.connection, cookie, null_mut()) };
        let reply = Allocation::new(reply)?;
        let header = unsafe { &*reply.0 };
        if header.property_type != property_type
            || header.format != 32
            || header.value_len != 1
            || header.bytes_after != 0
            || unsafe { xcb_get_property_value_length(reply.0) } != 4
        {
            return None;
        }
        let value = unsafe {
            xcb_get_property_value(reply.0)
                .cast::<u32>()
                .read_unaligned()
        };
        Some(value)
    }

    fn supports_xtest(&self) -> bool {
        let cookie = unsafe { xcb_test_get_version(self.connection, 2, 2) };
        let reply = unsafe { xcb_test_get_version_reply(self.connection, cookie, null_mut()) };
        let Some(reply) = Allocation::new(reply) else {
            return false;
        };
        let reply = unsafe { &*reply.0 };
        reply.major > 2 || (reply.major == 2 && reply.minor >= 2)
    }

    fn send(&self, event: XEvent) -> bool {
        let (kind, detail, x, y) = match event {
            XEvent::Move { x, y } => (MOTION_NOTIFY, 1, x, y),
            XEvent::Button { button, down } => (
                if down { BUTTON_PRESS } else { BUTTON_RELEASE },
                button,
                0,
                0,
            ),
        };
        // Check each request before posting the next one so an error leaves
        // a known prefix, and never retry a move, scroll step, or press.
        let cookie =
            unsafe { xcb_test_fake_input_checked(self.connection, kind, detail, 0, 0, x, y, 0) };
        let error = unsafe { xcb_request_check(self.connection, cookie) };
        Allocation::new(error).is_none()
            && unsafe { xcb_connection_has_error(self.connection) } == 0
    }
}

impl Drop for Display {
    fn drop(&mut self) {
        unsafe { xcb_disconnect(self.connection) };
    }
}

struct Allocation<T>(*mut T);

impl<T> Allocation<T> {
    fn new(pointer: *mut T) -> Option<Self> {
        (!pointer.is_null()).then(|| Self(pointer))
    }
}

impl<T> Drop for Allocation<T> {
    fn drop(&mut self) {
        unsafe { free(self.0.cast()) };
    }
}
