// Kept platform-independent so tests can exercise the same delivery policy
// against a recording backend without sending keyboard input.
#[cfg(any(windows, test))]
mod shortcut;

pub mod desktop;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(windows)]
mod win32;
#[cfg(windows)]
mod windows_inventory;

#[cfg(windows)]
use std::ffi::{CStr, c_char};
#[cfg(any(windows, target_os = "macos", target_os = "linux"))]
use std::sync::Mutex;

#[cfg(any(windows, target_os = "macos", target_os = "linux"))]
use desktop::{
    MAX_OUTPUT_BYTES, MAX_POINTER_INPUTS, PointerOutcome, RawPointerInput, output_length,
    prepare_pointer_batch,
};
#[cfg(windows)]
use shortcut::{Outcome, Shortcut, deliver};

// Flutter can call the DLL from several isolates. Serialize the complete
// check/send/release operation so two shortcuts cannot affect each other.
#[cfg(any(windows, target_os = "macos", target_os = "linux"))]
static INPUT_TRANSACTION: Mutex<()> = Mutex::new(());

#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn lumiakeys_shortcut_abi_version() -> u32 {
    1
}

#[cfg(any(windows, target_os = "macos", target_os = "linux"))]
#[unsafe(no_mangle)]
pub extern "C" fn lumiakeys_desktop_abi_version() -> u32 {
    1
}

/// Writes one JSON read result into a caller-owned buffer, without a NUL.
/// Kinds are 1 (process snapshot), 2 (foreground), and Windows-only 3 (registry inventory).
/// Returns byte count, or -1 invalid arguments, -2 unavailable, -3 too small.
///
/// # Safety
///
/// The non-null output must be writable for the given capacity and exclusively
/// borrowed for the duration of the call. Error results leave it untouched.
#[cfg(any(windows, target_os = "macos", target_os = "linux"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumiakeys_desktop_read_v1(
    kind: u32,
    output: *mut u8,
    capacity: u32,
) -> i32 {
    if (!matches!(kind, 1 | 2) && !(cfg!(windows) && kind == 3))
        || output.is_null()
        || !(1..=MAX_OUTPUT_BYTES).contains(&capacity)
    {
        return -1;
    }
    #[cfg(windows)]
    let result = windows_inventory::read(kind);
    #[cfg(target_os = "macos")]
    let result = macos::read(kind);
    #[cfg(target_os = "linux")]
    let result = linux::read(kind);
    let Some(json) = result else {
        return -2;
    };
    // Copy directly to raw memory so callers can provide uninitialized output.
    let Some(written) = output_length(json.len(), capacity as usize) else {
        return -3;
    };
    unsafe { std::ptr::copy_nonoverlapping(json.as_ptr(), output, json.len()) };
    written
}

/// Sends one validated mouse batch. Returns a `PointerOutcome` code.
///
/// # Safety
///
/// The non-null inputs pointer must be aligned and address the given number of
/// live, immutable `RawPointerInput` records.
#[cfg(any(windows, target_os = "macos", target_os = "linux"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumiakeys_desktop_pointer_v1(
    inputs: *const RawPointerInput,
    length: u32,
) -> i32 {
    if inputs.is_null()
        || !inputs.is_aligned()
        || !(1..=MAX_POINTER_INPUTS as u32).contains(&length)
    {
        return PointerOutcome::Invalid as i32;
    }
    let inputs = unsafe { std::slice::from_raw_parts(inputs, length as usize) };
    let Some(events) = prepare_pointer_batch(inputs) else {
        return PointerOutcome::Invalid as i32;
    };
    let Ok(_transaction) = INPUT_TRANSACTION.lock() else {
        return PointerOutcome::Rejected as i32;
    };
    #[cfg(windows)]
    let outcome = desktop::deliver_pointer_events(&events, win32::send_pointer_events);
    #[cfg(target_os = "macos")]
    let outcome = macos::send_pointer_events(&events);
    #[cfg(target_os = "linux")]
    let outcome = linux::send_pointer_events(&events);
    outcome as i32
}

/// Reports pointer availability without posting input or prompting the user.
#[cfg(any(windows, target_os = "macos", target_os = "linux"))]
#[unsafe(no_mangle)]
pub extern "C" fn lumiakeys_desktop_pointer_status_v1() -> i32 {
    #[cfg(windows)]
    let outcome = PointerOutcome::Delivered;
    #[cfg(target_os = "macos")]
    let outcome = macos::pointer_status();
    #[cfg(target_os = "linux")]
    let outcome = linux::pointer_status();
    outcome as i32
}

/// Sends one shortcut using the active Windows desktop.
///
/// # Safety
///
/// Both pointers must reference live, readable, NUL-terminated strings that
/// remain unchanged for the call. An empty process list is permitted.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumiakeys_send_shortcut_v1(
    key: *const c_char,
    modifiers: u32,
    allowed_processes: *const c_char,
) -> i32 {
    if key.is_null() || allowed_processes.is_null() {
        return Outcome::Invalid as i32;
    }
    // All input strings are borrowed only for the duration of this call.
    let Ok(key) = (unsafe { CStr::from_ptr(key) }).to_str() else {
        return Outcome::Invalid as i32;
    };
    let Ok(allowed_processes) = (unsafe { CStr::from_ptr(allowed_processes) }).to_str() else {
        return Outcome::Invalid as i32;
    };
    let Some(shortcut) = Shortcut::parse(key, modifiers, allowed_processes) else {
        return Outcome::Invalid as i32;
    };
    let Ok(_transaction) = INPUT_TRANSACTION.lock() else {
        return Outcome::NotDelivered as i32;
    };
    deliver(&mut win32::Win32, &shortcut) as i32
}
