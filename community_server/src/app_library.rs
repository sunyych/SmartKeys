//! Reviewed, non-executing public keyboard libraries. Private backup validation
//! is intentionally not used here.
use axum::{
    body::Body,
    extract::Path,
    http::{header, HeaderMap, HeaderValue, Response, StatusCode},
    response::IntoResponse,
    routing::get,
    Router,
};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{collections::HashSet, sync::OnceLock};

const MAX_CATALOG: usize = 512 * 1024;
pub(super) const MAX_BUNDLE: usize = 128 * 1024;
const MAX_PNG: usize = 64 * 1024;
const CATALOG: &str = include_str!("../assets/app_library/catalog.json");

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Catalog {
    schema_version: u8,
    #[serde(default = "default_version")]
    version: String,
    apps: Vec<App>,
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct App {
    id: String,
    icon_id: String,
    name: String,
    aliases: Vec<String>,
    bundled: bool,
    #[serde(rename = "supportedOS")]
    supported_os: Vec<String>,
    libraries: Vec<Library>,
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Library {
    id: String,
    family: String,
    #[serde(rename = "supportedOS")]
    supported_os: Vec<String>,
    version: String,
    source_urls: Vec<String>,
    #[serde(default = "native_context")]
    context: String,
    actions: Vec<Action>,
}
fn default_version() -> String {
    "1".into()
}
fn native_context() -> String {
    "native".into()
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Action {
    id: String,
    title: String,
    keys: Vec<String>,
    requires_configuration: bool,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Bundle {
    schema_version: u8,
    app: App,
    icon: BundleIcon,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct BundleIcon {
    id: String,
    sha256: String,
    png_base64: String,
}
struct Published {
    app_id: String,
    bytes: Vec<u8>,
    sha256: String,
}
struct Registry {
    catalog: Vec<u8>,
    catalog_hash: String,
    bundles: Vec<Published>,
}

fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn text(value: &str, maximum: usize) -> bool {
    !value.is_empty()
        && value == value.trim()
        && value.encode_utf16().count() <= maximum
        && !value
            .chars()
            .any(|character| character <= '\u{1f}' || character == '\u{7f}')
}
fn id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 80
        && value.as_bytes()[0].is_ascii_alphanumeric()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_.-".contains(&byte))
        && !value.starts_with("installed.")
}
fn os_set(values: &[String]) -> Result<HashSet<&str>, ()> {
    let set: HashSet<_> = values.iter().map(String::as_str).collect();
    if values.is_empty()
        || values.len() > 3
        || set.len() != values.len()
        || set
            .iter()
            .any(|value| !["macos", "windows", "linux"].contains(value))
    {
        return Err(());
    }
    Ok(set)
}
fn key(value: &str) -> bool {
    value.len() == 1
        && value
            .bytes()
            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
        || matches!(
            value,
            "F1" | "F2"
                | "F3"
                | "F4"
                | "F5"
                | "F6"
                | "F7"
                | "F8"
                | "F9"
                | "F10"
                | "F11"
                | "F12"
                | "ENTER"
                | "ESC"
                | "BACKSPACE"
                | "TAB"
                | "SPACE"
                | "LEFT"
                | "RIGHT"
                | "UP"
                | "DOWN"
                | "DELETE"
                | "HOME"
                | "END"
                | "PAGE_UP"
                | "PAGE_DOWN"
                | "MINUS"
                | "EQUAL"
                | "LEFT_BRACKET"
                | "RIGHT_BRACKET"
                | "BACKSLASH"
                | "SEMICOLON"
                | "QUOTE"
                | "BACKTICK"
                | "COMMA"
                | "PERIOD"
                | "SLASH"
        )
}
fn validate_app(app: &App) -> Result<(), ()> {
    if !id(&app.id)
        || app.id != app.icon_id
        || app.id.eq_ignore_ascii_case("codex")
        || app.aliases.iter().collect::<HashSet<_>>().len() != app.aliases.len()
        || !text(&app.name, 120)
        || app.aliases.len() > 16
        || app
            .aliases
            .iter()
            .any(|alias| !id(alias) || alias.eq_ignore_ascii_case("codex"))
        || !(1..=2).contains(&app.libraries.len())
    {
        return Err(());
    }
    let app_os = os_set(&app.supported_os)?;
    let mut families = HashSet::new();
    let mut library_ids = HashSet::new();
    let mut union = HashSet::new();
    for library in &app.libraries {
        let systems = os_set(&library.supported_os)?;
        if !id(&library.id)
            || !library.id.starts_with(&format!("{}.", app.id))
            || !library_ids.insert(&library.id)
            || !families.insert(&library.family)
            || !text(&library.version, 80)
            || !["native", "web", "terminal"].contains(&library.context.as_str())
            || !(1..=12).contains(&library.source_urls.len())
            || library.source_urls.iter().collect::<HashSet<_>>().len() != library.source_urls.len()
            || library.actions.is_empty()
            || library.actions.len() > 12
        {
            return Err(());
        }
        match library.family.as_str() {
            "macos" if systems.iter().all(|os| *os == "macos") => {}
            "windowsLinux" if systems.iter().all(|os| ["windows", "linux"].contains(os)) => {}
            _ => return Err(()),
        }
        for url in &library.source_urls {
            let parsed = reqwest::Url::parse(url).map_err(|_| ())?;
            if !text(url, 2048)
                || parsed.scheme() != "https"
                || parsed.host_str().is_none()
                || !parsed.username().is_empty()
                || parsed.password().is_some()
                || parsed
                    .fragment()
                    .is_some_and(|fragment| !fragment.is_empty())
            {
                return Err(());
            }
        }
        union.extend(systems);
        let mut action_ids = HashSet::new();
        for action in &library.actions {
            if !id(&action.id)
                || !action_ids.insert(&action.id)
                || !text(&action.title, 80)
                || action.keys.len() > 5
            {
                return Err(());
            }
            if action.requires_configuration {
                if !action.keys.is_empty() {
                    return Err(());
                }
                continue;
            }
            let Some(last) = action.keys.last() else {
                return Err(());
            };
            if !key(last) {
                return Err(());
            }
            let mut modifiers = HashSet::new();
            for modifier in &action.keys[..action.keys.len() - 1] {
                if !["CTRL", "ALT", "SHIFT", "META"].contains(&modifier.as_str())
                    || !modifiers.insert(modifier)
                {
                    return Err(());
                }
            }
        }
    }
    if union != app_os {
        return Err(());
    }
    Ok(())
}
fn parse_catalog(bytes: &[u8]) -> Result<Catalog, ()> {
    if bytes.len() > MAX_CATALOG {
        return Err(());
    }
    let catalog: Catalog = serde_json::from_slice(bytes).map_err(|_| ())?;
    if catalog.schema_version != 1
        || !text(&catalog.version, 80)
        || catalog.apps.is_empty()
        || catalog.apps.len() > 256
    {
        return Err(());
    }
    let mut identities = HashSet::new();
    for app in &catalog.apps {
        validate_app(app)?;
        for identity in std::iter::once(&app.id).chain(&app.aliases) {
            if !identities.insert(identity.to_ascii_lowercase()) {
                return Err(());
            }
        }
        let (expected, png) = super::icons::registered_png(&app.icon_id).ok_or(())?;
        if hash(png) != expected {
            return Err(());
        }
    }
    Ok(catalog)
}
fn validate_bundle(bytes: &[u8], expected: &App) -> Result<Bundle, ()> {
    if bytes.len() > MAX_BUNDLE {
        return Err(());
    }
    let bundle: Bundle = serde_json::from_slice(bytes).map_err(|_| ())?;
    validate_app(&bundle.app)?;
    if bundle.schema_version != 1
        || bundle.app != *expected
        || bundle.icon.id != bundle.app.icon_id
        || bundle.icon.png_base64.len() > MAX_PNG.div_ceil(3) * 4
    {
        return Err(());
    }
    let (sha256, png) = super::icons::registered_png(&bundle.icon.id).ok_or(())?;
    let decoded = STANDARD.decode(&bundle.icon.png_base64).map_err(|_| ())?;
    if decoded.len() > MAX_PNG
        || decoded != png
        || hash(&decoded) != bundle.icon.sha256
        || bundle.icon.sha256 != sha256
    {
        return Err(());
    }
    Ok(bundle)
}
fn build_registry() -> Result<Registry, ()> {
    let catalog = parse_catalog(CATALOG.as_bytes())?;
    let mut bundles = Vec::new();
    for app in &catalog.apps {
        let (sha256, png) = super::icons::registered_png(&app.icon_id).ok_or(())?;
        let bytes = serde_json::to_vec(&Bundle {
            schema_version: 1,
            app: app.clone(),
            icon: BundleIcon {
                id: app.icon_id.clone(),
                sha256: sha256.into(),
                png_base64: STANDARD.encode(png),
            },
        })
        .map_err(|_| ())?;
        validate_bundle(&bytes, app)?;
        bundles.push(Published {
            app_id: app.id.clone(),
            sha256: hash(&bytes),
            bytes,
        });
    }
    let catalog = serde_json::to_vec(&catalog).map_err(|_| ())?;
    Ok(Registry {
        catalog_hash: hash(&catalog),
        catalog,
        bundles,
    })
}
fn registry() -> Result<&'static Registry, ()> {
    static REGISTRY: OnceLock<Result<Registry, ()>> = OnceLock::new();
    REGISTRY
        .get_or_init(build_registry)
        .as_ref()
        .map_err(|_| ())
}
fn response(
    bytes: &[u8],
    sha256: &str,
    request: &HeaderMap,
    cache: &'static str,
    location: Option<&str>,
    filename: Option<&str>,
) -> Response<Body> {
    let etag = format!("\"{sha256}\"");
    let cached = request
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
        Body::from(bytes.to_vec())
    });
    if cached {
        *response.status_mut() = StatusCode::NOT_MODIFIED;
    }
    let headers = response.headers_mut();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/json"),
    );
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static(cache));
    headers.insert(header::ETAG, HeaderValue::from_str(&etag).expect("SHA256"));
    if let Some(location) = location {
        headers.insert(
            header::CONTENT_LOCATION,
            HeaderValue::from_str(location).expect("registered URL"),
        );
    }
    if let Some(filename) = filename {
        headers.insert(
            header::CONTENT_DISPOSITION,
            HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
                .expect("registered filename"),
        );
    }
    response
}
pub async fn catalog(headers: HeaderMap) -> Response<Body> {
    match registry() {
        Ok(registry) => response(
            &registry.catalog,
            &registry.catalog_hash,
            &headers,
            "public, max-age=3600",
            None,
            None,
        ),
        Err(_) => StatusCode::SERVICE_UNAVAILABLE.into_response(),
    }
}
fn serve_bundle(app_id: &str, requested_hash: Option<&str>, headers: HeaderMap) -> Response<Body> {
    let Ok(registry) = registry() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let Some(bundle) = registry
        .bundles
        .iter()
        .find(|bundle| bundle.app_id == app_id)
    else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if requested_hash.is_some_and(|value| value != bundle.sha256) {
        return StatusCode::NOT_FOUND.into_response();
    }
    let location = format!("/v1/apps/{app_id}/bundles/{}.json", bundle.sha256);
    response(
        &bundle.bytes,
        &bundle.sha256,
        &headers,
        if requested_hash.is_some() {
            "public, max-age=31536000, immutable"
        } else {
            "no-cache"
        },
        Some(&location),
        Some(&format!("{app_id}.lumia-app.json")),
    )
}
pub async fn latest(Path(app_id): Path<String>, headers: HeaderMap) -> Response<Body> {
    serve_bundle(&app_id, None, headers)
}
pub async fn immutable(
    Path((app_id, hash)): Path<(String, String)>,
    headers: HeaderMap,
) -> Response<Body> {
    let Some(hash) = hash
        .strip_suffix(".json")
        .filter(|value| super::lower_hex(value, 64))
    else {
        return StatusCode::NOT_FOUND.into_response();
    };
    serve_bundle(&app_id, Some(hash), headers)
}
pub fn routes<S: Clone + Send + Sync + 'static>() -> Router<S> {
    Router::new()
        .route("/apps", get(super::web::apps_index))
        .route("/assets/apps.css", get(super::web::apps_css))
        .route("/assets/apps.js", get(super::web::apps_js))
        .route("/v1/apps/catalog", get(catalog))
        .route("/v1/apps/:app_id/bundle", get(latest))
        .route("/v1/apps/:app_id/bundles/:hash", get(immutable))
}

#[cfg(test)]
mod tests;
