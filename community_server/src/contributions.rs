use super::{digest, error, lower_hex, now_seconds, AppState};
use axum::{
    body::Bytes,
    extract::{Path, State},
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

pub(super) const MAX_BODY: usize = 16_384;
const MAX_TOTAL: u64 = 100_000;
pub(super) const ALLOWED: [&str; 15] = [
    "copy",
    "paste",
    "cut",
    "undo",
    "redo",
    "select_all",
    "save",
    "find",
    "new",
    "open",
    "print",
    "new_tab",
    "close_tab",
    "bold",
    "italic",
];
pub(super) const TAGS: [&str; 5] = [
    "software_engineering",
    "design",
    "video_editing",
    "office",
    "other",
];
pub(super) const EXPERIENCES: [&str; 3] = ["beginner", "intermediate", "advanced"];

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct ContributionRequest {
    pub(super) schema_version: u8,
    pub(super) batch_id: String,
    pub(super) delete_token: String,
    #[serde(default)]
    pub(super) tag: Option<String>,
    #[serde(default)]
    pub(super) experience: Option<String>,
    pub(super) items: Vec<Item>,
}
#[derive(Deserialize, Serialize, Clone)]
#[serde(deny_unknown_fields)]
pub(super) struct Item {
    pub(super) shortcut_id: String,
    pub(super) count: u64,
}
#[derive(Serialize)]
struct Accepted {
    schema_version: u8,
    batch_id: String,
    status: &'static str,
}

pub(super) fn validate(
    mut body: ContributionRequest,
) -> Result<(ContributionRequest, Vec<u8>, Vec<u8>), ()> {
    if body.schema_version != 1
        || !lower_hex(&body.batch_id, 32)
        || !lower_hex(&body.delete_token, 64)
        || !(1..=15).contains(&body.items.len())
    {
        return Err(());
    }
    if body.tag.as_deref().is_some_and(|tag| !TAGS.contains(&tag)) {
        return Err(());
    }
    if body
        .experience
        .as_deref()
        .is_some_and(|value| !EXPERIENCES.contains(&value))
    {
        return Err(());
    }
    let mut seen = HashSet::new();
    let mut total = 0u64;
    for item in &body.items {
        if !ALLOWED.contains(&item.shortcut_id.as_str())
            || !seen.insert(item.shortcut_id.as_str())
            || item.count == 0
        {
            return Err(());
        }
        total = total.checked_add(item.count).ok_or(())?;
        if total > MAX_TOTAL {
            return Err(());
        }
    }
    body.items.sort_by(|a, b| a.shortcut_id.cmp(&b.shortcut_id));
    let canonical = if let Some(experience) = &body.experience {
        serde_json::to_vec(&(
            body.schema_version,
            &body.batch_id,
            &body.tag,
            Some(experience),
            &body.items,
        ))
    } else {
        // Preserve the exact pre-experience tuple so previously queued batches retry unchanged.
        serde_json::to_vec(&(body.schema_version, &body.batch_id, &body.tag, &body.items))
    }
    .map_err(|_| ())?;
    let token_hash = digest(body.delete_token.as_bytes());
    let payload_hash = digest(&canonical);
    Ok((body, token_hash, payload_hash))
}

pub async fn post(State(state): State<AppState>, body: Bytes) -> Response {
    if body.len() > MAX_BODY {
        return error(StatusCode::PAYLOAD_TOO_LARGE, "payload_too_large");
    }
    let parsed: ContributionRequest = match serde_json::from_slice(&body) {
        Ok(v) => v,
        Err(_) => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    let (body, token_hash, payload_hash) = match validate(parsed) {
        Ok(v) => v,
        Err(_) => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    let received_at = now_seconds();
    let received_day = received_at.div_euclid(86_400);
    let item_map = body
        .items
        .iter()
        .map(|item| {
            (
                item.shortcut_id.clone(),
                serde_json::Value::from(item.count),
            )
        })
        .collect::<serde_json::Map<_, _>>();
    let result =
        sqlx::query_scalar::<_, String>("SELECT submit_community_batch($1,$2,$3,$4,$5,$6,$7,$8)")
            .bind(&body.batch_id)
            .bind(&token_hash)
            .bind(&payload_hash)
            .bind(received_at)
            .bind(received_day)
            .bind(&body.tag)
            .bind(&body.experience)
            .bind(sqlx::types::Json(serde_json::Value::Object(item_map)))
            .fetch_one(&state.pool)
            .await;
    let result = match result {
        Ok(status) => status,
        Err(_) => return error(StatusCode::INTERNAL_SERVER_ERROR, "server_error"),
    };
    match result.as_str() {
        "created" | "duplicate" => {
            let http_status = if result == "created" {
                StatusCode::CREATED
            } else {
                StatusCode::OK
            };
            (
                http_status,
                Json(Accepted {
                    schema_version: 1,
                    batch_id: body.batch_id,
                    status: "accepted",
                }),
            )
                .into_response()
        }
        "withdrawn" => error(StatusCode::GONE, "withdrawn"),
        "conflict" => error(StatusCode::CONFLICT, "batch_conflict"),
        _ => error(StatusCode::INTERNAL_SERVER_ERROR, "server_error"),
    }
}

pub async fn delete(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(batch_id): Path<String>,
) -> Response {
    if !lower_hex(&batch_id, 32) {
        return error(StatusCode::NOT_FOUND, "not_found");
    }
    let token = match headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
    {
        Some(v) if lower_hex(v, 64) => v,
        _ => return error(StatusCode::UNAUTHORIZED, "unauthorized"),
    };
    let token_hash = digest(token.as_bytes());
    let result = sqlx::query_scalar::<_, String>("SELECT withdraw_community_batch($1,$2)")
        .bind(&batch_id)
        .bind(&token_hash)
        .fetch_one(&state.pool)
        .await;
    match result {
        Ok(status) if status == "withdrawn" || status == "already_withdrawn" => {
            StatusCode::NO_CONTENT.into_response()
        }
        Ok(status) if status == "forbidden" => error(StatusCode::FORBIDDEN, "forbidden"),
        Ok(status) if status == "not_found" => error(StatusCode::NOT_FOUND, "not_found"),
        _ => error(StatusCode::INTERNAL_SERVER_ERROR, "server_error"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validation_rejects_bad_allowlist_duplicates_totals_and_fields() {
        let base = r#"{"schema_version":1,"batch_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","delete_token":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","items":[{"shortcut_id":"copy","count":1}]}"#;
        let value: ContributionRequest = serde_json::from_str(base).unwrap();
        assert!(validate(value).is_ok());
        let duplicate = base.replace("\"items\":[{\"shortcut_id\":\"copy\",\"count\":1}]", "\"items\":[{\"shortcut_id\":\"copy\",\"count\":1},{\"shortcut_id\":\"copy\",\"count\":1}]");
        assert!(serde_json::from_str::<ContributionRequest>(&duplicate)
            .map_err(|_| ())
            .and_then(validate)
            .is_err());
        assert!(serde_json::from_str::<ContributionRequest>(
            &base.replace("\"count\":1", "\"count\":true")
        )
        .is_err());
        assert!(serde_json::from_str::<ContributionRequest>(
            &base.replace("\"copy\"", "\"private\"")
        )
        .map_err(|_| ())
        .and_then(validate)
        .is_err());
        assert!(serde_json::from_str::<ContributionRequest>(&base.replace(
            "\"schema_version\":1",
            "\"schema_version\":1,\"extra\":true"
        ))
        .is_err());
    }

    #[test]
    fn tag_is_optional_allowlisted_and_bound_into_idempotency_hash() {
        let base = r#"{"schema_version":1,"batch_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","delete_token":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","items":[{"shortcut_id":"copy","count":1}]}"#;
        let request: ContributionRequest = serde_json::from_str(base).unwrap();
        let (_, _, untagged_hash) = validate(request).unwrap();
        let explicit_null = base.replace("\"items\"", "\"tag\":null,\"items\"");
        let (_, _, explicit_null_hash) =
            validate(serde_json::from_str(&explicit_null).unwrap()).unwrap();
        assert_eq!(untagged_hash, explicit_null_hash);
        let tagged = base.replace("\"items\"", "\"tag\":\"design\",\"items\"");
        let (_, _, tagged_hash) = validate(serde_json::from_str(&tagged).unwrap()).unwrap();
        assert_ne!(untagged_hash, tagged_hash);
        let unknown = base.replace("\"items\"", "\"tag\":\"designer\",\"items\"");
        assert!(serde_json::from_str::<ContributionRequest>(&unknown)
            .map_err(|_| ())
            .and_then(validate)
            .is_err());
    }

    #[test]
    fn experience_is_optional_allowlisted_and_absence_preserves_legacy_hash() {
        let base = r#"{"schema_version":1,"batch_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","delete_token":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","items":[{"shortcut_id":"copy","count":1}]}"#;
        let (_, _, legacy_hash) = validate(serde_json::from_str(base).unwrap()).unwrap();
        let canonical_items = vec![Item {
            shortcut_id: "copy".into(),
            count: 1,
        }];
        let expected = digest(
            &serde_json::to_vec(&(
                1u8,
                &"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                &None::<String>,
                &canonical_items,
            ))
            .unwrap(),
        );
        assert_eq!(legacy_hash, expected);
        let explicit_null = base.replace("\"items\"", "\"experience\":null,\"items\"");
        let (_, _, null_hash) = validate(serde_json::from_str(&explicit_null).unwrap()).unwrap();
        assert_eq!(legacy_hash, null_hash);
        let experienced = base.replace("\"items\"", "\"experience\":\"beginner\",\"items\"");
        let (_, _, experienced_hash) =
            validate(serde_json::from_str(&experienced).unwrap()).unwrap();
        assert_ne!(legacy_hash, experienced_hash);
        let invalid = base.replace("\"items\"", "\"experience\":\"expert\",\"items\"");
        assert!(serde_json::from_str::<ContributionRequest>(&invalid)
            .map_err(|_| ())
            .and_then(validate)
            .is_err());
    }
}
