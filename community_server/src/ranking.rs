use super::{error, now_seconds, AppState};
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

#[derive(Deserialize)]
pub(super) struct PeriodQuery {
    period: String,
    tag: Option<String>,
}
#[derive(Serialize)]
struct RankingsResponse {
    schema_version: u8,
    period: String,
    tag: Option<String>,
    updated_at: String,
    rankings: Vec<Ranking>,
}
#[derive(Serialize)]
struct Ranking {
    shortcut_id: String,
    count: i64,
    contributions: i64,
}

pub async fn get(State(state): State<AppState>, Query(query): Query<PeriodQuery>) -> Response {
    let cutoff_day = match query.period.as_str() {
        "all" => None,
        "7d" => Some(now_seconds().div_euclid(86_400) - 6),
        "30d" => Some(now_seconds().div_euclid(86_400) - 29),
        _ => return error(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    if query
        .tag
        .as_deref()
        .is_some_and(|tag| !super::contributions::TAGS.contains(&tag))
    {
        return error(StatusCode::BAD_REQUEST, "invalid_request");
    }
    let result = if let (Some(tag), Some(day)) = (query.tag.as_deref(), cutoff_day) {
        sqlx::query_as::<_, (String, i64, i64)>("SELECT shortcut_id, SUM(count)::BIGINT, SUM(contributions)::BIGINT FROM shortcut_tag_daily_totals WHERE tag=$1 AND received_day >= $2 GROUP BY shortcut_id HAVING SUM(contributions) >= 3 ORDER BY SUM(count) DESC, shortcut_id ASC")
            .bind(tag).bind(day).fetch_all(&state.pool).await
    } else if let (Some(tag), None) = (query.tag.as_deref(), cutoff_day) {
        sqlx::query_as::<_, (String, i64, i64)>("SELECT shortcut_id,count,contributions FROM shortcut_tag_totals WHERE tag=$1 AND contributions >= 3 ORDER BY count DESC, shortcut_id ASC")
            .bind(tag).fetch_all(&state.pool).await
    } else if let Some(day) = cutoff_day {
        sqlx::query_as::<_, (String, i64, i64)>("SELECT shortcut_id, SUM(count)::BIGINT, SUM(contributions)::BIGINT FROM shortcut_daily_totals WHERE received_day >= $1 GROUP BY shortcut_id HAVING SUM(contributions) >= 3 ORDER BY SUM(count) DESC, shortcut_id ASC")
            .bind(day).fetch_all(&state.pool).await
    } else {
        sqlx::query_as::<_, (String, i64, i64)>("SELECT shortcut_id, count, contributions FROM shortcut_totals WHERE contributions >= 3 ORDER BY count DESC, shortcut_id ASC")
            .fetch_all(&state.pool).await
    };
    let rows = match result {
        Ok(rows) => rows,
        Err(_) => return error(StatusCode::INTERNAL_SERVER_ERROR, "server_error"),
    };
    let rankings = rows
        .into_iter()
        .map(|(shortcut_id, count, contributions)| Ranking {
            shortcut_id,
            count,
            contributions,
        })
        .collect();
    let updated_at = match OffsetDateTime::now_utc().format(&Rfc3339) {
        Ok(t) => t,
        Err(_) => return error(StatusCode::INTERNAL_SERVER_ERROR, "server_error"),
    };
    (
        StatusCode::OK,
        Json(RankingsResponse {
            schema_version: 1,
            period: query.period,
            tag: query.tag,
            updated_at,
            rankings,
        }),
    )
        .into_response()
}
