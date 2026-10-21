use super::{auth::VerifyError, error, now_seconds, AppState};
use axum::middleware::Next;
use axum::{
    body::Bytes,
    extract::{Extension, State},
    http::{header, Request, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::types::Json as SqlJson;
use std::collections::HashSet;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

pub const MAX_BACKUP_BODY: usize = 20 * 1024 * 1024;
const MAX_IMAGE_BYTES: usize = 4 * 1024 * 1024;

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct BackupEnvelope {
    schema_version: u8,
    selection: Selection,
    data: BackupData,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Selection {
    settings: bool,
    profile_ids: Vec<String>,
    images: bool,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct BackupData {
    preferences: Option<Preferences>,
    profiles: Vec<Profile>,
    images: Vec<BackupImage>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Preferences {
    #[serde(rename = "hapticEnabled")]
    haptic_enabled: bool,
    #[serde(rename = "soundEnabled")]
    sound_enabled: bool,
    #[serde(rename = "orientationMode")]
    orientation_mode: String,
    #[serde(rename = "shortcutPlatform")]
    shortcut_platform: String,
    #[serde(rename = "controlSurfaceLayout")]
    control_surface_layout: String,
    #[serde(rename = "tabletKeysPerPage")]
    tablet_keys_per_page: i64,
    #[serde(rename = "chargingBrightnessMode")]
    charging_brightness_mode: String,
    #[serde(rename = "chargingBrightness")]
    charging_brightness: f64,
    #[serde(rename = "keepScreenOnWhileCharging")]
    keep_screen_on_while_charging: bool,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
#[serde(rename_all = "camelCase")]
struct Profile {
    id: String,
    name: String,
    target_application: Option<String>,
    profile_icon: Visual,
    accent_color: Option<i64>,
    is_built_in_template: bool,
    buttons: Vec<Button>,
    wheel: Wheel,
    created_at: i64,
    updated_at: i64,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
#[serde(rename_all = "camelCase")]
struct Button {
    id: String,
    position: i64,
    label: String,
    subtitle: String,
    show_label: bool,
    show_shortcut: bool,
    visual: Visual,
    action: Action,
    haptic_enabled: bool,
    sound_enabled: bool,
    text_size: f64,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
#[serde(rename_all = "camelCase")]
struct Visual {
    r#type: String,
    value: Option<String>,
    fit: String,
    tint_color: Option<i64>,
    background_color: Option<i64>,
    icon_size: f64,
    image_scale: f64,
    alignment_x: f64,
    alignment_y: f64,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
#[serde(rename_all = "camelCase")]
struct Action {
    r#type: String,
    key_code: Option<String>,
    modifiers: Vec<String>,
    value: Option<String>,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
#[serde(rename_all = "camelCase")]
struct Wheel {
    control_type: String,
    clockwise: Action,
    counter_clockwise: Action,
    center: Action,
    up: Action,
    down: Action,
    left: Action,
    right: Action,
    mode_label: String,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct BackupImage {
    path: String,
    mime_type: String,
    data_base64: String,
}

#[derive(Serialize)]
struct PutResponse {
    schema_version: u8,
    updated_at: String,
}
#[derive(Serialize)]
struct GetResponse {
    schema_version: u8,
    updated_at: String,
    backup: Value,
}

pub async fn guard(
    State(state): State<AppState>,
    mut request: Request<axum::body::Body>,
    next: Next,
) -> Response {
    if !state.verifier.is_configured() {
        return error(StatusCode::SERVICE_UNAVAILABLE, "backup_unavailable");
    }
    let token = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "));
    let Some(token) = token else {
        return error(StatusCode::UNAUTHORIZED, "unauthorized");
    };
    let subject = match state.verifier.verified_subject(token).await {
        Ok(subject) => subject,
        Err(VerifyError::Unavailable | VerifyError::NotConfigured) => {
            return error(StatusCode::SERVICE_UNAVAILABLE, "backup_unavailable")
        }
        Err(VerifyError::Invalid) => return error(StatusCode::UNAUTHORIZED, "unauthorized"),
    };
    let permit = match state.backup_slots.clone().try_acquire_owned() {
        Ok(permit) => permit,
        Err(_) => return error(StatusCode::SERVICE_UNAVAILABLE, "backup_busy"),
    };
    request.extensions_mut().insert(subject);
    let response = next.run(request).await;
    drop(permit);
    response
}

pub async fn put(
    State(state): State<AppState>,
    Extension(subject): Extension<String>,
    body: Bytes,
) -> Response {
    if body.len() > MAX_BACKUP_BODY {
        return error(StatusCode::PAYLOAD_TOO_LARGE, "payload_too_large");
    }
    let decoded = tokio::task::spawn_blocking(move || -> Result<Value, ()> {
        let backup: BackupEnvelope = serde_json::from_slice(&body).map_err(|_| ())?;
        validate_backup(&backup)?;
        serde_json::to_value(backup).map_err(|_| ())
    })
    .await;
    let value = match decoded {
        Ok(Ok(value)) => value,
        _ => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    let updated = now_seconds();
    if sqlx::query("INSERT INTO account_backups(google_sub, updated_at, backup) VALUES($1,$2,$3) ON CONFLICT(google_sub) DO UPDATE SET updated_at=EXCLUDED.updated_at, backup=EXCLUDED.backup")
        .bind(subject).bind(updated).bind(SqlJson(value)).execute(&state.pool).await.is_err() {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "server_error");
    }
    match timestamp(updated) {
        Some(updated_at) => (
            StatusCode::OK,
            Json(PutResponse {
                schema_version: 1,
                updated_at,
            }),
        )
            .into_response(),
        None => error(StatusCode::INTERNAL_SERVER_ERROR, "server_error"),
    }
}

pub async fn get(State(state): State<AppState>, Extension(subject): Extension<String>) -> Response {
    let row = sqlx::query_as::<_, (i64, SqlJson<Value>)>(
        "SELECT updated_at, backup FROM account_backups WHERE google_sub=$1",
    )
    .bind(subject)
    .fetch_optional(&state.pool)
    .await;
    match row {
        Ok(Some((updated, SqlJson(backup)))) => match timestamp(updated) {
            Some(updated_at) => (
                StatusCode::OK,
                Json(GetResponse {
                    schema_version: 1,
                    updated_at,
                    backup,
                }),
            )
                .into_response(),
            None => error(StatusCode::INTERNAL_SERVER_ERROR, "server_error"),
        },
        Ok(None) => error(StatusCode::NOT_FOUND, "not_found"),
        Err(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "server_error"),
    }
}

pub async fn delete(
    State(state): State<AppState>,
    Extension(subject): Extension<String>,
) -> Response {
    if sqlx::query("DELETE FROM account_backups WHERE google_sub=$1")
        .bind(subject)
        .execute(&state.pool)
        .await
        .is_err()
    {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "server_error");
    }
    StatusCode::NO_CONTENT.into_response()
}

fn timestamp(seconds: i64) -> Option<String> {
    OffsetDateTime::from_unix_timestamp(seconds)
        .ok()?
        .format(&Rfc3339)
        .ok()
}

fn validate_backup(backup: &BackupEnvelope) -> Result<(), ()> {
    if backup.schema_version != 1
        || backup.selection.profile_ids.len() > 4
        || !(backup.selection.settings || !backup.selection.profile_ids.is_empty())
    {
        return Err(());
    }
    let mut profile_ids = HashSet::new();
    if backup
        .selection
        .profile_ids
        .iter()
        .any(|id| id.is_empty() || id.len() > 128 || !profile_ids.insert(id.as_str()))
    {
        return Err(());
    }
    if backup.selection.settings != backup.data.preferences.is_some()
        || backup.data.profiles.len() != backup.selection.profile_ids.len()
        || backup.data.profiles.len() > 4
    {
        return Err(());
    }
    for (profile, selected_id) in backup
        .data
        .profiles
        .iter()
        .zip(&backup.selection.profile_ids)
    {
        if &profile.id != selected_id
            || profile.id.is_empty()
            || profile.name.len() > 512
            || profile
                .target_application
                .as_ref()
                .is_some_and(|s| s.len() > 512)
        {
            return Err(());
        }
        validate_visual(&profile.profile_icon)?;
        if profile.buttons.len() > 60 {
            return Err(());
        }
        let mut positions = HashSet::new();
        for button in &profile.buttons {
            if button.position < 0
                || button.position >= 60
                || !positions.insert(button.position)
                || button.id.len() > 128
                || button.label.len() > 1024
                || button.subtitle.len() > 1024
                || !(10.0..=24.0).contains(&button.text_size)
            {
                return Err(());
            }
            validate_visual(&button.visual)?;
            validate_action(&button.action)?;
        }
        validate_wheel(&profile.wheel)?;
    }
    if let Some(prefs) = &backup.data.preferences {
        if !["auto", "portrait", "landscape"].contains(&prefs.orientation_mode.as_str())
            || !["automatic", "apple", "windowsLinux"].contains(&prefs.shortcut_platform.as_str())
            || !["automatic", "phone", "shortcutBoard"]
                .contains(&prefs.control_surface_layout.as_str())
            || !["fixed", "dynamic"].contains(&prefs.charging_brightness_mode.as_str())
            || !(24..=60).contains(&prefs.tablet_keys_per_page)
            || !(0.1..=1.0).contains(&prefs.charging_brightness)
        {
            return Err(());
        }
    }
    if !backup.selection.images && !backup.data.images.is_empty() || backup.data.images.len() > 244
    {
        return Err(());
    }
    let mut refs = HashSet::new();
    for profile in &backup.data.profiles {
        collect_image_ref(&profile.profile_icon, &mut refs)?;
        for button in &profile.buttons {
            collect_image_ref(&button.visual, &mut refs)?;
        }
    }
    let mut paths = HashSet::new();
    for image in &backup.data.images {
        if !safe_image_path(&image.path)
            || !paths.insert(image.path.as_str())
            || !refs.contains(&image.path)
        {
            return Err(());
        }
        let decoded = STANDARD.decode(&image.data_base64).map_err(|_| ())?;
        if decoded.len() > MAX_IMAGE_BYTES
            || !valid_image_signature(&image.mime_type, &image.path, &decoded)
        {
            return Err(());
        }
    }
    Ok(())
}

fn validate_visual(visual: &Visual) -> Result<(), ()> {
    if !["none", "builtinIcon", "customImage"].contains(&visual.r#type.as_str())
        || !["contain", "cover", "centerCrop"].contains(&visual.fit.as_str())
        || !(18.0..=64.0).contains(&visual.icon_size)
        || !(0.75..=2.0).contains(&visual.image_scale)
        || !(-1.0..=1.0).contains(&visual.alignment_x)
        || !(-1.0..=1.0).contains(&visual.alignment_y)
    {
        return Err(());
    }
    if visual.r#type == "customImage" && visual.value.as_deref().is_none_or(|v| !safe_image_path(v))
    {
        return Err(());
    }
    Ok(())
}
fn collect_image_ref(visual: &Visual, refs: &mut HashSet<String>) -> Result<(), ()> {
    validate_visual(visual)?;
    if visual.r#type == "customImage" {
        refs.insert(visual.value.clone().ok_or(())?);
    }
    Ok(())
}
fn validate_action(action: &Action) -> Result<(), ()> {
    if ![
        "keyboard",
        "companion",
        "consumerControl",
        "mouseWheel",
        "mouseMove",
        "mouseButton",
        "none",
    ]
    .contains(&action.r#type.as_str())
    {
        return Err(());
    }
    if action.r#type != "keyboard" && (action.key_code.is_some() || !action.modifiers.is_empty()) {
        return Err(());
    }
    if action.r#type == "companion" {
        let value = action.value.as_deref().ok_or(())?;
        if value.is_empty() || value.len() > 16 * 1024 {
            return Err(());
        }
        let parsed: Value = serde_json::from_str(value).map_err(|_| ())?;
        if parsed.as_object().is_none_or(|o| o.is_empty()) {
            return Err(());
        }
    } else {
        let value = action.value.as_deref();
        let safe_value = match action.r#type.as_str() {
            "keyboard" => {
                action.key_code.as_deref().is_some_and(|v| {
                    (5..=44).contains(&v.len())
                        && v.starts_with("KEY_")
                        && v.bytes()
                            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_')
                }) && value.is_none()
            }
            "consumerControl" => value.is_some_and(|v| {
                [
                    "MUTE",
                    "VOLUME_UP",
                    "VOLUME_DOWN",
                    "PREVIOUS_TRACK",
                    "PLAY_PAUSE",
                    "NEXT_TRACK",
                    "PLAY",
                    "PAUSE",
                    "RECORD",
                    "STOP",
                    "BRIGHTNESS_UP",
                    "BRIGHTNESS_DOWN",
                    "KEYBOARD_BRIGHTNESS_UP",
                    "KEYBOARD_BRIGHTNESS_DOWN",
                    "KEYBOARD_BACKLIGHT_MINIMUM",
                    "KEYBOARD_BACKLIGHT_MAXIMUM",
                ]
                .contains(&v)
            }),
            "mouseWheel" => value.is_some_and(|v| {
                ["UP", "DOWN", "WHEEL_UP", "WHEEL_DOWN"].contains(&v)
                    || v.parse::<i16>().is_ok_and(|n| (-127..=127).contains(&n))
            }),
            "mouseMove" => value.is_some_and(|v| {
                ["UP", "DOWN", "LEFT", "RIGHT"].contains(&v) || valid_mouse_coordinates(v)
            }),
            "mouseButton" => value
                .is_some_and(|v| ["LEFT", "PRIMARY", "RIGHT", "SECONDARY", "MIDDLE"].contains(&v)),
            "none" => value.is_none() && action.key_code.is_none(),
            _ => false,
        };
        if !safe_value {
            return Err(());
        }
    }
    if action.modifiers.len() > 8
        || action.modifiers.iter().any(|m| {
            ![
                "PRIMARY",
                "LEFT_CTRL",
                "LEFT_SHIFT",
                "LEFT_ALT",
                "LEFT_META",
                "LEFT_GUI",
                "SHIFT",
                "ALT",
                "META",
                "GUI",
                "RIGHT_CTRL",
                "RIGHT_SHIFT",
                "RIGHT_ALT",
                "RIGHT_META",
                "RIGHT_GUI",
            ]
            .contains(&m.as_str())
        })
        || action.key_code.as_ref().is_some_and(|k| k.len() > 64)
    {
        return Err(());
    }
    Ok(())
}
fn valid_mouse_coordinates(value: &str) -> bool {
    let Some((x, y)) = value.split_once(',') else {
        return false;
    };
    valid_coordinate(x) && valid_coordinate(y)
}
fn valid_coordinate(value: &str) -> bool {
    let digits = value.strip_prefix('-').unwrap_or(value);
    (1..=4).contains(&digits.len()) && digits.bytes().all(|b| b.is_ascii_digit())
}
fn validate_wheel(wheel: &Wheel) -> Result<(), ()> {
    if !["jog", "mousePad"].contains(&wheel.control_type.as_str()) || wheel.mode_label.len() > 128 {
        return Err(());
    }
    for action in [
        &wheel.clockwise,
        &wheel.counter_clockwise,
        &wheel.center,
        &wheel.up,
        &wheel.down,
        &wheel.left,
        &wheel.right,
    ] {
        validate_action(action)?;
    }
    Ok(())
}
fn safe_image_path(path: &str) -> bool {
    let parts = path.split('/').collect::<Vec<_>>();
    if parts.len() != 3 || parts[0] != "images" || parts[1].is_empty() || parts[2].is_empty() {
        return false;
    }
    let safe_component = |s: &str| {
        s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-' || b == b'.')
            && !s.contains("..")
            && s != "."
    };
    if !safe_component(parts[1]) || !safe_component(parts[2]) {
        return false;
    }
    let ext = parts[2]
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();
    ["png", "jpg", "jpeg", "webp"].contains(&ext.as_str())
}
fn valid_image_signature(mime: &str, path: &str, data: &[u8]) -> bool {
    let ext = path.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
    match (mime, ext.as_str()) {
        ("image/png", "png") => {
            data.len() >= 33
                && data.starts_with(b"\x89PNG\r\n\x1a\n")
                && &data[12..16] == b"IHDR"
                && data[16..24].iter().any(|b| *b != 0)
        }
        ("image/jpeg", "jpg" | "jpeg") => {
            data.len() >= 4
                && data.starts_with(&[0xff, 0xd8, 0xff])
                && data.ends_with(&[0xff, 0xd9])
        }
        ("image/webp", "webp") => {
            data.len() >= 30
                && data.starts_with(b"RIFF")
                && &data[8..12] == b"WEBP"
                && u32::from_le_bytes(data[4..8].try_into().unwrap()) as usize + 8 == data.len()
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_traversal_unknown_mime_and_unreferenced_images() {
        assert!(!safe_image_path("images/../secret.png"));
        assert!(!safe_image_path("C:/images/a.png"));
        assert!(!valid_image_signature(
            "image/png",
            "images/icons/a.png",
            b"not a png"
        ));
        assert!(!valid_image_signature(
            "image/jpeg",
            "images/icons/a.png",
            &[0xff, 0xd8, 0xff]
        ));
    }

    fn minimal_settings_backup() -> Value {
        serde_json::json!({
            "schema_version": 1,
            "selection": {"settings":true,"profile_ids":[],"images":false},
            "data": {"preferences": {
                "hapticEnabled":true,"soundEnabled":false,"orientationMode":"landscape",
                "shortcutPlatform":"automatic","controlSurfaceLayout":"automatic","tabletKeysPerPage":40,
                "chargingBrightnessMode":"fixed","chargingBrightness":0.8,"keepScreenOnWhileCharging":true
            },"profiles":[],"images":[]}
        })
    }

    fn profile_backup(action: Value) -> Value {
        let visual = serde_json::json!({"type":"none","value":null,"fit":"contain","tintColor":null,"backgroundColor":null,"iconSize":32.0,"imageScale":1.0,"alignmentX":0.0,"alignmentY":0.0});
        let button = serde_json::json!({"id":"button_01","position":0,"label":"Copy","subtitle":"","showLabel":true,"showShortcut":false,"visual":visual,"action":action,"hapticEnabled":true,"soundEnabled":false,"textSize":14.0});
        let action_none =
            serde_json::json!({"type":"none","keyCode":null,"modifiers":[],"value":null});
        serde_json::json!({
            "schema_version":1,"selection":{"settings":false,"profile_ids":["profile_custom"],"images":false},
            "data":{"preferences":null,"profiles":[{"id":"profile_custom","name":"Custom","targetApplication":null,"profileIcon":visual,"accentColor":null,"isBuiltInTemplate":false,"buttons":[button],"wheel":{"controlType":"jog","clockwise":action_none,"counterClockwise":action_none,"center":action_none,"up":action_none,"down":action_none,"left":action_none,"right":action_none,"modeLabel":"Navigate"},"createdAt":1,"updatedAt":2}],"images":[]}
        })
    }

    #[test]
    fn validates_exact_preferences_profile_fields_and_safe_companion_action() {
        let backup: BackupEnvelope = serde_json::from_value(minimal_settings_backup()).unwrap();
        assert!(validate_backup(&backup).is_ok());
        let mut unknown = minimal_settings_backup();
        unknown["data"]["preferences"]["defaultHostAddress"] = serde_json::json!("192.0.2.1");
        assert!(serde_json::from_value::<BackupEnvelope>(unknown).is_err());

        let dark = serde_json::json!({"type":"companion","keyCode":null,"modifiers":[],"value":"{\"kind\":\"dark\"}"});
        let safe: BackupEnvelope = serde_json::from_value(profile_backup(dark)).unwrap();
        assert!(validate_backup(&safe).is_ok());
        let arbitrary = serde_json::json!({"type":"companion","keyCode":null,"modifiers":[],"value":"{\"kind\":\"execute\",\"command\":\"private\"}"});
        let private_backup: BackupEnvelope =
            serde_json::from_value(profile_backup(arbitrary)).unwrap();
        assert!(validate_backup(&private_backup).is_ok());
    }

    #[test]
    fn accepts_builtin_general_hid_actions_and_rejects_out_of_range_values() {
        for action in [
            serde_json::json!({"type":"consumerControl","keyCode":null,"modifiers":[],"value":"MUTE"}),
            serde_json::json!({"type":"consumerControl","keyCode":null,"modifiers":[],"value":"VOLUME_DOWN"}),
            serde_json::json!({"type":"consumerControl","keyCode":null,"modifiers":[],"value":"PREVIOUS_TRACK"}),
            serde_json::json!({"type":"mouseMove","keyCode":null,"modifiers":[],"value":"UP"}),
            serde_json::json!({"type":"mouseWheel","keyCode":null,"modifiers":[],"value":"-127"}),
            serde_json::json!({"type":"mouseButton","keyCode":null,"modifiers":[],"value":"PRIMARY"}),
        ] {
            let parsed: BackupEnvelope = serde_json::from_value(profile_backup(action)).unwrap();
            assert!(validate_backup(&parsed).is_ok());
        }
        let too_fast =
            serde_json::json!({"type":"mouseWheel","keyCode":null,"modifiers":[],"value":"128"});
        let parsed: BackupEnvelope = serde_json::from_value(profile_backup(too_fast)).unwrap();
        assert!(validate_backup(&parsed).is_err());

        let mut prefs = minimal_settings_backup();
        prefs["data"]["preferences"]["tabletKeysPerPage"] = serde_json::json!(15);
        let parsed: BackupEnvelope = serde_json::from_value(prefs).unwrap();
        assert!(validate_backup(&parsed).is_err());
    }

    #[test]
    fn matches_keyboard_alias_and_mouse_coordinate_codec_boundaries() {
        for modifier in ["SHIFT", "ALT", "META", "GUI"] {
            let action = serde_json::json!({"type":"keyboard","keyCode":"KEY_A","modifiers":[modifier],"value":null});
            let backup: BackupEnvelope = serde_json::from_value(profile_backup(action)).unwrap();
            assert!(validate_backup(&backup).is_ok());
        }
        let longest_key = format!("KEY_{}", "A".repeat(40));
        let action = serde_json::json!({"type":"keyboard","keyCode":longest_key,"modifiers":[],"value":null});
        let backup: BackupEnvelope = serde_json::from_value(profile_backup(action)).unwrap();
        assert!(validate_backup(&backup).is_ok());
        let too_long_key = format!("KEY_{}", "A".repeat(41));
        let action = serde_json::json!({"type":"keyboard","keyCode":too_long_key,"modifiers":[],"value":null});
        let backup: BackupEnvelope = serde_json::from_value(profile_backup(action)).unwrap();
        assert!(validate_backup(&backup).is_err());

        for coordinate in ["9999,-0001", "-1,0"] {
            let action = serde_json::json!({"type":"mouseMove","keyCode":null,"modifiers":[],"value":coordinate});
            let backup: BackupEnvelope = serde_json::from_value(profile_backup(action)).unwrap();
            assert!(validate_backup(&backup).is_ok());
        }
        for coordinate in ["10000,0", " 1,0", "+1,0", "1, 0", "1,0,2"] {
            let action = serde_json::json!({"type":"mouseMove","keyCode":null,"modifiers":[],"value":coordinate});
            let backup: BackupEnvelope = serde_json::from_value(profile_backup(action)).unwrap();
            assert!(validate_backup(&backup).is_err(), "accepted {coordinate}");
        }
        for invalid_action in [
            serde_json::json!({"type":"mouseMove","keyCode":"KEY_A","modifiers":[],"value":"UP"}),
            serde_json::json!({"type":"consumerControl","keyCode":null,"modifiers":["SHIFT"],"value":"MUTE"}),
        ] {
            let backup: BackupEnvelope =
                serde_json::from_value(profile_backup(invalid_action)).unwrap();
            assert!(validate_backup(&backup).is_err());
        }
    }

    #[test]
    fn preserves_valid_desktop_companion_commands_in_buttons_and_wheel() {
        for command in [
            r#"{"kind":"launch","target":"ChatGPT"}"#,
            r#"{"kind":"voiceInput"}"#,
            r#"{"kind":"shortcut","keys":["CTRL","ALT","T"]}"#,
        ] {
            let action = serde_json::json!({"type":"companion","keyCode":null,"modifiers":[],"value":command});
            let button: BackupEnvelope =
                serde_json::from_value(profile_backup(action.clone())).unwrap();
            assert!(validate_backup(&button).is_ok());

            let mut wheel_value = profile_backup(
                serde_json::json!({"type":"none","keyCode":null,"modifiers":[],"value":null}),
            );
            wheel_value["data"]["profiles"][0]["wheel"]["clockwise"] = action.clone();
            let wheel: BackupEnvelope = serde_json::from_value(wheel_value).unwrap();
            assert!(validate_backup(&wheel).is_ok());
            assert_eq!(
                wheel.data.profiles[0].wheel.clockwise.value.as_deref(),
                Some(command)
            );
        }
    }

    #[test]
    fn rejects_invalid_or_oversized_desktop_companion_data() {
        for value in ["not json", "null", "[]", "\"string\"", "{}"] {
            let action =
                serde_json::json!({"type":"companion","keyCode":null,"modifiers":[],"value":value});
            let backup: BackupEnvelope = serde_json::from_value(profile_backup(action)).unwrap();
            assert!(validate_backup(&backup).is_err(), "accepted {value}");
        }
        let oversized = format!(
            "{{\"kind\":\"shortcut\",\"payload\":\"{}\"}}",
            "x".repeat(16 * 1024)
        );
        let action =
            serde_json::json!({"type":"companion","keyCode":null,"modifiers":[],"value":oversized});
        let backup: BackupEnvelope = serde_json::from_value(profile_backup(action)).unwrap();
        assert!(validate_backup(&backup).is_err());
    }

    #[test]
    fn enforces_selection_and_safe_image_references_and_bytes() {
        let mut unselected: Value = serde_json::json!({"schema_version":1,"selection":{"settings":false,"profile_ids":[],"images":false},"data":{"preferences":null,"profiles":[],"images":[]}});
        let empty: BackupEnvelope = serde_json::from_value(unselected.clone()).unwrap();
        assert!(validate_backup(&empty).is_err());
        unselected["selection"]["settings"] = serde_json::json!(true);
        unselected["data"]["preferences"] =
            minimal_settings_backup()["data"]["preferences"].clone();

        let png = STANDARD.encode(b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\x00IEND\xaeB`\x82");
        assert!(valid_image_signature(
            "image/png",
            "images/icons/a.png",
            &STANDARD.decode(png).unwrap()
        ));
        assert!(safe_image_path("images/icons/a.webp"));
        assert!(!safe_image_path("images/icons/../a.png"));
        let _ = unselected;
    }
}
