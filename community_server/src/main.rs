use axum::{
    extract::ConnectInfo,
    http::{Request, StatusCode},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{delete, get, post, put},
    Json, Router,
};
use serde::Serialize;
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::{
    collections::HashMap,
    env,
    hash::{BuildHasher, RandomState},
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::net::TcpListener;

mod account_backup;
mod auth;
mod contributions;
mod ranking;
mod web;

#[derive(Clone)]
struct AppState {
    pool: PgPool,
    limiter: Arc<Mutex<RateLimiter>>,
    trust_proxy: bool,
    verifier: auth::GoogleTokenVerifier,
    backup_slots: Arc<tokio::sync::Semaphore>,
}

struct RateLimiter {
    buckets: HashMap<u64, (u32, u64)>,
    hasher: RandomState,
    max_clients: usize,
    window: u64,
    limit: u32,
}
impl RateLimiter {
    fn client_key(&self, client: &str) -> u64 {
        self.hasher.hash_one(client)
    }
    fn allow(&mut self, key: u64, now: u64) -> bool {
        if self.buckets.len() >= self.max_clients && !self.buckets.contains_key(&key) {
            self.buckets
                .retain(|_, (_, start)| now.saturating_sub(*start) < self.window);
            if self.buckets.len() >= self.max_clients {
                return false;
            }
        }
        let entry = self.buckets.entry(key).or_insert((0, now));
        if now.saturating_sub(entry.1) >= self.window {
            *entry = (0, now);
        }
        if entry.0 >= self.limit {
            return false;
        }
        entry.0 += 1;
        true
    }
}

#[derive(Serialize)]
struct ErrorBody {
    error: &'static str,
}

fn error(status: StatusCode, code: &'static str) -> Response {
    (status, Json(ErrorBody { error: code })).into_response()
}
fn now_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
fn lower_hex(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn digest(input: &[u8]) -> Vec<u8> {
    use sha2::{Digest, Sha256};
    Sha256::digest(input).to_vec()
}
async fn rate_limit(
    axum::extract::State(state): axum::extract::State<AppState>,
    request: Request<axum::body::Body>,
    next: Next,
) -> Response {
    let remote = request
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|c| c.0.ip().to_string())
        .unwrap_or_else(|| "unresolved".to_owned());
    let client = if state.trust_proxy {
        request
            .headers()
            .get("x-forwarded-for")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.split(',').next_back())
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .unwrap_or(&remote)
    } else {
        &remote
    };
    let allowed = state
        .limiter
        .lock()
        .map(|mut l| {
            let key = l.client_key(client);
            l.allow(key, now_seconds() as u64)
        })
        .unwrap_or(false);
    if !allowed {
        return error(StatusCode::TOO_MANY_REQUESTS, "rate_limited");
    }
    next.run(request).await
}

async fn health() -> impl IntoResponse {
    (StatusCode::OK, Json(serde_json::json!({"status":"ok"})))
}

async fn open_pool(url: &str) -> Result<PgPool, sqlx::Error> {
    let pool = PgPoolOptions::new()
        .max_connections(16)
        .connect(url)
        .await?;
    initialize_schema(&pool).await?;
    Ok(pool)
}

async fn initialize_schema(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::raw_sql(include_str!("../migrations/001_init.sql"))
        .execute(pool)
        .await?;
    sqlx::raw_sql(include_str!("../migrations/002_experience.sql"))
        .execute(pool)
        .await?;
    Ok(())
}

fn app(state: AppState) -> Router {
    let account_routes = Router::new()
        .route(
            "/backup",
            put(account_backup::put)
                .get(account_backup::get)
                .delete(account_backup::delete),
        )
        .layer(axum::extract::DefaultBodyLimit::max(
            account_backup::MAX_BACKUP_BODY,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            account_backup::guard,
        ))
        .with_state(state.clone());
    Router::new()
        .route("/", get(web::index))
        .route("/dashboard", get(web::index))
        .route("/assets/dashboard.css", get(web::css))
        .route("/assets/dashboard.js", get(web::js))
        .route("/healthz", get(health))
        .route(
            "/v1/contributions",
            post(contributions::post).layer(axum::extract::DefaultBodyLimit::max(
                contributions::MAX_BODY,
            )),
        )
        .route("/v1/contributions/:batch_id", delete(contributions::delete))
        .route("/v1/rankings", get(ranking::get))
        .nest("/v1/account", account_routes)
        .layer(middleware::from_fn_with_state(state.clone(), rate_limit))
        .with_state(state)
}

fn env_limit(name: &str, default: u32, max: u32) -> u32 {
    env::var(name)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
        .clamp(1, max)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is required")?;
    let pool = open_pool(&database_url).await?;
    let trust_proxy = env::var("TRUST_PROXY").map(|v| v == "1").unwrap_or(false);
    let state = AppState {
        pool,
        limiter: Arc::new(Mutex::new(RateLimiter {
            buckets: HashMap::new(),
            hasher: RandomState::new(),
            max_clients: env_limit("RATE_LIMIT_MAX_CLIENTS", 10_000, 100_000) as usize,
            window: 60,
            limit: env_limit("RATE_LIMIT_PER_MINUTE", 120, 1_000_000),
        })),
        trust_proxy,
        verifier: auth::GoogleTokenVerifier::from_env(),
        backup_slots: Arc::new(tokio::sync::Semaphore::new(8)),
    };
    let addr: SocketAddr = env::var("LISTEN_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8080".into())
        .parse()?;
    let listener = TcpListener::bind(addr).await?;
    axum::serve(
        listener,
        app(state).into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(async {
        let _ = tokio::signal::ctrl_c().await;
    })
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests;
