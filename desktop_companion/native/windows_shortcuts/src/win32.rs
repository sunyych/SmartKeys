use std::{ffi::OsString, os::windows::ffi::OsStringExt, path::Path, ptr::null_mut};

use windows_sys::Win32::Foundation::{CloseHandle, GetLastError, HANDLE, HWND, SetLastError};
use windows_sys::Win32::System::Threading::{
    OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, QueryFullProcessImageNameW,
};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, GetKeyboardLayout, INPUT, INPUT_0, INPUT_KEYBOARD, INPUT_MOUSE, KEYBDINPUT,
    KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP,
    MOUSEEVENTF_MOVE, MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP, MOUSEEVENTF_WHEEL, MOUSEINPUT,
    SendInput, VK_CONTROL, VK_LWIN, VK_MENU, VK_RWIN, VK_SHIFT, VkKeyScanExW,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    GW_OWNER, GWL_EXSTYLE, GetForegroundWindow, GetWindow, GetWindowLongPtrW,
    GetWindowThreadProcessId, IsWindowVisible, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

use crate::desktop::{PointerEvent, foreground_process_name};
use crate::shortcut::{Key, KeyEvent, ShortcutPlatform, layout_key};

pub(crate) struct Win32;

impl ShortcutPlatform for Win32 {
    type Window = HWND;

    fn foreground(&mut self) -> Option<HWND> {
        let hwnd = unsafe { GetForegroundWindow() };
        (!hwnd.is_null()).then_some(hwnd)
    }

    fn process_id(&mut self, window: HWND) -> Option<u32> {
        let mut pid = 0;
        let thread = unsafe { GetWindowThreadProcessId(window, &mut pid) };
        (thread != 0 && pid != 0).then_some(pid)
    }

    fn process_name(&mut self, process_id: u32) -> Option<String> {
        let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, process_id) };
        if handle.is_null() {
            return None;
        }
        let handle = ProcessHandle(handle);
        let mut image = vec![0u16; 32_768];
        let mut size = image.len() as u32;
        let read =
            unsafe { QueryFullProcessImageNameW(handle.0, 0, image.as_mut_ptr(), &mut size) };
        if read == 0 {
            return None;
        }
        let image = OsString::from_wide(&image[..size as usize]);
        Path::new(&image).file_stem()?.to_str().map(str::to_owned)
    }

    fn is_main_window(&mut self, window: HWND) -> bool {
        // A zero extended style is valid. Distinguish a failed query from it.
        let forbidden_style = (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE) as isize;
        unsafe {
            SetLastError(0);
            let style = GetWindowLongPtrW(window, GWL_EXSTYLE);
            (style != 0 || GetLastError() == 0)
                && style & forbidden_style == 0
                && IsWindowVisible(window) != 0
                && GetWindow(window, GW_OWNER).is_null()
        }
    }

    fn modifier_held(&mut self) -> bool {
        [VK_CONTROL, VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN]
            .into_iter()
            .any(|key| unsafe { GetAsyncKeyState(i32::from(key)) } < 0)
    }

    fn character_key(&mut self, window: HWND, character: u16) -> Option<(Key, u8)> {
        let thread = unsafe { GetWindowThreadProcessId(window, null_mut()) };
        if thread == 0 {
            return None;
        }
        let layout = unsafe { GetKeyboardLayout(thread) };
        if layout.is_null() {
            return None;
        }
        layout_key(unsafe { VkKeyScanExW(character, layout) })
    }

    fn send(&mut self, events: &[KeyEvent]) -> usize {
        let events: Vec<_> = events
            .iter()
            .map(|event| {
                let mut flags = 0;
                if event.up {
                    flags |= KEYEVENTF_KEYUP;
                }
                if event.key.extended {
                    flags |= KEYEVENTF_EXTENDEDKEY;
                }
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: event.key.virtual_key,
                            dwFlags: flags,
                            ..KEYBDINPUT::default()
                        },
                    },
                }
            })
            .collect();
        send_input(&events)
    }
}

pub(crate) fn foreground_name() -> Option<String> {
    let mut os = Win32;
    let window = os.foreground()?;
    let pid = os.process_id(window)?;
    let name = os.process_name(pid)?;
    let main_window = !name.eq_ignore_ascii_case("chatgpt") || os.is_main_window(window);
    let name = foreground_process_name(Some(&name), main_window)?;
    (os.process_id(window) == Some(pid) && os.foreground() == Some(window)).then_some(name)
}

pub(crate) fn send_pointer_events(events: &[PointerEvent]) -> usize {
    let mut inputs = [INPUT::default(); 2 * crate::desktop::MAX_POINTER_INPUTS];
    for (input, event) in inputs.iter_mut().zip(events) {
        let mut mouse = MOUSEINPUT::default();
        match *event {
            PointerEvent::Move { x, y } => {
                mouse.dx = x;
                mouse.dy = y;
                mouse.dwFlags = MOUSEEVENTF_MOVE;
            }
            PointerEvent::Wheel { delta } => {
                mouse.mouseData = delta as u32;
                mouse.dwFlags = MOUSEEVENTF_WHEEL;
            }
            PointerEvent::Button { secondary, down } => {
                mouse.dwFlags = match (secondary, down) {
                    (false, true) => MOUSEEVENTF_LEFTDOWN,
                    (false, false) => MOUSEEVENTF_LEFTUP,
                    (true, true) => MOUSEEVENTF_RIGHTDOWN,
                    (true, false) => MOUSEEVENTF_RIGHTUP,
                };
            }
        }
        *input = INPUT {
            r#type: INPUT_MOUSE,
            Anonymous: INPUT_0 { mi: mouse },
        };
    }
    send_input(&inputs[..events.len()])
}

fn send_input(events: &[INPUT]) -> usize {
    unsafe {
        SendInput(
            events.len() as u32,
            events.as_ptr(),
            size_of::<INPUT>() as i32,
        ) as usize
    }
}

pub(crate) struct ProcessHandle(pub(crate) HANDLE);

impl Drop for ProcessHandle {
    fn drop(&mut self) {
        unsafe { CloseHandle(self.0) };
    }
}
