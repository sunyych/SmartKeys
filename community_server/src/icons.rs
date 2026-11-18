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
    canonical_id: &'static str,
    name: &'static str,
    download_url: Option<&'static str>,
    mime_type: Option<&'static str>,
    source: &'static str,
    license: &'static str,
    available: bool,
}

const BRAND_NOTICE: &str =
    "Brand artwork: verify the owner's terms and trademarks. Project CC0 is not a brand license.";
const fn entry(
    app_id: &'static str,
    canonical_id: &'static str,
    name: &'static str,
    download_url: Option<&'static str>,
    source: &'static str,
) -> IconRecord {
    IconRecord {
        app_id,
        canonical_id,
        name,
        download_url,
        mime_type: if download_url.is_some() {
            Some("image/png")
        } else {
            None
        },
        source,
        license: BRAND_NOTICE,
        available: download_url.is_some(),
    }
}

// Codex is only the historical combined ChatGPT ID here. It is not counted
// as another brand and does not assign an unrelated product's artwork.
const ICONS: &[IconRecord] = &[
    entry(
        "codex",
        "chatgpt",
        "ChatGPT (legacy codex ID)",
        Some("/v1/icons/codex"),
        "https://cdn.simpleicons.org/openai",
    ),
    entry(
        "chatgpt",
        "chatgpt",
        "ChatGPT",
        Some("/v1/icons/chatgpt"),
        "https://cdn.simpleicons.org/openai",
    ),
    entry(
        "claude",
        "claude",
        "Claude",
        Some("/v1/icons/claude"),
        "https://cdn.simpleicons.org/claude",
    ),
    entry(
        "cursor",
        "cursor",
        "Cursor",
        Some("/v1/icons/cursor"),
        "https://cdn.simpleicons.org/cursor",
    ),
    entry(
        "chrome",
        "chrome",
        "Google Chrome",
        Some("/v1/icons/chrome"),
        "https://cdn.simpleicons.org/googlechrome",
    ),
    entry(
        "edge",
        "edge",
        "Microsoft Edge",
        Some("/v1/icons/edge"),
        "https://edgecdn-embza6g8cacagcbn.z01.azurefd.net/welcome/static/favicon.png",
    ),
    entry(
        "firefox",
        "firefox",
        "Firefox",
        Some("/v1/icons/firefox"),
        "https://cdn.simpleicons.org/firefoxbrowser",
    ),
    entry(
        "safari",
        "safari",
        "Safari",
        Some("/v1/icons/safari"),
        "https://cdn.simpleicons.org/safari",
    ),
    entry(
        "teams",
        "teams",
        "Microsoft Teams",
        Some("/v1/icons/teams"),
        "https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/Teams-Icon-FY26",
    ),
    entry(
        "zoom",
        "zoom",
        "Zoom",
        Some("/v1/icons/zoom"),
        "https://cdn.simpleicons.org/zoom",
    ),
    entry(
        "photoshop",
        "photoshop",
        "Adobe Photoshop",
        Some("/v1/icons/photoshop"),
        "https://cdn.simpleicons.org/adobephotoshop",
    ),
    entry(
        "illustrator",
        "illustrator",
        "Adobe Illustrator",
        Some("/v1/icons/illustrator"),
        "https://cdn.simpleicons.org/adobeillustrator",
    ),
    entry(
        "vscode",
        "vscode",
        "Visual Studio Code",
        Some("/v1/icons/vscode"),
        "https://cdn.simpleicons.org/visualstudiocode",
    ),
    entry(
        "solidworks",
        "solidworks",
        "SOLIDWORKS",
        Some("/v1/icons/solidworks"),
        "https://help.solidworks.com/favicon.png",
    ),
    entry(
        "premiere",
        "premiere",
        "Adobe Premiere Pro",
        Some("/v1/icons/premiere"),
        "https://cdn.simpleicons.org/adobepremierepro",
    ),
    entry(
        "appleMusic",
        "appleMusic",
        "Apple Music",
        Some("/v1/icons/appleMusic"),
        "https://cdn.simpleicons.org/applemusic",
    ),
    entry(
        "finder",
        "finder",
        "Finder",
        Some("/v1/icons/finder"),
        "https://ipcdn-web.apple.com/assets/v2/web/f2ab6839-b5a7-45f8-bcb3-037aa7887965",
    ),
];

fn png_asset(canonical_id: &str) -> Option<(&'static [u8], &'static str)> {
    Some(match canonical_id {
        "chatgpt" => (
            include_bytes!("../assets/app_icons/openai.png"),
            "chatgpt.png",
        ),
        "claude" => (
            include_bytes!("../assets/app_icons/claude-app.png"),
            "claude.png",
        ),
        "cursor" => (
            include_bytes!("../assets/app_icons/cursor.png"),
            "cursor.png",
        ),
        "chrome" => (
            include_bytes!("../assets/app_icons/chrome.png"),
            "chrome.png",
        ),
        "edge" => (include_bytes!("../assets/app_icons/edge.png"), "edge.png"),
        "firefox" => (
            include_bytes!("../assets/app_icons/firefox.png"),
            "firefox.png",
        ),
        "safari" => (
            include_bytes!("../assets/app_icons/safari.png"),
            "safari.png",
        ),
        "teams" => (include_bytes!("../assets/app_icons/teams.png"), "teams.png"),
        "zoom" => (include_bytes!("../assets/app_icons/zoom.png"), "zoom.png"),
        "photoshop" => (
            include_bytes!("../assets/app_icons/photoshop.png"),
            "photoshop.png",
        ),
        "illustrator" => (
            include_bytes!("../assets/app_icons/illustrator.png"),
            "illustrator.png",
        ),
        "vscode" => (
            include_bytes!("../assets/app_icons/vscode.png"),
            "vscode.png",
        ),
        "solidworks" => (
            include_bytes!("../assets/app_icons/solidworks-app.png"),
            "solidworks.png",
        ),
        "premiere" => (
            include_bytes!("../assets/app_icons/premiere.png"),
            "premiere.png",
        ),
        "appleMusic" => (
            include_bytes!("../assets/app_icons/appleMusic.png"),
            "appleMusic.png",
        ),
        "finder" => (
            include_bytes!("../assets/app_icons/finder.png"),
            "finder.png",
        ),
        _ => return None,
    })
}

fn valid_png(bytes: &[u8]) -> bool {
    if bytes.len() < 24
        || bytes.len() > 64 * 1024
        || &bytes[..8] != b"\x89PNG\r\n\x1a\n"
        || &bytes[12..16] != b"IHDR"
    {
        return false;
    }
    let width = u32::from_be_bytes([bytes[16], bytes[17], bytes[18], bytes[19]]);
    let height = u32::from_be_bytes([bytes[20], bytes[21], bytes[22], bytes[23]]);
    (1..=512).contains(&width) && (1..=512).contains(&height)
}

pub async fn catalog() -> Json<Catalog> {
    Json(Catalog {
        schema_version: 1,
        icons: ICONS,
    })
}

pub async fn get(Path(app_id): Path<String>) -> Response<Body> {
    let Some(record) = ICONS
        .iter()
        .find(|record| record.app_id == app_id && record.available)
    else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let Some((bytes, filename)) = png_asset(record.canonical_id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if !valid_png(bytes) {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let mut response = Response::new(Body::from(bytes));
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("image/png"));
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=86400"),
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
            .expect("fixed ASCII asset filename"),
    );
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use std::collections::HashSet;

    #[tokio::test]
    async fn catalog_distinguishes_registered_ids_from_canonical_brands() {
        let Json(catalog) = catalog().await;
        assert_eq!(catalog.schema_version, 1);
        assert_eq!(catalog.icons.len(), 17);
        assert_eq!(
            catalog
                .icons
                .iter()
                .filter(|icon| icon.available)
                .map(|icon| icon.canonical_id)
                .collect::<HashSet<_>>()
                .len(),
            16
        );
        assert_eq!(
            catalog
                .icons
                .iter()
                .map(|icon| icon.canonical_id)
                .collect::<HashSet<_>>()
                .len(),
            16
        );
        assert_eq!(
            catalog
                .icons
                .iter()
                .map(|icon| icon.app_id)
                .collect::<HashSet<_>>()
                .len(),
            17
        );
        for record in catalog.icons {
            if record.available {
                assert_eq!(
                    record.download_url,
                    Some(format!("/v1/icons/{}", record.app_id).as_str())
                );
                assert_eq!(record.mime_type, Some("image/png"));
                assert!(record.source.starts_with("https://"));
                assert!(png_asset(record.canonical_id).is_some());
            } else {
                assert!(record.download_url.is_none());
                assert!(record.mime_type.is_none());
            }
            assert!(record.license.contains("owner"));
        }
    }

    #[tokio::test]
    async fn every_available_asset_is_bounded_png_with_safe_download_headers() {
        for record in ICONS.iter().filter(|record| record.available) {
            let response = get(Path(record.app_id.to_owned())).await;
            assert_eq!(response.status(), StatusCode::OK, "{}", record.app_id);
            assert_eq!(response.headers()[header::CONTENT_TYPE], "image/png");
            assert_eq!(
                response.headers()[header::X_CONTENT_TYPE_OPTIONS],
                "nosniff"
            );
            assert!(response.headers()[header::CONTENT_DISPOSITION]
                .to_str()
                .unwrap()
                .ends_with(".png\""));
            let body = to_bytes(response.into_body(), 64 * 1024).await.unwrap();
            assert!(valid_png(&body), "{}", record.app_id);
        }
    }

    #[tokio::test]
    async fn legacy_codex_alias_uses_chatgpt_artwork_without_adding_a_brand() {
        let codex = to_bytes(get(Path("codex".to_owned())).await.into_body(), 64 * 1024)
            .await
            .unwrap();
        let chatgpt = to_bytes(get(Path("chatgpt".to_owned())).await.into_body(), 64 * 1024)
            .await
            .unwrap();
        assert_eq!(codex, chatgpt);
        assert_eq!(
            ICONS
                .iter()
                .find(|record| record.app_id == "codex")
                .unwrap()
                .canonical_id,
            "chatgpt"
        );
    }

    #[tokio::test]
    async fn unknown_paths_and_external_urls_are_not_download_proxies() {
        for id in [
            "unknown-brand",
            "https://example.com/x",
            "../chrome",
            "chrome.png",
            "chrome?url=https://example.com",
        ] {
            assert_eq!(
                get(Path(id.to_owned())).await.status(),
                StatusCode::NOT_FOUND
            );
        }
    }

    #[test]
    fn invalid_or_unbounded_images_are_rejected() {
        assert!(!valid_png(b"<svg>not a PNG</svg>"));
        assert!(!valid_png(&vec![0; 64 * 1024 + 1]));
    }
}
