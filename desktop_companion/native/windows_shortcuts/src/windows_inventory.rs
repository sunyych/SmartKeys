use std::ptr::{null, null_mut};

use serde_json::{Value, json};
use windows_sys::Win32::Foundation::{
    ERROR_FILE_NOT_FOUND, ERROR_NO_MORE_FILES, ERROR_NO_MORE_ITEMS, ERROR_PATH_NOT_FOUND,
    ERROR_SUCCESS, GetLastError, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::System::Environment::ExpandEnvironmentStringsW;
use windows_sys::Win32::System::Registry::{
    HKEY, HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, KEY_READ, KEY_WOW64_32KEY, KEY_WOW64_64KEY,
    RRF_NOEXPAND, RRF_RT_REG_EXPAND_SZ, RRF_RT_REG_SZ, RegCloseKey, RegEnumKeyExW, RegGetValueW,
    RegOpenKeyExW,
};

use crate::desktop::{AppPath, normalize_app_paths, normalize_process_list};
use crate::win32::{ProcessHandle, foreground_name};

const APP_PATHS: &str = r"Software\Microsoft\Windows\CurrentVersion\App Paths";
const UNINSTALL: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall";
const MAX_PROCESS_ROWS: usize = 16_384;
const MAX_REGISTRY_SUBKEYS: u32 = 4096;
const MAX_REGISTRY_ROWS: usize = 2000;
const MAX_REGISTRY_BYTES: usize = 512 * 1024;
const MAX_VALUE_UNITS: usize = 4096;

pub(crate) fn read(kind: u32) -> Option<Vec<u8>> {
    let value = match kind {
        1 => json!({
            "runningProcesses": running_processes()?,
            "foregroundProcess": foreground_name(),
        }),
        2 => json!(foreground_name()),
        3 => registry_inventory()?,
        _ => return None,
    };
    serde_json::to_vec(&value).ok()
}

fn running_processes() -> Option<Vec<String>> {
    let handle = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if handle == INVALID_HANDLE_VALUE {
        return None;
    }
    let snapshot = ProcessHandle(handle);
    let mut entry = PROCESSENTRY32W {
        dwSize: size_of::<PROCESSENTRY32W>() as u32,
        ..Default::default()
    };
    let mut found = unsafe { Process32FirstW(snapshot.0, &mut entry) };
    let mut names = Vec::new();
    while found != 0 {
        if names.len() >= MAX_PROCESS_ROWS {
            return None;
        }
        names.push(String::from_utf16_lossy(until_nul(&entry.szExeFile)));
        found = unsafe { Process32NextW(snapshot.0, &mut entry) };
    }
    if unsafe { GetLastError() } != ERROR_NO_MORE_FILES {
        return None;
    }
    Some(normalize_process_list(&names))
}

fn registry_inventory() -> Option<Value> {
    let mut app_paths = Vec::new();
    let mut installed_names = Vec::new();
    let mut budget = RegistryBudget {
        rows: MAX_REGISTRY_ROWS,
        bytes: MAX_REGISTRY_BYTES,
    };
    for (root, view) in [
        (HKEY_CURRENT_USER, 0),
        (HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY),
        (HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY),
    ] {
        if let Some(key) = open_registry_key(root, view, APP_PATHS)? {
            for (name, target) in registry_values(&key, None, &mut budget)? {
                if let Some(path) = expand_environment(&target) {
                    budget.bytes = budget
                        .bytes
                        .checked_sub(path.len().saturating_sub(target.len()))?;
                    app_paths.push(AppPath { name, path });
                }
            }
        }
        if let Some(key) = open_registry_key(root, view, UNINSTALL)? {
            for (_, name) in registry_values(&key, Some("DisplayName"), &mut budget)? {
                if !name.trim().is_empty() && !name.chars().any(|value| value.is_ascii_control()) {
                    installed_names.push(name);
                }
            }
        }
    }
    let app_paths: Vec<Value> = normalize_app_paths(&app_paths)
        .into_iter()
        .filter(|entry| std::path::Path::new(&entry.path).is_file())
        .map(|entry| json!({"name": entry.name, "path": entry.path}))
        .collect();
    Some(json!({"installedNames": installed_names, "appPaths": app_paths}))
}

fn open_registry_key(root: HKEY, view: u32, path: &str) -> Option<Option<RegistryKey>> {
    let path = wide(path);
    let mut key = null_mut();
    let status = unsafe { RegOpenKeyExW(root, path.as_ptr(), 0, KEY_READ | view, &mut key) };
    match status {
        ERROR_SUCCESS => Some(Some(RegistryKey(key))),
        ERROR_FILE_NOT_FOUND | ERROR_PATH_NOT_FOUND => Some(None),
        _ => None,
    }
}

struct RegistryBudget {
    rows: usize,
    bytes: usize,
}

fn registry_values(
    key: &RegistryKey,
    value: Option<&str>,
    budget: &mut RegistryBudget,
) -> Option<Vec<(String, String)>> {
    let value = value.map(wide);
    let value = value.as_ref().map_or(null(), |value| value.as_ptr());
    let mut entries = Vec::new();
    for index in 0..MAX_REGISTRY_SUBKEYS {
        let mut name = [0u16; 256];
        let mut units = name.len() as u32;
        let status = unsafe {
            RegEnumKeyExW(
                key.0,
                index,
                name.as_mut_ptr(),
                &mut units,
                null(),
                null_mut(),
                null_mut(),
                null_mut(),
            )
        };
        match status {
            ERROR_NO_MORE_ITEMS => return Some(entries),
            ERROR_SUCCESS if units < name.len() as u32 => {}
            _ => return None,
        }
        let mut data = [0u16; MAX_VALUE_UNITS];
        let mut bytes = size_of_val(&data) as u32;
        let status = unsafe {
            RegGetValueW(
                key.0,
                name.as_ptr(),
                value,
                RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND,
                null_mut(),
                data.as_mut_ptr().cast(),
                &mut bytes,
            )
        };
        if status == ERROR_SUCCESS {
            let name = String::from_utf16_lossy(&name[..units as usize]);
            let data = String::from_utf16_lossy(until_nul(&data));
            budget.rows = budget.rows.checked_sub(1)?;
            budget.bytes = budget.bytes.checked_sub(name.len() + data.len())?;
            entries.push((name, data));
        }
    }
    None
}

fn expand_environment(value: &str) -> Option<String> {
    if !value.contains('%') {
        return Some(value.to_owned());
    }
    let value = wide(value);
    let mut expanded = [0u16; MAX_VALUE_UNITS];
    let units = unsafe {
        ExpandEnvironmentStringsW(value.as_ptr(), expanded.as_mut_ptr(), expanded.len() as u32)
    };
    (units != 0 && units <= expanded.len() as u32)
        .then(|| String::from_utf16_lossy(&expanded[..units as usize - 1]))
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

fn until_nul(value: &[u16]) -> &[u16] {
    &value[..value
        .iter()
        .position(|&unit| unit == 0)
        .unwrap_or(value.len())]
}

struct RegistryKey(HKEY);

impl Drop for RegistryKey {
    fn drop(&mut self) {
        unsafe { RegCloseKey(self.0) };
    }
}
