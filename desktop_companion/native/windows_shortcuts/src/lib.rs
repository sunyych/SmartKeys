// Kept platform-independent so tests can exercise the same delivery policy
// against a recording backend without sending keyboard input.
#[cfg(any(windows, test))]
mod shortcut;

#[cfg(windows)]
mod win32;

#[cfg(windows)]
use std::ffi::{CStr, c_char};
#[cfg(windows)]
use std::sync::Mutex;

#[cfg(windows)]
use shortcut::{Outcome, Shortcut, deliver};

// Flutter can call the DLL from several isolates. Serialize the complete
// check/send/release operation so two shortcuts cannot affect each other.
#[cfg(windows)]
static INPUT_TRANSACTION: Mutex<()> = Mutex::new(());

#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn lumiakeys_shortcut_abi_version() -> u32 {
    1
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
