use super::*;
use contributions::{validate, ContributionRequest, Item, ALLOWED};
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::Serialize;

const TEST_RSA_MODULUS: &str = "rgMkuKRWIAbKu6Bd6yXVHs_54hHeplayUQykGNUbCQMjGL5x4idluZN_CsPjK4qFZEoobBRrsGQE0iiOQgH02coFIky64ZJrx-IM-Xu0YTbljrLvxXSyNaJ3hGqqYqKNukYTITHLo5FIvZnS5IftfjdNRMX3hoJND_jgkg-wqTNVsDyUuguGLT7nqEs5-nE-U5xIiN29X6NsRjag6zmHYFvadyR4L_H-nixEXT8KPz4qYT1lYzzbTlcgaKXzdxSogJ2_QxUFIsJyWkTUsTI6_fA0E5tg-gEaBbUqoPiYnxnjHUpvDSBuU4UCVRKLUKx8YLUWC5XDdNWYq24sznJpCw";

#[derive(Serialize)]
struct AccountClaims {
    iss: String,
    aud: String,
    sub: String,
    exp: u64,
}

fn account_token_for(subject: &str, audience: &str, exp: u64) -> String {
    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some("backup-fixture-key".into());
    encode(
        &header,
        &AccountClaims {
            iss: "https://accounts.google.com".into(),
            aud: audience.into(),
            sub: subject.into(),
            exp,
        },
        &EncodingKey::from_rsa_pem(include_bytes!("../tests/fixtures/test-rsa-private.pem"))
            .unwrap(),
    )
    .unwrap()
}

fn account_token(subject: &str, audience: &str) -> String {
    account_token_for(subject, audience, now_seconds() as u64 + 300)
}

fn account_token_expired(subject: &str, audience: &str) -> String {
    account_token_for(subject, audience, 1)
}

async fn local_jwks_server() -> (String, tokio::task::JoinHandle<()>) {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/jwks", listener.local_addr().unwrap());
    let body = serde_json::json!({"keys":[{"kid":"backup-fixture-key","kty":"RSA","alg":"RS256","use":"sig","n":TEST_RSA_MODULUS,"e":"AQAB"}]}).to_string();
    let task = tokio::spawn(async move {
        let mut requests = 0;
        while let Ok((mut stream, _)) = listener.accept().await {
            requests += 1;
            let mut request = [0u8; 2048];
            let _ = stream.read(&mut request).await;
            let response = format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nCache-Control: public, max-age=60\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
            let _ = stream.write_all(response.as_bytes()).await;
            if requests >= 2 {
                break;
            }
        }
    });
    (url, task)
}

fn full_general_profile() -> serde_json::Value {
    let mut profile: serde_json::Value =
        serde_json::from_str(include_str!("../../assets/profiles/general.json")).unwrap();
    fn fill_visual(value: &mut serde_json::Value) {
        let obj = value.as_object_mut().unwrap();
        for (key, default) in [
            ("tintColor", serde_json::Value::Null),
            ("backgroundColor", serde_json::Value::Null),
            ("iconSize", serde_json::json!(32)),
            ("imageScale", serde_json::json!(1)),
            ("alignmentX", serde_json::json!(0)),
            ("alignmentY", serde_json::json!(0)),
        ] {
            obj.entry(key).or_insert(default);
        }
    }
    fill_visual(&mut profile["profileIcon"]);
    for button in profile["buttons"].as_array_mut().unwrap() {
        fill_visual(&mut button["visual"]);
        let b = button.as_object_mut().unwrap();
        b.insert("hapticEnabled".into(), serde_json::json!(true));
        b.insert("soundEnabled".into(), serde_json::json!(false));
        b.insert("textSize".into(), serde_json::json!(14));
        let action = b.get_mut("action").unwrap().as_object_mut().unwrap();
        action.entry("keyCode").or_insert(serde_json::Value::Null);
        action.entry("value").or_insert(serde_json::Value::Null);
    }
    let wheel = profile["wheel"].as_object_mut().unwrap();
    let none = serde_json::json!({"type":"none","keyCode":null,"modifiers":[],"value":null});
    for key in ["clockwise", "counterClockwise", "center"] {
        wheel.insert(key.into(), none.clone());
    }
    for key in ["up", "down", "left", "right"] {
        if let Some(action) = wheel
            .get_mut(key)
            .and_then(serde_json::Value::as_object_mut)
        {
            action.entry("keyCode").or_insert(serde_json::Value::Null);
        }
    }
    profile
}

fn valid_body() -> ContributionRequest {
    ContributionRequest {
        schema_version: 1,
        batch_id: "a".repeat(32),
        delete_token: "b".repeat(64),
        tag: None,
        items: vec![Item {
            shortcut_id: "copy".into(),
            count: 2,
        }],
    }
}

#[test]
fn accepts_canonical_items_and_hashes_only_safe_payload() {
    let mut body = valid_body();
    body.items = vec![
        Item {
            shortcut_id: "paste".into(),
            count: 3,
        },
        Item {
            shortcut_id: "copy".into(),
            count: 2,
        },
    ];
    let (normalized, token_hash, payload_hash) = validate(body).unwrap();
    assert_eq!(
        normalized
            .items
            .iter()
            .map(|i| i.shortcut_id.as_str())
            .collect::<Vec<_>>(),
        vec!["copy", "paste"]
    );
    assert_eq!(token_hash.len(), 32);
    assert_eq!(payload_hash.len(), 32);
}

#[test]
fn rejects_invalid_ids_fields_duplicate_categories_counts_and_totals() {
    let mut body = valid_body();
    body.batch_id = "A".repeat(32);
    assert!(validate(body).is_err());
    let mut body = valid_body();
    body.delete_token = "b".repeat(63);
    assert!(validate(body).is_err());
    let mut body = valid_body();
    body.items[0].shortcut_id = "custom".into();
    assert!(validate(body).is_err());
    let mut body = valid_body();
    body.items[0].count = 0;
    assert!(validate(body).is_err());
    let mut body = valid_body();
    body.items[0].count = 100_001;
    assert!(validate(body).is_err());
    let mut body = valid_body();
    body.items.push(body.items[0].clone());
    assert!(validate(body).is_err());
    let mut body = valid_body();
    body.items = (0..15)
        .map(|i| Item {
            shortcut_id: ALLOWED[i].into(),
            count: 10_000,
        })
        .collect();
    assert!(validate(body).is_err());
}

#[test]
fn serde_rejects_duplicate_and_unknown_json_fields_and_non_integer_counts() {
    assert!(serde_json::from_str::<ContributionRequest>(r#"{"schema_version":1,"schema_version":1,"batch_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","delete_token":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","items":[{"shortcut_id":"copy","count":1}]}"#).is_err());
    assert!(serde_json::from_str::<ContributionRequest>(r#"{"schema_version":1,"batch_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","delete_token":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","other":true,"items":[{"shortcut_id":"copy","count":1}]}"#).is_err());
    for value in ["true", "1.0", "-1"] {
        let json = format!(
            r#"{{"schema_version":1,"batch_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","delete_token":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","items":[{{"shortcut_id":"copy","count":{value}}}]}}"#
        );
        assert!(
            serde_json::from_str::<ContributionRequest>(&json).is_err(),
            "accepted count {value}"
        );
    }
}

#[test]
fn rate_limiter_enforces_window_and_has_a_hard_client_bound() {
    let mut limiter = RateLimiter {
        buckets: HashMap::new(),
        hasher: RandomState::new(),
        max_clients: 2,
        window: 60,
        limit: 2,
    };
    let a = limiter.client_key("a");
    let b = limiter.client_key("b");
    let c = limiter.client_key("c");
    assert!(limiter.allow(a, 10));
    assert!(limiter.allow(a, 10));
    assert!(!limiter.allow(a, 10));
    assert!(limiter.allow(b, 10));
    assert!(!limiter.allow(c, 10));
    assert!(limiter.allow(a, 70));
    assert!(limiter.buckets.len() <= 2);
}

#[tokio::test]
#[ignore = "requires a disposable PostgreSQL database in TEST_DATABASE_URL; test creates and drops an isolated schema"]
async fn postgres_http_contract_concurrency_withdrawal_threshold_and_periods() {
    let url = std::env::var("TEST_DATABASE_URL").expect("TEST_DATABASE_URL required");
    let admin = PgPoolOptions::new()
        .max_connections(1)
        .connect(&url)
        .await
        .unwrap();
    let schema = format!(
        "community_test_{:032x}",
        now_seconds() as u64 * 1_000_000 + 7
    );
    sqlx::query(&format!("CREATE SCHEMA {schema}"))
        .execute(&admin)
        .await
        .unwrap();
    let isolated_schema = schema.clone();
    let pool = PgPoolOptions::new()
        .max_connections(16)
        .after_connect(move |connection, _meta| {
            let statement = format!("SET search_path TO {isolated_schema}");
            Box::pin(async move {
                sqlx::query(&statement).execute(connection).await?;
                Ok(())
            })
        })
        .connect(&url)
        .await
        .unwrap();
    initialize_schema(&pool).await.unwrap();
    initialize_schema(&pool).await.unwrap();
    let (jwks_url, jwks_task) = local_jwks_server().await;
    let state = AppState {
        pool: pool.clone(),
        limiter: Arc::new(Mutex::new(RateLimiter {
            buckets: HashMap::new(),
            hasher: RandomState::new(),
            max_clients: 10_000,
            window: 60,
            limit: 1000,
        })),
        trust_proxy: false,
        verifier: auth::GoogleTokenVerifier::for_test(vec!["test-web-client".into()], jwks_url),
        backup_slots: Arc::new(tokio::sync::Semaphore::new(8)),
    };
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        axum::serve(
            listener,
            app(state).into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .unwrap();
    });
    let client = reqwest::Client::new();
    let base = format!("http://{addr}");
    assert_eq!(
        client
            .get(format!("{base}/healthz"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );

    // A complete built-in General profile can roundtrip; backups are isolated by verified sub.
    let profile = full_general_profile();
    let backup = serde_json::json!({"schema_version":1,"selection":{"settings":false,"profile_ids":["profile_general"],"images":false},"data":{"preferences":null,"profiles":[profile],"images":[]}});
    let token_a = account_token("sub-account-a", "test-web-client");
    let token_b = account_token("sub-account-b", "test-web-client");
    assert_eq!(
        client
            .put(format!("{base}/v1/account/backup"))
            .bearer_auth(&token_a)
            .json(&backup)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );
    assert_eq!(
        client
            .get(format!("{base}/v1/account/backup"))
            .bearer_auth(&token_b)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NOT_FOUND
    );
    let stored: serde_json::Value = client
        .get(format!("{base}/v1/account/backup"))
        .bearer_auth(&token_a)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(
        stored["backup"]["data"]["profiles"][0]["id"],
        "profile_general"
    );
    assert_eq!(
        stored["backup"]["data"]["profiles"][0]["buttons"][0]["action"]["value"],
        "MUTE"
    );
    assert_eq!(client.put(format!("{base}/v1/account/backup")).bearer_auth(&token_b).json(&serde_json::json!({"schema_version":1,"selection":{"settings":false,"profile_ids":["profile_general"],"images":false},"data":{"preferences":null,"profiles":[{"id":"profile_general","unexpected":true}],"images":[]}})).send().await.unwrap().status(), StatusCode::BAD_REQUEST);
    assert_eq!(
        client
            .get(format!("{base}/v1/account/backup"))
            .bearer_auth("forged")
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        client
            .get(format!("{base}/v1/account/backup"))
            .bearer_auth(account_token_expired("sub-account-a", "test-web-client"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        client
            .get(format!("{base}/v1/account/backup"))
            .bearer_auth(account_token("sub-account-a", "wrong-audience"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::UNAUTHORIZED
    );
    let huge = " ".repeat(account_backup::MAX_BACKUP_BODY + 1);
    assert_eq!(
        client
            .put(format!("{base}/v1/account/backup"))
            .bearer_auth(&token_a)
            .body(huge)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::PAYLOAD_TOO_LARGE
    );
    assert_eq!(
        client
            .delete(format!("{base}/v1/account/backup"))
            .bearer_auth(&token_a)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        client
            .delete(format!("{base}/v1/account/backup"))
            .bearer_auth(&token_a)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        client
            .get(format!("{base}/v1/account/backup"))
            .bearer_auth(&token_a)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        client
            .get(format!("{base}/v1/rankings?period=all"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );

    let unconfigured_state = AppState {
        pool: pool.clone(),
        limiter: Arc::new(Mutex::new(RateLimiter {
            buckets: HashMap::new(),
            hasher: RandomState::new(),
            max_clients: 100,
            window: 60,
            limit: 100,
        })),
        trust_proxy: false,
        verifier: auth::GoogleTokenVerifier::for_test(vec![], "http://127.0.0.1:1/unused".into()),
        backup_slots: Arc::new(tokio::sync::Semaphore::new(1)),
    };
    let no_auth_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let no_auth_addr = no_auth_listener.local_addr().unwrap();
    let no_auth_server = tokio::spawn(async move {
        axum::serve(no_auth_listener, app(unconfigured_state))
            .await
            .unwrap();
    });
    assert_eq!(
        client
            .get(format!("http://{no_auth_addr}/v1/account/backup"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::SERVICE_UNAVAILABLE
    );
    assert_eq!(
        client
            .get(format!("http://{no_auth_addr}/healthz"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );
    assert_eq!(
        client
            .get(format!("http://{no_auth_addr}/v1/rankings?period=all"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );
    assert_eq!(client.post(format!("http://{no_auth_addr}/v1/contributions")).json(&serde_json::json!({"schema_version":1,"batch_id":new_batch_id(),"delete_token":"d".repeat(64),"items":[{"shortcut_id":"undo","count":1}]})).send().await.unwrap().status(), StatusCode::CREATED);
    no_auth_server.abort();

    let batch = new_batch_id();
    let token = "c".repeat(64);
    let payload = serde_json::json!({"schema_version":1,"batch_id":batch,"delete_token":token,"items":[{"shortcut_id":"copy","count":7}]});
    let results = futures_for_concurrent_posts(&client, &base, payload.clone()).await;
    assert_eq!(
        results
            .iter()
            .filter(|s| **s == StatusCode::CREATED)
            .count(),
        1
    );
    assert_eq!(results.iter().filter(|s| **s == StatusCode::OK).count(), 7);
    let mut conflict = payload.clone();
    conflict["items"][0]["count"] = serde_json::json!(8);
    assert_eq!(
        client
            .post(format!("{base}/v1/contributions"))
            .json(&conflict)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::CONFLICT
    );

    let mut fresh_ids = Vec::new();
    for (index, (category, count)) in [("copy", 4), ("cut", 5), ("paste", 1)]
        .into_iter()
        .cycle()
        .take(8)
        .enumerate()
    {
        let id = new_batch_id();
        fresh_ids.push(id.clone());
        let body = serde_json::json!({"schema_version":1,"batch_id":id,"delete_token":format!("{:064x}", index + 1),"items":[{"shortcut_id":category,"count":count}]});
        let response = client
            .post(format!("{base}/v1/contributions"))
            .json(&body)
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::CREATED);
    }
    for _ in 0..3 {
        let id = new_batch_id();
        let received = now_seconds() - 40 * 86_400;
        let day = received.div_euclid(86_400);
        sqlx::query("INSERT INTO batches(batch_id, token_hash, payload_hash, received_at, received_day, withdrawn) VALUES($1,$2,$3,$4,$5,FALSE)")
            .bind(&id).bind(digest(b"test token")).bind(digest(b"test payload")).bind(received).bind(day).execute(&pool).await.unwrap();
        sqlx::query("INSERT INTO batch_items(batch_id, shortcut_id, count) VALUES($1,'italic',1)")
            .bind(id)
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("UPDATE shortcut_totals SET count=count+1, contributions=contributions+1 WHERE shortcut_id='italic'").execute(&pool).await.unwrap();
        sqlx::query("INSERT INTO shortcut_daily_totals(received_day,shortcut_id,count,contributions) VALUES($1,'italic',1,1) ON CONFLICT(received_day,shortcut_id) DO UPDATE SET count=shortcut_daily_totals.count+1, contributions=shortcut_daily_totals.contributions+1").bind(day).execute(&pool).await.unwrap();
    }
    let ranking: serde_json::Value = client
        .get(format!("{base}/v1/rankings?period=all"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let rows = ranking["rankings"].as_array().unwrap();
    assert_eq!(rows[0]["shortcut_id"], "copy");
    assert_eq!(rows[0]["count"], 19);
    assert_eq!(rows[0]["contributions"], 4);
    assert!(!rows.iter().any(|r| r["shortcut_id"] == "paste"));
    assert!(rows
        .iter()
        .all(|r| r["contributions"].as_i64().unwrap() >= 3));
    assert!(rows.iter().any(|r| r["shortcut_id"] == "italic"));
    let seven: serde_json::Value = client
        .get(format!("{base}/v1/rankings?period=7d"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(!seven["rankings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["shortcut_id"] == "italic"));
    assert_eq!(
        client
            .get(format!("{base}/v1/rankings?period=2d"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_REQUEST
    );

    let mut tagged_receipt: Option<(String, String)> = None;
    for index in 0..3 {
        let id = new_batch_id();
        let token = format!("{:064x}", 100 + index);
        if index == 0 {
            tagged_receipt = Some((id.clone(), token.clone()));
        }
        let body = serde_json::json!({"schema_version":1,"batch_id":id,"delete_token":token,"tag":"design","items":[{"shortcut_id":"save","count":4}]});
        assert_eq!(
            client
                .post(format!("{base}/v1/contributions"))
                .json(&body)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::CREATED
        );
    }
    let tagged: serde_json::Value = client
        .get(format!("{base}/v1/rankings?period=all&tag=design"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(tagged["tag"], "design");
    assert_eq!(tagged["rankings"][0]["shortcut_id"], "save");
    assert_eq!(tagged["rankings"][0]["count"], 12);
    let (tagged_id, tagged_token) = tagged_receipt.unwrap();
    assert_eq!(
        client
            .delete(format!("{base}/v1/contributions/{tagged_id}"))
            .bearer_auth(tagged_token)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NO_CONTENT
    );
    let below_threshold: serde_json::Value = client
        .get(format!("{base}/v1/rankings?period=all&tag=design"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(below_threshold["rankings"].as_array().unwrap().is_empty());
    let global_after_tag_delete: serde_json::Value = client
        .get(format!("{base}/v1/rankings?period=all"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(!global_after_tag_delete["rankings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["shortcut_id"] == "save"));
    assert_eq!(
        client
            .get(format!("{base}/v1/rankings?period=all&tag=unknown"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_REQUEST
    );

    let wrong = client
        .delete(format!("{base}/v1/contributions/{batch}"))
        .bearer_auth("d".repeat(64))
        .send()
        .await
        .unwrap();
    assert_eq!(wrong.status(), StatusCode::FORBIDDEN);
    let deleted = client
        .delete(format!("{base}/v1/contributions/{batch}"))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::NO_CONTENT);
    assert_eq!(
        client
            .delete(format!("{base}/v1/contributions/{batch}"))
            .bearer_auth(&token)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        client
            .post(format!("{base}/v1/contributions"))
            .json(&payload)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::GONE
    );
    let after_delete: serde_json::Value = client
        .get(format!("{base}/v1/rankings?period=all"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let copy = after_delete["rankings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["shortcut_id"] == "copy")
        .unwrap();
    assert_eq!(copy["count"], 12);
    assert_eq!(copy["contributions"], 3);
    server.abort();
    let _ = server.await;
    jwks_task.abort();
    pool.close().await;
    sqlx::query(&format!("DROP SCHEMA {schema} CASCADE"))
        .execute(&admin)
        .await
        .unwrap();
    admin.close().await;
    let _ = fresh_ids;
}

#[test]
fn full_general_fixture_deserializes_as_the_typed_backup_contract() {
    let value = serde_json::json!({"schema_version":1,"selection":{"settings":false,"profile_ids":["profile_general"],"images":false},"data":{"preferences":null,"profiles":[full_general_profile()],"images":[]}});
    let typed: account_backup::BackupEnvelope = serde_json::from_value(value).unwrap();
    // Keep the validator private to its module; the HTTP integration verifies its acceptance.
    drop(typed);
}

fn new_batch_id() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(1);
    format!(
        "{:032x}",
        now_seconds() as u64 * 1_000_000 + SEQ.fetch_add(1, Ordering::Relaxed)
    )
}

async fn futures_for_concurrent_posts(
    client: &reqwest::Client,
    base: &str,
    body: serde_json::Value,
) -> Vec<StatusCode> {
    let mut tasks = Vec::new();
    for _ in 0..8 {
        let client = client.clone();
        let url = format!("{base}/v1/contributions");
        let payload = body.clone();
        tasks.push(tokio::spawn(async move {
            client
                .post(url)
                .json(&payload)
                .send()
                .await
                .unwrap()
                .status()
        }));
    }
    let mut statuses = Vec::new();
    for task in tasks {
        statuses.push(task.await.unwrap());
    }
    statuses
}
