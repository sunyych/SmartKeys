use super::*;
use crate::{auth, RateLimiter};
use axum::{routing::post, Router};
use sqlx::postgres::PgPoolOptions;
use std::{
    collections::HashMap,
    hash::RandomState,
    sync::{Arc, Mutex},
};

fn event(index: u32, now: i64) -> Event {
    Event {
        id: format!("12345678-1234-4123-8123-{index:012x}"),
        occurred_at_ms: now,
        last_occurred_at_ms: now,
        app_version: "1.6.0".into(),
        app_build: 8,
        edition: Edition::Full,
        platform: Platform::Android,
        code: Code::ConnectionTimeout,
        repeat_count: 1,
    }
}
fn batch(now: i64) -> Batch {
    Batch {
        schema_version: 1,
        events: vec![event(1, now)],
    }
}

#[test]
fn strict_fields_and_metadata_never_accept_raw_context() {
    let now = now_seconds() * 1000;
    let base = serde_json::json!({"schemaVersion":1,"events":[event(1,now)]});
    for field in [
        "message",
        "exception",
        "stack",
        "keys",
        "appId",
        "token",
        "path",
        "ip",
        "consentEpoch",
    ] {
        let mut poisoned = base.clone();
        poisoned["events"][0][field] =
            serde_json::json!("Bearer token CTRL+C clipboard /private/path 192.168.1.4");
        assert!(serde_json::from_value::<Batch>(poisoned).is_err());
    }
    let mut unknown = base.clone();
    unknown["raw"] = "private".into();
    assert!(serde_json::from_value::<Batch>(unknown).is_err());
    for (field, value) in [
        ("edition", "lite"),
        ("code", "CTRL+C"),
        ("platform", "private"),
        ("appVersion", "token /path"),
        ("id", "device-id"),
    ] {
        let mut poisoned = base.clone();
        poisoned["events"][0][field] = value.into();
        if let Ok(value) = serde_json::from_value::<Batch>(poisoned) {
            assert!(!validate(&value, now));
        }
    }
    assert!(validate(
        &serde_json::from_value::<Batch>(base).unwrap(),
        now
    ));
}
#[test]
fn bounded_batches_time_counts_and_fixed_codes() {
    let now = now_seconds() * 1000;
    let mut value = batch(now);
    assert!(validate(&value, now));
    value.events[0].repeat_count = 1000001;
    assert!(!validate(&value, now));
    value = batch(now);
    value.events[0].last_occurred_at_ms = now + 300001;
    assert!(!validate(&value, now));
    value = batch(now);
    value.events[0].occurred_at_ms = now - RETENTION_MS - 1;
    assert!(!validate(&value, now));
    value = batch(now);
    value.events.push(value.events[0].clone());
    assert!(!validate(&value, now));
    value.events = (0..21).map(|i| event(i, now)).collect();
    assert!(!validate(&value, now));
    value.events.clear();
    assert!(!validate(&value, now));
    let codes = [
        "connectionUnavailable",
        "connectionTimeout",
        "connectionAuthenticationFailed",
        "connectionProtocolInvalid",
        "applicationActivationFailed",
        "shortcutDeliveryFailed",
        "pointerDeliveryFailed",
        "iconDownloadFailed",
        "iconDataInvalid",
        "configurationLoadFailed",
        "configurationInvalid",
        "configurationSaveFailed",
        "storageReadFailed",
        "storageWriteFailed",
        "bluetoothUnavailable",
        "bluetoothPermissionDenied",
        "bluetoothConnectionFailed",
        "bluetoothInputFailed",
        "platformUnavailable",
        "runtimeFailure",
    ];
    for code in codes {
        assert_eq!(
            serde_json::from_value::<Code>(code.into()).unwrap().wire(),
            code
        );
    }
}

async fn http_fixture() -> (String, tokio::task::JoinHandle<()>) {
    let state = AppState {
        pool: PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(100))
            .connect_lazy("postgres://unavailable:unavailable@127.0.0.1:1/unavailable")
            .unwrap(),
        limiter: Arc::new(Mutex::new(RateLimiter {
            buckets: HashMap::new(),
            hasher: RandomState::new(),
            max_clients: 100,
            window: 60,
            limit: 1000,
        })),
        trust_proxy: false,
        verifier: auth::GoogleTokenVerifier::from_env(),
        backup_slots: Arc::new(tokio::sync::Semaphore::new(8)),
    };
    let router = Router::new()
        .route(
            "/v1/diagnostics/errors",
            post(super::post).layer(axum::extract::DefaultBodyLimit::max(MAX_BODY)),
        )
        .with_state(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!(
        "http://{}/v1/diagnostics/errors",
        listener.local_addr().unwrap()
    );
    let task = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    (url, task)
}
#[tokio::test]
async fn http_rejections_are_fixed_and_never_echo_request_content() {
    let (url, task) = http_fixture().await;
    let client = reqwest::Client::new();
    let response = client
        .post(&url)
        .json(&serde_json::json!({"schemaVersion":1,"events":[],"token":"private-token"}))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert_eq!(
        response.text().await.unwrap(),
        "{\"error\":\"invalid_diagnostics\"}"
    );
    let response = client
        .post(&url)
        .header("content-type", "application/json")
        .body(format!(
            "{{\"token\":\"{}\"}}",
            "private-token".repeat(2000)
        ))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    assert!(!response.text().await.unwrap().contains("private-token"));
    assert_eq!(
        client.get(&url).send().await.unwrap().status(),
        StatusCode::METHOD_NOT_ALLOWED
    );
    let response = client
        .post(&url)
        .json(&serde_json::json!({"schemaVersion":1,"events":[event(1,now_seconds()*1000)]}))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(
        response.text().await.unwrap(),
        "{\"error\":\"diagnostics_unavailable\"}"
    );
    task.abort();
}

#[tokio::test]
#[ignore = "requires disposable PostgreSQL in TEST_DATABASE_URL; creates/drops isolated schema"]
async fn postgres_idempotency_conflicts_capacity_retention_and_concurrency() {
    let url = std::env::var("TEST_DATABASE_URL").expect("TEST_DATABASE_URL required");
    let admin = PgPoolOptions::new()
        .max_connections(1)
        .connect(&url)
        .await
        .unwrap();
    let schema = format!("diagnostics_test_{}_{}", std::process::id(), now_seconds());
    sqlx::query(&format!("CREATE SCHEMA {schema}"))
        .execute(&admin)
        .await
        .unwrap();
    let isolated = schema.clone();
    let pool = PgPoolOptions::new()
        .max_connections(8)
        .after_connect(move |connection, _| {
            let sql = format!("SET search_path TO {isolated}");
            Box::pin(async move {
                sqlx::query(&sql).execute(connection).await?;
                Ok(())
            })
        })
        .connect(&url)
        .await
        .unwrap();
    crate::initialize_schema(&pool).await.unwrap();
    crate::initialize_schema(&pool).await.unwrap();
    let now = now_seconds() * 1000;
    let first = event(1, now);
    store(&pool, std::slice::from_ref(&first), now, 3)
        .await
        .unwrap();
    let mut repeated = first.clone();
    repeated.repeat_count = 4;
    repeated.last_occurred_at_ms += 1000;
    store(&pool, &[repeated], now + 1000, 3).await.unwrap();
    store(&pool, std::slice::from_ref(&first), now + 1000, 3)
        .await
        .unwrap();
    let row = sqlx::query(
        "SELECT repeat_count,last_occurred_at_ms FROM diagnostic_errors WHERE event_id=$1",
    )
    .bind(&first.id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(row.get::<i32, _>("repeat_count"), 4);
    assert_eq!(row.get::<i64, _>("last_occurred_at_ms"), now + 1000);
    let mut conflict = first;
    conflict.code = Code::RuntimeFailure;
    assert_eq!(
        store(&pool, &[conflict], now, 3).await,
        Err(StoreError::Conflict)
    );
    let mut tasks = Vec::new();
    for i in 2..12 {
        let pool = pool.clone();
        tasks.push(tokio::spawn(async move {
            store(&pool, &[event(i, now + i as i64)], now, 3)
                .await
                .unwrap();
        }));
    }
    for task in tasks {
        task.await.unwrap();
    }
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM diagnostic_errors")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 3);
    store(&pool, &[], now + RETENTION_MS + 10000, MAX_ROWS)
        .await
        .unwrap();
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM diagnostic_errors")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0);
    let columns:Vec<String>=sqlx::query_scalar("SELECT column_name FROM information_schema.columns WHERE table_schema=$1 AND table_name='diagnostic_errors'").bind(&schema).fetch_all(&pool).await.unwrap();
    for forbidden in [
        "ip",
        "device_id",
        "user_id",
        "token",
        "message",
        "stack",
        "app_id",
    ] {
        assert!(!columns.iter().any(|column| column == forbidden));
    }
    pool.close().await;
    sqlx::query(&format!("DROP SCHEMA {schema} CASCADE"))
        .execute(&admin)
        .await
        .unwrap();
    admin.close().await;
}
