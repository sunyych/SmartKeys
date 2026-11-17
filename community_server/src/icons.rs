use axum::{
    body::Body,
    extract::Path,
    http::{header, HeaderValue, Response, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::Serialize;

#[derive(Serialize)]
pub(super) struct Catalog {
    schema_version: u8,
    icons: &'static [IconRecord],
}

#[derive(Serialize)]
pub(super) struct IconRecord {
    app_id: &'static str,
    name: &'static str,
    download_url: Option<&'static str>,
    mime_type: Option<&'static str>,
    source: &'static str,
    license: &'static str,
    available: bool,
}

const fn entry(
    app_id: &'static str,
    name: &'static str,
    download_url: Option<&'static str>,
    mime_type: Option<&'static str>,
    source: &'static str,
    license: &'static str,
    available: bool,
) -> IconRecord {
    IconRecord { app_id, name, download_url, mime_type, source, license, available }
}

const SIMPLE_ICONS_LICENSE: &str = "No per-icon license listed; check brand terms and trademarks";
const ICONS: &[IconRecord] = &[
    entry("codex", "OpenAI Codex", Some("/v1/icons/codex"), Some("image/png"), "https://cdn.simpleicons.org/openai", SIMPLE_ICONS_LICENSE, true),
    entry("chatgpt", "ChatGPT", Some("/v1/icons/chatgpt"), Some("image/png"), "https://cdn.simpleicons.org/openai", SIMPLE_ICONS_LICENSE, true),
    entry("claude", "Claude", Some("/v1/icons/claude"), Some("image/svg+xml"), "https://cdn.simpleicons.org/anthropic", SIMPLE_ICONS_LICENSE, true),
    entry("cursor", "Cursor", Some("/v1/icons/cursor"), Some("image/svg+xml"), "https://cdn.simpleicons.org/cursor", SIMPLE_ICONS_LICENSE, true),
    entry("chrome", "Google Chrome", Some("/v1/icons/chrome"), Some("image/png"), "https://cdn.simpleicons.org/googlechrome", SIMPLE_ICONS_LICENSE, true),
    entry("edge", "Microsoft Edge", None, None, "", "No approved catalog asset; use the installed app icon", false),
    entry("firefox", "Firefox", Some("/v1/icons/firefox"), Some("image/svg+xml"), "https://cdn.simpleicons.org/firefoxbrowser", SIMPLE_ICONS_LICENSE, true),
    entry("safari", "Safari", Some("/v1/icons/safari"), Some("image/svg+xml"), "https://cdn.simpleicons.org/safari", SIMPLE_ICONS_LICENSE, true),
    entry("teams", "Microsoft Teams", None, None, "", "No approved catalog asset; use the installed app icon", false),
    entry("zoom", "Zoom", Some("/v1/icons/zoom"), Some("image/svg+xml"), "https://cdn.simpleicons.org/zoom", SIMPLE_ICONS_LICENSE, true),
    entry("photoshop", "Adobe Photoshop", Some("/v1/icons/photoshop"), Some("image/png"), "https://cdn.simpleicons.org/adobephotoshop", SIMPLE_ICONS_LICENSE, true),
    entry("illustrator", "Adobe Illustrator", Some("/v1/icons/illustrator"), Some("image/png"), "https://cdn.simpleicons.org/adobeillustrator", SIMPLE_ICONS_LICENSE, true),
    entry("vscode", "Visual Studio Code", Some("/v1/icons/vscode"), Some("image/png"), "https://cdn.simpleicons.org/visualstudiocode", SIMPLE_ICONS_LICENSE, true),
    entry("solidworks", "SOLIDWORKS", Some("/v1/icons/solidworks"), Some("image/png"), "https://cdn.simpleicons.org/dassaultsystemes", SIMPLE_ICONS_LICENSE, true),
    entry("premiere", "Adobe Premiere Pro", Some("/v1/icons/premiere"), Some("image/png"), "https://cdn.simpleicons.org/adobepremierepro", SIMPLE_ICONS_LICENSE, true),
    entry("appleMusic", "Apple Music", Some("/v1/icons/appleMusic"), Some("image/svg+xml"), "https://cdn.simpleicons.org/applemusic", SIMPLE_ICONS_LICENSE, true),
    entry("finder", "Finder", None, None, "", "No approved catalog asset; use the installed app icon", false),
];

pub async fn catalog() -> Json<Catalog> {
    Json(Catalog { schema_version: 1, icons: ICONS })
}

pub async fn get(Path(app_id): Path<String>) -> Response<Body> {
    let (bytes, filename): (&'static [u8], &'static str) = match app_id.as_str() {
        "codex" | "chatgpt" => (include_bytes!("../assets/app_icons/openai.png"), "openai.png"),
        "claude" => (include_bytes!("../assets/app_icons/claude.svg"), "claude.svg"),
        "cursor" => (include_bytes!("../assets/app_icons/cursor.svg"), "cursor.svg"),
        "firefox" => (include_bytes!("../assets/app_icons/firefox.svg"), "firefox.svg"),
        "safari" => (include_bytes!("../assets/app_icons/safari.svg"), "safari.svg"),
        "zoom" => (include_bytes!("../assets/app_icons/zoom.svg"), "zoom.svg"),
        "appleMusic" => (include_bytes!("../assets/app_icons/appleMusic.svg"), "appleMusic.svg"),
        "chrome" => (include_bytes!("../assets/app_icons/chrome.png"), "chrome.png"),
        "vscode" => (include_bytes!("../assets/app_icons/vscode.png"), "vscode.png"),
        "photoshop" => (include_bytes!("../assets/app_icons/photoshop.png"), "photoshop.png"),
        "illustrator" => (include_bytes!("../assets/app_icons/illustrator.png"), "illustrator.png"),
        "premiere" => (include_bytes!("../assets/app_icons/premiere.png"), "premiere.png"),
        "solidworks" => (include_bytes!("../assets/app_icons/solidworks.png"), "solidworks.png"),
        _ => return StatusCode::NOT_FOUND.into_response(),
    };
    let mut response = Response::new(Body::from(bytes));
    *response.status_mut() = StatusCode::OK;
    let headers = response.headers_mut();
    let mime = if filename.ends_with(".svg") { "image/svg+xml" } else { "image/png" };
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static(mime));
    headers.insert(header::X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("public, max-age=86400"));
    headers.insert(header::CONTENT_DISPOSITION, HeaderValue::from_str(&format!("attachment; filename=\"{filename}\"")).unwrap());
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;

    #[tokio::test]
    async fn catalog_is_a_fixed_allowlist_with_same_origin_downloads() {
        let Json(catalog) = catalog().await;
        assert_eq!(catalog.schema_version, 1);
        assert_eq!(catalog.icons.len(), 7);
        for entry in catalog.icons {
            assert_eq!(entry.download_url, format!("/v1/icons/{}", entry.app_id));
            assert_eq!(entry.mime_type, "image/png");
            assert!(entry.source.starts_with("https://cdn.simpleicons.org/"));
        }
    }

    #[tokio::test]
    async fn downloads_known_assets_and_rejects_unknown_ids() {
        for app_id in ["codex", "chrome", "vscode", "photoshop", "illustrator", "premiere", "solidworks"] {
            let response = get(Path(app_id.to_owned())).await;
            assert_eq!(response.status(), StatusCode::OK);
            assert_eq!(response.headers()[header::CONTENT_TYPE], "image/png");
            assert!(response.headers().contains_key(header::CONTENT_DISPOSITION));
            assert!(!to_bytes(response.into_body(), 2_000_000).await.unwrap().is_empty());
        }
        assert_eq!(get(Path("https://example.com/x".to_owned())).await.status(), StatusCode::NOT_FOUND);
        assert_eq!(get(Path("../chrome".to_owned())).await.status(), StatusCode::NOT_FOUND);
    }
}
