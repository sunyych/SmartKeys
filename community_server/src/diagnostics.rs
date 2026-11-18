//! Strict fixed-code errors. No raw text, identity, request metadata or public reads.
use crate::{error, now_seconds, AppState};
use axum::{
    extract::{rejection::JsonRejection, State},
    http::StatusCode,
    response::Response,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use std::{collections::HashSet, time::Duration};

pub const MAX_BODY: usize = 16 * 1024;
const RETENTION_MS: i64 = 30 * 86400 * 1000;
const MAX_ROWS: i64 = 100000;
const LOCK_KEY: i64 = 0x4c554d4941444941;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Code {
    ConnectionUnavailable,
    ConnectionTimeout,
    ConnectionAuthenticationFailed,
    ConnectionProtocolInvalid,
    ApplicationActivationFailed,
    ShortcutDeliveryFailed,
    PointerDeliveryFailed,
    IconDownloadFailed,
    IconDataInvalid,
    ConfigurationLoadFailed,
    ConfigurationInvalid,
    ConfigurationSaveFailed,
    StorageReadFailed,
    StorageWriteFailed,
    BluetoothUnavailable,
    BluetoothPermissionDenied,
    BluetoothConnectionFailed,
    BluetoothInputFailed,
    PlatformUnavailable,
    RuntimeFailure,
}
impl Code {
    fn wire(&self) -> String {
        serde_json::to_value(self)
            .unwrap()
            .as_str()
            .unwrap()
            .to_owned()
    }
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Edition {
    Full,
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Platform {
    Android,
    Ios,
}
impl Platform {
    fn wire(&self) -> &'static str {
        match self {
            Self::Android => "android",
            Self::Ios => "ios",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Event {
    id: String,
    occurred_at_ms: i64,
    last_occurred_at_ms: i64,
    app_version: String,
    app_build: i32,
    edition: Edition,
    platform: Platform,
    code: Code,
    repeat_count: i32,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Batch {
    schema_version: u8,
    events: Vec<Event>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Accepted {
    accepted_ids: Vec<String>,
}

fn valid_uuid(id: &str) -> bool {
    id.len() == 36
        && id.bytes().enumerate().all(|(i, b)| {
            if matches!(i, 8 | 13 | 18 | 23) {
                b == b'-'
            } else if i == 14 {
                b == b'4'
            } else if i == 19 {
                matches!(b, b'8' | b'9' | b'a' | b'b')
            } else {
                b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
            }
        })
}
fn valid_version(version: &str) -> bool {
    let parts: Vec<_> = version.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.len() <= 3 && p.bytes().all(|b| b.is_ascii_digit()))
}
fn validate(batch: &Batch, now: i64) -> bool {
    if batch.schema_version != 1 || batch.events.is_empty() || batch.events.len() > 20 {
        return false;
    }
    let mut ids = HashSet::new();
    batch.events.iter().all(|event| {
        valid_uuid(&event.id)
            && ids.insert(&event.id)
            && valid_version(&event.app_version)
            && (0..=1000000000).contains(&event.app_build)
            && event.occurred_at_ms >= now - RETENTION_MS
            && event.last_occurred_at_ms >= event.occurred_at_ms
            && event.last_occurred_at_ms <= now + 300000
            && (1..=1000000).contains(&event.repeat_count)
    })
}
#[derive(Debug, PartialEq)]
enum StoreError {
    Conflict,
    Unavailable,
}
async fn store(pool: &PgPool, events: &[Event], now: i64, max_rows: i64) -> Result<(), StoreError> {
    let mut tx = pool.begin().await.map_err(|_| StoreError::Unavailable)?;
    sqlx::query("SELECT pg_advisory_xact_lock($1)")
        .bind(LOCK_KEY)
        .execute(&mut *tx)
        .await
        .map_err(|_| StoreError::Unavailable)?;
    sqlx::query("DELETE FROM diagnostic_errors WHERE last_occurred_at_ms < $1")
        .bind(now - RETENTION_MS)
        .execute(&mut *tx)
        .await
        .map_err(|_| StoreError::Unavailable)?;
    for event in events {
        let code = event.code.wire();
        let previous=sqlx::query("SELECT occurred_at_ms, app_version, app_build, platform, code FROM diagnostic_errors WHERE event_id=$1 FOR UPDATE")
            .bind(&event.id).fetch_optional(&mut *tx).await.map_err(|_|StoreError::Unavailable)?;
        if let Some(row) = previous {
            if row.get::<i64, _>("occurred_at_ms") != event.occurred_at_ms
                || row.get::<String, _>("app_version") != event.app_version
                || row.get::<i32, _>("app_build") != event.app_build
                || row.get::<String, _>("platform") != event.platform.wire()
                || row.get::<String, _>("code") != code
            {
                return Err(StoreError::Conflict);
            }
        }
        sqlx::query("INSERT INTO diagnostic_errors(event_id,occurred_at_ms,last_occurred_at_ms,app_version,app_build,edition,platform,code,repeat_count) VALUES($1,$2,$3,$4,$5,'full',$6,$7,$8) ON CONFLICT(event_id) DO UPDATE SET last_occurred_at_ms=GREATEST(diagnostic_errors.last_occurred_at_ms,EXCLUDED.last_occurred_at_ms),repeat_count=GREATEST(diagnostic_errors.repeat_count,EXCLUDED.repeat_count)")
            .bind(&event.id).bind(event.occurred_at_ms).bind(event.last_occurred_at_ms).bind(&event.app_version).bind(event.app_build)
            .bind(event.platform.wire()).bind(code).bind(event.repeat_count).execute(&mut *tx).await.map_err(|_|StoreError::Unavailable)?;
    }
    sqlx::query("DELETE FROM diagnostic_errors WHERE event_id IN (SELECT event_id FROM diagnostic_errors ORDER BY last_occurred_at_ms DESC,event_id DESC OFFSET $1)")
        .bind(max_rows).execute(&mut *tx).await.map_err(|_|StoreError::Unavailable)?;
    tx.commit().await.map_err(|_| StoreError::Unavailable)
}

pub async fn post(
    State(state): State<AppState>,
    body: Result<Json<Batch>, JsonRejection>,
) -> Response {
    let batch = match body {
        Ok(Json(batch)) => batch,
        Err(rejection) => {
            return error(
                if rejection.status() == StatusCode::PAYLOAD_TOO_LARGE {
                    StatusCode::PAYLOAD_TOO_LARGE
                } else {
                    StatusCode::BAD_REQUEST
                },
                "invalid_diagnostics",
            )
        }
    };
    let now = now_seconds() * 1000;
    if !validate(&batch, now) {
        return error(StatusCode::BAD_REQUEST, "invalid_diagnostics");
    }
    match store(&state.pool, &batch.events, now, MAX_ROWS).await {
        Ok(()) => {
            use axum::response::IntoResponse;
            Json(Accepted {
                accepted_ids: batch.events.into_iter().map(|event| event.id).collect(),
            })
            .into_response()
        }
        Err(StoreError::Conflict) => error(StatusCode::CONFLICT, "diagnostic_id_conflict"),
        Err(StoreError::Unavailable) => {
            error(StatusCode::SERVICE_UNAVAILABLE, "diagnostics_unavailable")
        }
    }
}

/// Bounded retention also runs when there are no new uploads; no payload logging.
pub fn start_retention(pool: PgPool) {
    tokio::spawn(async move {
        let mut timer = tokio::time::interval(Duration::from_secs(3600));
        loop {
            timer.tick().await;
            let _ = store(&pool, &[], now_seconds() * 1000, MAX_ROWS).await;
        }
    });
}

#[cfg(test)]
mod tests;
