use axum::{
    body::Body,
    http::{header, HeaderValue, Response, StatusCode},
};

const CSP: &str = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'";

pub async fn index() -> Response<Body> {
    response(
        include_str!("web/index.html"),
        "text/html; charset=utf-8",
        "no-cache",
    )
}

pub async fn css() -> Response<Body> {
    response(
        include_str!("web/dashboard.css"),
        "text/css; charset=utf-8",
        "public, max-age=3600",
    )
}

pub async fn js() -> Response<Body> {
    response(
        include_str!("web/dashboard.js"),
        "text/javascript; charset=utf-8",
        "public, max-age=3600",
    )
}

fn response(
    content: &'static str,
    content_type: &'static str,
    cache_control: &'static str,
) -> Response<Body> {
    let mut response = Response::new(Body::from(content));
    *response.status_mut() = StatusCode::OK;
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static(content_type));
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static(cache_control),
    );
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        header::REFERRER_POLICY,
        HeaderValue::from_static("no-referrer"),
    );
    headers.insert(
        header::CONTENT_SECURITY_POLICY,
        HeaderValue::from_static(CSP),
    );
    headers.insert("x-frame-options", HeaderValue::from_static("DENY"));
    headers.insert(
        "permissions-policy",
        HeaderValue::from_static("camera=(), microphone=(), geolocation=()"),
    );
    response
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn assets_have_content_types_security_headers_and_cache_policy() {
        let page = index().await;
        assert_eq!(
            page.headers()[header::CONTENT_TYPE],
            "text/html; charset=utf-8"
        );
        assert_eq!(page.headers()[header::CONTENT_SECURITY_POLICY], CSP);
        assert_eq!(page.headers()[header::CACHE_CONTROL], "no-cache");
        let style = css().await;
        assert_eq!(
            style.headers()[header::CONTENT_TYPE],
            "text/css; charset=utf-8"
        );
        assert_eq!(
            style.headers()[header::CACHE_CONTROL],
            "public, max-age=3600"
        );
        assert_eq!(
            js().await.headers()[header::CONTENT_TYPE],
            "text/javascript; charset=utf-8"
        );
    }
}
