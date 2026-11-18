use lumiakeys_windows_shortcuts::desktop::supports_linux_x11;

#[test]
fn live_x11_session_allows_readiness_probe() {
    assert!(supports_linux_x11(Some(":99"), None, None));
    assert!(supports_linux_x11(Some(":99"), Some(""), Some("x11")));
}

#[test]
fn xwayland_and_missing_display_fail_closed() {
    assert!(!supports_linux_x11(Some(":99"), Some("wayland-0"), None));
    assert!(!supports_linux_x11(Some(":99"), None, Some("WaYlAnD")));
    assert!(!supports_linux_x11(None, None, Some("x11")));
    assert!(!supports_linux_x11(Some(""), None, None));
}
