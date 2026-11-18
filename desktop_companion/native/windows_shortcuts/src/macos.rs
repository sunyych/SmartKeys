use std::ffi::{CStr, c_char, c_int, c_void};
use std::ptr::null_mut;

use serde_json::json;

use crate::desktop::{PointerEvent, PointerOutcome, normalize_process_list};

type Object = *mut c_void;
type Selector = *const c_void;
type EventRef = *mut c_void;

#[repr(C)]
#[derive(Clone, Copy)]
struct Point {
    x: f64,
    y: f64,
}

#[link(name = "AppKit", kind = "framework")]
unsafe extern "C" {}

#[link(name = "objc")]
unsafe extern "C" {
    fn objc_getClass(name: *const c_char) -> Object;
    fn sel_registerName(name: *const c_char) -> Selector;
    fn objc_msgSend();
}

#[link(name = "System")]
unsafe extern "C" {
    fn proc_listallpids(buffer: *mut c_void, buffer_size: c_int) -> c_int;
    fn proc_name(pid: c_int, buffer: *mut c_void, buffer_size: u32) -> c_int;
}

#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    fn AXIsProcessTrusted() -> u8;
}

#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGPreflightPostEventAccess() -> bool;
    fn CGEventCreate(source: Object) -> EventRef;
    fn CGEventGetLocation(event: EventRef) -> Point;
    fn CGEventCreateMouseEvent(
        source: Object,
        event_type: u32,
        position: Point,
        button: u32,
    ) -> EventRef;
    fn CGEventSetIntegerValueField(event: EventRef, field: u32, value: i64);
    fn CGEventCreateScrollWheelEvent2(
        source: Object,
        units: u32,
        wheel_count: u32,
        wheel1: i32,
        wheel2: i32,
        wheel3: i32,
    ) -> EventRef;
    fn CGEventPost(tap: u32, event: EventRef);
}

#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFRelease(value: *const c_void);
}

const MAX_PROCESSES: usize = 16_384;
const HID_EVENT_TAP: u32 = 0;
const PIXELS: u32 = 0;
const LEFT_DOWN: u32 = 1;
const LEFT_UP: u32 = 2;
const RIGHT_DOWN: u32 = 3;
const RIGHT_UP: u32 = 4;
const MOUSE_MOVED: u32 = 5;
const MOUSE_DELTA_X: u32 = 4;
const MOUSE_DELTA_Y: u32 = 5;

pub(crate) fn read(kind: u32) -> Option<Vec<u8>> {
    let foreground = foreground_name();
    let value = match kind {
        1 => {
            let mut names = running_processes()?;
            // Include the same localized application name used by the
            // existing app-ID resolver for every foreground snapshot.
            names.extend(foreground.iter().cloned());
            json!({
                "runningProcesses": normalize_process_list(&names),
                "foregroundProcess": foreground,
            })
        }
        2 => json!(foreground),
        _ => return None,
    };
    serde_json::to_vec(&value).ok()
}

fn running_processes() -> Option<Vec<String>> {
    let mut pids = vec![0_i32; MAX_PROCESSES];
    let count = unsafe {
        proc_listallpids(
            pids.as_mut_ptr().cast(),
            size_of_val(pids.as_slice()) as c_int,
        )
    };
    if count <= 0 || count as usize >= pids.len() {
        return None;
    }
    let mut names = Vec::new();
    for &pid in &pids[..count as usize] {
        if pid <= 0 {
            continue;
        }
        let mut name = [0_u8; 256];
        let read = unsafe { proc_name(pid, name.as_mut_ptr().cast(), name.len() as u32) };
        if read <= 0 {
            continue;
        }
        if let Ok(value) = CStr::from_bytes_until_nul(&name)
            && let Ok(value) = value.to_str()
        {
            names.push(value.to_owned());
        }
    }
    Some(names)
}

fn foreground_name() -> Option<String> {
    // Apple documents the shared NSWorkspace as accessible from all threads.
    // The worker isolate owns its own autorelease pool for Objective-C values.
    let _pool = AutoreleasePool::new()?;
    let workspace = message_object(class(c"NSWorkspace"), c"sharedWorkspace");
    let app = message_object(workspace, c"frontmostApplication");
    let name = message_object(app, c"localizedName");
    let utf8 = message_object(name, c"UTF8String").cast::<c_char>();
    if utf8.is_null() {
        return None;
    }
    let name = unsafe { CStr::from_ptr(utf8) }.to_str().ok()?.trim();
    if name.is_empty() || name.chars().any(|value| value.is_ascii_control()) {
        return None;
    }
    Some(name.to_lowercase())
}

fn class(name: &CStr) -> Object {
    unsafe { objc_getClass(name.as_ptr()) }
}

fn message_object(receiver: Object, name: &CStr) -> Object {
    if receiver.is_null() {
        return null_mut();
    }
    let send: unsafe extern "C" fn(Object, Selector) -> Object =
        unsafe { std::mem::transmute(objc_msgSend as unsafe extern "C" fn()) };
    unsafe { send(receiver, sel_registerName(name.as_ptr())) }
}

struct AutoreleasePool(Object);

impl AutoreleasePool {
    fn new() -> Option<Self> {
        let pool = message_object(class(c"NSAutoreleasePool"), c"new");
        (!pool.is_null()).then(|| Self(pool))
    }
}

impl Drop for AutoreleasePool {
    fn drop(&mut self) {
        let send: unsafe extern "C" fn(Object, Selector) =
            unsafe { std::mem::transmute(objc_msgSend as unsafe extern "C" fn()) };
        unsafe { send(self.0, sel_registerName(c"drain".as_ptr())) };
    }
}

pub(crate) fn pointer_status() -> PointerOutcome {
    if unsafe { AXIsProcessTrusted() != 0 && CGPreflightPostEventAccess() } {
        PointerOutcome::Delivered
    } else {
        PointerOutcome::PermissionDenied
    }
}

pub(crate) fn send_pointer_events(events: &[PointerEvent]) -> PointerOutcome {
    if pointer_status() != PointerOutcome::Delivered {
        return PointerOutcome::PermissionDenied;
    }
    let Some(source) = Event::new(unsafe { CGEventCreate(null_mut()) }) else {
        return PointerOutcome::Rejected;
    };
    let mut location = unsafe { CGEventGetLocation(source.0) };
    let mut planned = Vec::with_capacity(events.len());
    for event in events {
        let generated = match *event {
            PointerEvent::Move { x, y } => {
                location.x += f64::from(x);
                location.y += f64::from(y);
                let event =
                    unsafe { CGEventCreateMouseEvent(null_mut(), MOUSE_MOVED, location, 0) };
                if !event.is_null() {
                    unsafe {
                        CGEventSetIntegerValueField(event, MOUSE_DELTA_X, i64::from(x));
                        CGEventSetIntegerValueField(event, MOUSE_DELTA_Y, i64::from(y));
                    }
                }
                event
            }
            PointerEvent::Wheel { delta } => unsafe {
                // Match the existing macOS conversion of one protocol tick
                // to ten Core Graphics pixels.
                CGEventCreateScrollWheelEvent2(null_mut(), PIXELS, 1, delta / 120 * 10, 0, 0)
            },
            PointerEvent::Button { secondary, down } => {
                let kind = match (secondary, down) {
                    (false, true) => LEFT_DOWN,
                    (false, false) => LEFT_UP,
                    (true, true) => RIGHT_DOWN,
                    (true, false) => RIGHT_UP,
                };
                unsafe { CGEventCreateMouseEvent(null_mut(), kind, location, u32::from(secondary)) }
            }
        };
        let Some(generated) = Event::new(generated) else {
            return PointerOutcome::Rejected;
        };
        planned.push(generated);
    }
    // Allocation failures reject the whole batch before any event is posted.
    if pointer_status() != PointerOutcome::Delivered {
        return PointerOutcome::PermissionDenied;
    }
    for event in planned {
        unsafe { CGEventPost(HID_EVENT_TAP, event.0) };
    }
    PointerOutcome::Delivered
}

struct Event(EventRef);

impl Event {
    fn new(event: EventRef) -> Option<Self> {
        (!event.is_null()).then(|| Self(event))
    }
}

impl Drop for Event {
    fn drop(&mut self) {
        unsafe { CFRelease(self.0) };
    }
}
