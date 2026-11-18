use axum::{
    body::Body,
    extract::Path,
    http::{header, HeaderMap, HeaderValue, Response, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::Serialize;

#[derive(Serialize)]
pub(super) struct Catalog {
    schema_version: u8,
    version: &'static str,
    icons: &'static [IconRecord],
    legacy_aliases: &'static [LegacyAlias],
}

#[derive(Serialize)]
struct LegacyAlias {
    app_id: &'static str,
    canonical_id: &'static str,
    description: &'static str,
}

#[derive(Serialize)]
pub(super) struct IconRecord {
    app_id: &'static str,
    canonical_id: &'static str,
    name: &'static str,
    aliases: &'static [&'static str],
    download_url: &'static str,
    mime_type: &'static str,
    source: &'static str,
    source_page_url: &'static str,
    terms_url: &'static str,
    license: &'static str,
    available: bool,
    bundled: bool,
    sha256: &'static str,
    version: &'static str,
    width: u32,
    height: u32,
}

include!("builtin_icon_catalog.g.rs");

/// Exact canonical registration only: public App identities never use legacy
/// artwork aliases (in particular codex -> chatgpt).
pub(super) fn registered_png(id: &str) -> Option<(&'static str, &'static [u8])> {
    let record = ICONS.iter().find(|record| record.canonical_id == id)?;
    let bytes = png_asset(record.canonical_id)?;
    valid_png(bytes).then_some((record.sha256, bytes))
}

const LEGACY_ALIASES: &[LegacyAlias] = &[LegacyAlias {
    app_id: "codex",
    canonical_id: "chatgpt",
    description: "Historical LumiaKey protocol/configuration ID for ChatGPT artwork; not the Codex product or another catalog entry.",
}];

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
    width == 256 && height == 256
}

pub async fn catalog() -> impl IntoResponse {
    (
        [(header::CACHE_CONTROL, "public, max-age=3600")],
        Json(Catalog {
            schema_version: 1,
            version: CATALOG_VERSION,
            icons: ICONS,
            legacy_aliases: LEGACY_ALIASES,
        }),
    )
}

fn lookup(id: &str) -> Option<&'static IconRecord> {
    if id.is_empty()
        || id.len() > 64
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_-".contains(&byte))
    {
        return None;
    }
    // Kept outside normal product aliases/search: Codex has its own identity.
    let product = if id.eq_ignore_ascii_case("codex") {
        "chatgpt"
    } else {
        id
    };
    ICONS.iter().find(|icon| {
        icon.app_id.eq_ignore_ascii_case(product)
            || icon
                .aliases
                .iter()
                .any(|alias| alias.eq_ignore_ascii_case(product))
    })
}

pub async fn get(Path(app_id): Path<String>, request_headers: HeaderMap) -> Response<Body> {
    let Some(record) = lookup(&app_id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let Some(bytes) = png_asset(record.canonical_id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if !valid_png(bytes) {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let etag = format!("\"{}\"", record.sha256);
    let cached = request_headers
        .get(header::IF_NONE_MATCH)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| {
            value
                .split(',')
                .any(|tag| tag.trim() == etag || tag.trim() == "*")
        });
    let mut response = Response::new(if cached {
        Body::empty()
    } else {
        Body::from(bytes)
    });
    if cached {
        *response.status_mut() = StatusCode::NOT_MODIFIED;
    }
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
        header::ETAG,
        HeaderValue::from_str(&etag).expect("generated SHA256"),
    );
    headers.insert(
        header::CONTENT_LOCATION,
        HeaderValue::from_static(record.download_url),
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!(
            "attachment; filename=\"{}.png\"",
            record.canonical_id
        ))
        .expect("registered ASCII filename"),
    );
    if app_id.eq_ignore_ascii_case("codex") {
        headers.insert(
            "x-lumiakey-legacy-icon",
            HeaderValue::from_static("chatgpt; historical-protocol-alias"),
        );
    }
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use sha2::{Digest, Sha256};
    use std::collections::HashSet;

    #[tokio::test]
    async fn catalog_has_fifty_actual_builtins_and_ten_web_only_products() {
        assert_eq!(ICONS.len(), 60);
        assert_eq!(ICONS.iter().filter(|icon| icon.bundled).count(), 50);
        assert_eq!(
            ICONS
                .iter()
                .map(|icon| icon.sha256)
                .collect::<HashSet<_>>()
                .len(),
            60
        );
        assert_eq!(
            ICONS
                .iter()
                .map(|icon| icon.app_id)
                .collect::<HashSet<_>>()
                .len(),
            60
        );
        assert!(!ICONS
            .iter()
            .any(|icon| icon.app_id == "codex" || icon.aliases.contains(&"codex")));
        for icon in ICONS {
            assert_eq!(icon.app_id, icon.canonical_id);
            assert!(icon.source_page_url.starts_with("https://"));
            assert!(icon.terms_url.starts_with("https://"));
            assert!(!icon.version.is_empty());
            assert!(icon.available);
        }
        assert!(!lookup("brave").unwrap().bundled);
    }

    #[tokio::test]
    async fn every_actual_png_matches_hash_dimensions_and_safe_download_headers() {
        for icon in ICONS {
            let response = get(Path(icon.app_id.to_owned()), HeaderMap::new()).await;
            assert_eq!(response.status(), StatusCode::OK, "{}", icon.app_id);
            assert_eq!(response.headers()[header::CONTENT_TYPE], "image/png");
            assert_eq!(
                response.headers()[header::X_CONTENT_TYPE_OPTIONS],
                "nosniff"
            );
            assert_eq!(
                response.headers()[header::ETAG],
                format!("\"{}\"", icon.sha256)
            );
            assert_eq!(
                response.headers()[header::CONTENT_DISPOSITION],
                format!("attachment; filename=\"{}.png\"", icon.app_id)
            );
            let bytes = to_bytes(response.into_body(), 65536).await.unwrap();
            assert!(valid_png(&bytes), "{}", icon.app_id);
            assert_eq!(format!("{:x}", Sha256::digest(&bytes)), icon.sha256);
        }
    }

    #[tokio::test]
    async fn etag_avoids_resending_unchanged_bytes_but_stale_versions_receive_png() {
        let icon = lookup("chrome").unwrap();
        let mut headers = HeaderMap::new();
        headers.insert(
            header::IF_NONE_MATCH,
            HeaderValue::from_str(&format!("\"{}\"", icon.sha256)).unwrap(),
        );
        let response = get(Path("chrome".into()), headers.clone()).await;
        assert_eq!(response.status(), StatusCode::NOT_MODIFIED);
        assert!(to_bytes(response.into_body(), 65536)
            .await
            .unwrap()
            .is_empty());
        headers.insert(
            header::IF_NONE_MATCH,
            HeaderValue::from_static("\"previous-version\""),
        );
        assert_eq!(
            get(Path("chrome".into()), headers).await.status(),
            StatusCode::OK
        );
    }

    #[tokio::test]
    async fn ordinary_aliases_and_separate_legacy_urls_resolve_canonical_bytes() {
        assert_eq!(lookup("VS-Code").unwrap().app_id, "vscode");
        assert_eq!(lookup("APPLE-MUSIC").unwrap().app_id, "appleMusic");
        let legacy = get(Path("codex".into()), HeaderMap::new()).await;
        assert!(legacy.headers().contains_key("x-lumiakey-legacy-icon"));
        let bytes = to_bytes(legacy.into_body(), 65536).await.unwrap();
        assert_eq!(bytes.as_ref(), png_asset("chatgpt").unwrap());
    }

    #[tokio::test]
    async fn unknown_paths_and_external_urls_are_never_download_proxies() {
        for id in [
            "unknown-brand",
            "https://example.com/x",
            "../chrome",
            "chrome.png",
            "chrome?url=https://example.com",
        ] {
            assert_eq!(
                get(Path(id.to_owned()), HeaderMap::new()).await.status(),
                StatusCode::NOT_FOUND
            );
        }
        assert!(!valid_png(b"<svg>not PNG</svg>"));
        assert!(!valid_png(&vec![0; 65537]));
    }
}
