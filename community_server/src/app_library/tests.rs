use super::*;
use serde_json::{json, Value};

fn raw() -> Value {
    serde_json::from_str(CATALOG).unwrap()
}
fn accepts(value: &Value) -> bool {
    parse_catalog(&serde_json::to_vec(value).unwrap()).is_ok()
}
fn first_app() -> App {
    parse_catalog(CATALOG.as_bytes()).unwrap().apps.remove(0)
}

#[test]
fn reviewed_catalog_binds_sixty_distinct_icons_and_preserves_explicit_os() {
    let catalog = parse_catalog(CATALOG.as_bytes()).unwrap();
    assert_eq!(catalog.apps.len(), 60);
    assert_eq!(catalog.apps.iter().filter(|app| app.bundled).count(), 50);
    assert!(!catalog.apps.iter().any(|app| app.id == "codex"));
    for name in ["safari", "finder"] {
        let app = catalog.apps.iter().find(|app| app.id == name).unwrap();
        assert_eq!(app.supported_os, ["macos"]);
        assert!(app
            .libraries
            .iter()
            .all(|library| library.family == "macos"));
    }
    let notepad = catalog
        .apps
        .iter()
        .find(|app| app.id == "notepadplusplus")
        .unwrap();
    assert_eq!(notepad.libraries[0].family, "windowsLinux");
    assert_eq!(notepad.libraries[0].supported_os, ["windows"]);
    assert!(catalog
        .apps
        .iter()
        .flat_map(|app| &app.libraries)
        .flat_map(|library| &library.actions)
        .any(|action| action.requires_configuration));
}

#[test]
fn executable_fields_cannot_enter_the_public_action_schema() {
    for field in [
        "command",
        "args",
        "path",
        "url",
        "script",
        "steps",
        "companion",
        "value",
        "installedApplicationId",
    ] {
        let mut value = raw();
        value["apps"][0]["libraries"][0]["actions"][0][field] = json!("never execute");
        assert!(!accepts(&value), "accepted {field}");
    }
    let mut value = raw();
    value["apps"][0]["executable"] = json!("anything");
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][0]["libraries"][0]["actions"] = json!([]);
    assert!(!accepts(&value));
}

#[test]
fn single_chords_unassigned_actions_and_twelve_key_bound_are_strict() {
    for keys in [
        json!([]),
        json!(["CTRL", "CTRL", "A"]),
        json!(["CTRL", "A", "CTRL", "B"]),
        json!(["CMD", "A"]),
        json!(["CTRL+A"]),
        json!(["CTRL", ","]),
        json!(["CTRL", "KEY_A"]),
        json!(["CTRL", "F13"]),
    ] {
        let mut value = raw();
        value["apps"][0]["libraries"][0]["actions"][0]["keys"] = keys;
        assert!(!accepts(&value));
    }
    let mut value = raw();
    value["apps"][0]["libraries"][0]["actions"][0]["requiresConfiguration"] = json!(true);
    assert!(!accepts(&value));
    value["apps"][0]["libraries"][0]["actions"][0]["keys"] = json!([]);
    assert!(accepts(&value));
    let action = value["apps"][0]["libraries"][0]["actions"][0].clone();
    value["apps"][0]["libraries"][0]["actions"]
        .as_array_mut()
        .unwrap()
        .push(action);
    assert!(!accepts(&value));
}

#[test]
fn impossible_os_family_union_and_duplicate_identities_are_rejected() {
    for systems in [
        json!([]),
        json!(["android"]),
        json!(["macos", "linux"]),
        json!(["macos", "macos"]),
    ] {
        let mut value = raw();
        value["apps"][0]["libraries"][0]["supportedOS"] = systems;
        assert!(!accepts(&value));
    }
    let mut value = raw();
    value["apps"][0]["supportedOS"] = json!(["macos"]);
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][0]["libraries"][1]["family"] = json!("macos");
    assert!(!accepts(&value));
    let mut value = raw();
    let duplicate = value["apps"][0].clone();
    value["apps"].as_array_mut().unwrap().push(duplicate);
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][1]["aliases"] = json!(["CHROME"]);
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][0]["aliases"] = json!(["codex"]);
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][0]["id"] = json!("codex");
    value["apps"][0]["iconId"] = json!("codex");
    assert!(!accepts(&value));
}

#[test]
fn text_and_provenance_limits_match_the_shared_dart_contract() {
    for url in [
        "http://example.com",
        "https://user:secret@example.com",
        "https://example.com/#section",
        " https://example.com",
        "file:///tmp/data",
    ] {
        let mut value = raw();
        value["apps"][0]["libraries"][0]["sourceUrls"] = json!([url]);
        assert!(!accepts(&value));
    }
    let mut value = raw();
    value["apps"][0]["name"] = json!("你".repeat(120));
    value["apps"][0]["libraries"][0]["actions"][0]["title"] = json!("你".repeat(80));
    value["apps"][0]["libraries"][0]["version"] = json!("Reviewed version 2");
    assert!(accepts(&value));
    value["apps"][0]["libraries"][0]["actions"][0]["title"] = json!("你".repeat(81));
    assert!(!accepts(&value));
    for bad_name in [
        " leading".to_owned(),
        "trailing ".to_owned(),
        "a".repeat(121),
        "bad\nname".to_owned(),
    ] {
        let mut value = raw();
        value["apps"][0]["name"] = json!(bad_name);
        assert!(!accepts(&value));
    }
    let mut value = raw();
    value["apps"][0]["libraries"][0]["sourceUrls"] =
        json!(["https://example.com", "https://example.com"]);
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][0]["libraries"][0]["id"] = json!("other.macos.default");
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][0]["aliases"] = json!([".unsafe"]);
    assert!(!accepts(&value));
}

#[test]
fn legacy_missing_context_and_catalog_version_remain_compatible_but_unknown_fields_do_not() {
    let mut value = raw();
    value.as_object_mut().unwrap().remove("version");
    value["apps"][0]["libraries"][0]
        .as_object_mut()
        .unwrap()
        .remove("context");
    assert!(accepts(&value));
    value["apps"][0]["libraries"][0]["context"] = json!("shell");
    assert!(!accepts(&value));
    assert!(parse_catalog(b"{\"schemaVersion\":1,\"schemaVersion\":1,\"apps\":[]}").is_err());
    assert!(parse_catalog(&[b' '; MAX_CATALOG + 1]).is_err());
}

#[test]
fn fixed_schema_and_field_types_are_not_coerced() {
    for schema in [json!(1.0), json!(true), json!("1"), Value::Null] {
        let mut value = raw();
        value["schemaVersion"] = schema;
        assert!(!accepts(&value));
    }
    for field in ["version", "context"] {
        let mut value = raw();
        if field == "version" {
            value[field] = Value::Null;
        } else {
            value["apps"][0]["libraries"][0][field] = Value::Null;
        }
        assert!(!accepts(&value));
    }
    let mut value = raw();
    value["apps"][0]["bundled"] = json!(1);
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][0]["libraries"][0]["actions"][0]["requiresConfiguration"] = json!("false");
    assert!(!accepts(&value));
    let mut value = raw();
    value["apps"][0]["libraries"][0]["actions"][0]["keys"] = json!(["CTRL", 1]);
    assert!(!accepts(&value));
}

#[test]
fn bundle_identity_base64_hash_bytes_and_size_are_all_verified() {
    let registry = registry().unwrap();
    let app = first_app();
    let published = registry
        .bundles
        .iter()
        .find(|bundle| bundle.app_id == app.id)
        .unwrap();
    assert!(validate_bundle(&published.bytes, &app).is_ok());
    let baseline: Value = serde_json::from_slice(&published.bytes).unwrap();
    for (path, bad) in [
        ("id", json!("other")),
        ("sha256", json!("0".repeat(64))),
        ("pngBase64", json!("@@@=")),
        ("pngBase64", json!(STANDARD.encode(b"not PNG"))),
    ] {
        let mut value = baseline.clone();
        value["icon"][path] = bad;
        assert!(validate_bundle(&serde_json::to_vec(&value).unwrap(), &app).is_err());
    }
    let mut value = baseline.clone();
    value["app"]["name"] = json!("Unreviewed change");
    assert!(validate_bundle(&serde_json::to_vec(&value).unwrap(), &app).is_err());
    let mut value = baseline;
    value["icon"]["url"] = json!("https://example.com");
    assert!(validate_bundle(&serde_json::to_vec(&value).unwrap(), &app).is_err());
    assert!(validate_bundle(&[b' '; MAX_BUNDLE + 1], &app).is_err());
}

#[tokio::test]
async fn real_http_downloads_hashes_etags_immutable_paths_and_read_only_methods() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        axum::serve(listener, Router::new().merge(routes()))
            .await
            .unwrap();
    });
    let client = reqwest::Client::builder().no_proxy().build().unwrap();
    let catalog_response = client
        .get(format!("{base}/v1/apps/catalog"))
        .send()
        .await
        .unwrap();
    assert_eq!(catalog_response.status(), StatusCode::OK);
    let catalog_etag = catalog_response.headers()[header::ETAG].clone();
    let catalog: Catalog = catalog_response.json().await.unwrap();
    assert_eq!(
        client
            .get(format!("{base}/v1/apps/catalog"))
            .header(header::IF_NONE_MATCH, catalog_etag)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NOT_MODIFIED
    );
    for app in &catalog.apps {
        let url = format!("{base}/v1/apps/{}/bundle", app.id);
        let response = client.get(&url).send().await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()[header::CONTENT_TYPE], "application/json");
        assert_eq!(
            response.headers()[header::X_CONTENT_TYPE_OPTIONS],
            "nosniff"
        );
        let location = response.headers()[header::CONTENT_LOCATION]
            .to_str()
            .unwrap()
            .to_owned();
        let etag = response.headers()[header::ETAG].clone();
        assert!(response.headers()[header::CONTENT_DISPOSITION]
            .to_str()
            .unwrap()
            .contains(&format!("{}.lumia-app.json", app.id)));
        let bytes = response.bytes().await.unwrap();
        assert!(bytes.len() <= MAX_BUNDLE);
        validate_bundle(&bytes, app).unwrap();
        assert_eq!(etag.to_str().unwrap(), format!("\"{}\"", hash(&bytes)));
        assert_eq!(
            location,
            format!("/v1/apps/{}/bundles/{}.json", app.id, hash(&bytes))
        );
        let immutable = client
            .get(format!("{base}{location}"))
            .send()
            .await
            .unwrap();
        assert!(immutable.headers()[header::CACHE_CONTROL]
            .to_str()
            .unwrap()
            .contains("immutable"));
        assert_eq!(immutable.bytes().await.unwrap(), bytes);
        assert_eq!(
            client
                .get(&url)
                .header(header::IF_NONE_MATCH, etag)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::NOT_MODIFIED
        );
        assert_eq!(
            client
                .post(&url)
                .json(&json!({"command":"never execute"}))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::METHOD_NOT_ALLOWED
        );
    }
    for path in [
        "/v1/apps/unknown/bundle",
        "/v1/apps/codex/bundle",
        "/v1/apps/chrome/bundles/not-a-hash.json",
        &format!("/v1/apps/chrome/bundles/{}.json", "0".repeat(64)),
    ] {
        assert_eq!(
            client
                .get(format!("{base}{path}"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::NOT_FOUND
        );
    }
    assert_eq!(
        client
            .post(format!("{base}/v1/apps/catalog"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::METHOD_NOT_ALLOWED
    );
    let web = client.get(format!("{base}/apps")).send().await.unwrap();
    assert!(web.headers().contains_key(header::CONTENT_SECURITY_POLICY));
    assert!(web.text().await.unwrap().contains("App 与快捷键库"));
    server.abort();
}
