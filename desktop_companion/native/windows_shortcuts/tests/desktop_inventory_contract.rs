use lumiakeys_windows_shortcuts::desktop::{
    AppPath, foreground_process_name, normalize_app_paths, normalize_process_list, output_length,
};

fn app_path(name: &str, path: &str) -> AppPath {
    AppPath {
        name: name.into(),
        path: path.into(),
    }
}

#[test]
fn running_process_names_are_clean_case_insensitive_and_stable() {
    let input = [
        "  Code.EXE ",
        "ChatGPT.EXE",
        "code.exe",
        "ÉDITEUR.EXE",
        "éditeur.exe",
        "  ",
        r"C:\Windows\explorer.exe",
        "program/tools.exe",
        "before\nafter.exe",
        "invalid\u{0}name.exe",
        "explorer.exe",
        "CHATGPT.exe",
    ];
    let input = input.map(str::to_owned);
    assert_eq!(
        normalize_process_list(&input),
        ["code.exe", "chatgpt.exe", "éditeur.exe", "explorer.exe"],
    );
    assert!(normalize_process_list(&[]).is_empty());
}

#[test]
fn foreground_names_drop_one_extension_and_filter_chatgpt_overlays() {
    for (name, main_window, expected) in [
        (Some(" ChatGPT.EXE "), true, Some("chatgpt")),
        (Some(" ChatGPT.EXE "), false, None),
        (Some("ChatGPT"), false, None),
        (Some(" ChatGPTHelper.EXE "), false, Some("chatgpthelper")),
        (Some(" ÉDITEUR.EXE "), false, Some("éditeur")),
        (Some("tool.EXE.EXE"), false, Some("tool.exe")),
        (Some("Code"), false, Some("code")),
        (Some(".EXE"), true, None),
        (Some(" \t"), true, None),
        (Some(r"C:\apps\code.exe"), true, None),
        (Some("tool/name.exe"), true, None),
        (Some("code\n.exe"), true, None),
        (None, true, None),
    ] {
        assert_eq!(
            foreground_process_name(name, main_window).as_deref(),
            expected,
            "name {name:?}, main {main_window}",
        );
    }
}

#[test]
fn registered_paths_preserve_first_identity_and_support_drive_and_unc_roots() {
    let observed = normalize_app_paths(&[
        app_path("Editor", r#"  "C:\Program Files\Editor\Editor.EXE"  "#),
        app_path("Duplicate label", r"c:\program files\editor\editor.exe"),
        app_path("Forward slash", "d:/Tools/Forward.exe"),
        app_path("Network app", r"\\fileserver\tools\app.exe"),
        app_path("UNC duplicate", r"\\FILESERVER\TOOLS\APP.EXE"),
        app_path("Editor elsewhere", r"D:\Editor\Editor.exe"),
    ]);
    let identities: Vec<_> = observed
        .iter()
        .map(|item| (item.name.as_str(), item.path.as_str()))
        .collect();
    assert_eq!(
        identities,
        [
            ("Editor", r"C:\Program Files\Editor\Editor.EXE"),
            ("Forward slash", "d:/Tools/Forward.exe"),
            ("Network app", r"\\fileserver\tools\app.exe"),
            ("Editor elsewhere", r"D:\Editor\Editor.exe"),
        ],
    );
}

#[test]
fn unsafe_registered_icon_locators_are_discarded_before_file_lookup() {
    let untrusted_paths = [
        "",
        "tool.exe",
        r"C:tool.exe",
        r"\tool.exe",
        r"C:\",
        r"C:\tools\app.dll",
        r"C:\tools\script.com",
        r"C:\tools\app.exe --flag",
        r#""C:\tools\app.exe" --flag"#,
        r#"C:\tools\bad"name.exe"#,
        r"C:\tools\app.exe:stream.exe",
        r"\\?\C:\tools\app.exe",
        r"\\.\C:\tools\app.exe",
        r"\\fileserver\tool.exe",
        "C:/tools/bad\nname.exe",
        "C:/tools/bad\u{0}name.exe",
    ];
    for path in untrusted_paths {
        assert!(
            normalize_app_paths(&[app_path("Untrusted target", path)]).is_empty(),
            "unexpected published path {path:?}",
        );
    }
}

#[test]
fn registry_fields_fit_existing_desktop_id_and_label_limits() {
    let maximum_label = "😀".repeat(128);
    let overlong_label = format!("{maximum_label}a");
    let directory = format!("{}/", "d".repeat(99)).repeat(40);
    let valid_target = format!("C:/{directory}{}.exe", "a".repeat(81));
    let overlong_target = format!("C:/{directory}{}.exe", "a".repeat(82));
    assert_eq!(valid_target.encode_utf16().count(), 4088);
    assert_eq!(overlong_target.encode_utf16().count(), 4089);

    let paths = normalize_app_paths(&[
        app_path(&maximum_label, &valid_target),
        app_path(&overlong_label, r"C:\tools\tooLongName.exe"),
        app_path("Too long identity", &overlong_target),
    ]);
    assert_eq!(paths, [app_path(&maximum_label, &valid_target)]);
}

#[test]
fn output_capacity_measures_bytes_without_reserving_a_terminator() {
    let length = "\"é\"".len();
    assert_eq!(length, 4);
    assert_eq!(output_length(length, 4), Some(4));
    assert_eq!(output_length(length, 6), Some(4));
    assert_eq!(output_length(0, 0), Some(0));
}

#[test]
fn insufficient_capacity_and_unrepresentable_abi_lengths_are_rejected() {
    assert_eq!(output_length(4, 3), None);
    assert_eq!(output_length(4, 0), None);
    let largest = i32::MAX as usize;
    assert_eq!(output_length(largest, largest), Some(i32::MAX));
    assert_eq!(output_length(largest + 1, largest + 1), None);
}
