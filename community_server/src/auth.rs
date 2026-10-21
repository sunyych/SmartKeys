use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use std::{
    collections::HashMap,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::sync::{Mutex, RwLock};

const GOOGLE_JWKS_URL: &str = "https://www.googleapis.com/oauth2/v3/certs";
const MAX_JWKS_BYTES: usize = 256 * 1024;

#[derive(Debug)]
pub enum VerifyError {
    NotConfigured,
    Invalid,
    Unavailable,
}

#[derive(Clone)]
pub struct GoogleTokenVerifier {
    client_ids: Vec<String>,
    client: reqwest::Client,
    jwks_url: String,
    cache: std::sync::Arc<RwLock<KeyCache>>,
    refresh_lock: std::sync::Arc<Mutex<()>>,
}

struct KeyCache {
    keys: HashMap<String, (String, String)>,
    expires_at: Instant,
    refresh_after: Instant,
}

#[derive(Deserialize)]
struct JwkSet {
    keys: Vec<Jwk>,
}
#[derive(Deserialize)]
struct Jwk {
    kid: String,
    kty: String,
    alg: Option<String>,
    #[serde(rename = "use")]
    use_: Option<String>,
    n: String,
    e: String,
}

#[derive(Deserialize)]
struct GoogleClaims {
    sub: String,
    iss: String,
    aud: serde_json::Value,
    exp: u64,
}

impl GoogleTokenVerifier {
    pub fn from_env() -> Self {
        let client_ids = std::env::var("GOOGLE_CLIENT_IDS")
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|id| !id.is_empty())
            .map(str::to_owned)
            .collect();
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(4))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("static Google JWKS HTTP client configuration");
        Self::new(client_ids, client, GOOGLE_JWKS_URL.to_owned())
    }

    fn new(client_ids: Vec<String>, client: reqwest::Client, jwks_url: String) -> Self {
        Self {
            client_ids,
            client,
            jwks_url,
            cache: std::sync::Arc::new(RwLock::new(KeyCache {
                keys: HashMap::new(),
                expires_at: Instant::now(),
                refresh_after: Instant::now() - Duration::from_secs(1),
            })),
            refresh_lock: std::sync::Arc::new(Mutex::new(())),
        }
    }

    #[cfg(test)]
    pub fn for_test(client_ids: Vec<String>, jwks_url: String) -> Self {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(1))
            .redirect(reqwest::redirect::Policy::none())
            .no_proxy()
            .build()
            .unwrap();
        Self::new(client_ids, client, jwks_url)
    }

    pub fn is_configured(&self) -> bool {
        !self.client_ids.is_empty()
    }

    pub async fn verified_subject(&self, token: &str) -> Result<String, VerifyError> {
        if !self.is_configured() {
            return Err(VerifyError::NotConfigured);
        }
        if token.is_empty() || token.len() > 16_384 {
            return Err(VerifyError::Invalid);
        }
        let header = decode_header(token).map_err(|_| VerifyError::Invalid)?;
        if header.alg != Algorithm::RS256 {
            return Err(VerifyError::Invalid);
        }
        let kid = header.kid.ok_or(VerifyError::Invalid)?;
        let (modulus, exponent) = self.get_key(&kid).await?;
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_issuer(&["accounts.google.com", "https://accounts.google.com"]);
        validation.set_audience(&self.client_ids);
        validation.required_spec_claims = ["exp", "iss", "aud", "sub"]
            .into_iter()
            .map(str::to_owned)
            .collect();
        validation.leeway = 0;
        let claims = decode::<GoogleClaims>(
            token,
            &DecodingKey::from_rsa_components(&modulus, &exponent)
                .map_err(|_| VerifyError::Invalid)?,
            &validation,
        )
        .map_err(|_| VerifyError::Invalid)?
        .claims;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        if claims.sub.is_empty()
            || claims.sub.len() > 255
            || claims.iss != "accounts.google.com" && claims.iss != "https://accounts.google.com"
            || claims.exp <= now
            || !audience_allowed(&claims.aud, &self.client_ids)
        {
            return Err(VerifyError::Invalid);
        }
        Ok(claims.sub)
    }

    async fn get_key(&self, kid: &str) -> Result<(String, String), VerifyError> {
        {
            let cache = self.cache.read().await;
            if Instant::now() < cache.expires_at {
                if let Some(key) = cache.keys.get(kid) {
                    return Ok(key.clone());
                }
                if Instant::now() < cache.refresh_after {
                    return Err(VerifyError::Invalid);
                }
            } else if Instant::now() < cache.refresh_after {
                return Err(VerifyError::Unavailable);
            }
        }
        let _refresh = self.refresh_lock.lock().await;
        {
            let cache = self.cache.read().await;
            if Instant::now() < cache.expires_at {
                if let Some(key) = cache.keys.get(kid) {
                    return Ok(key.clone());
                }
            }
            if Instant::now() < cache.refresh_after {
                return Err(if Instant::now() < cache.expires_at {
                    VerifyError::Invalid
                } else {
                    VerifyError::Unavailable
                });
            }
        }
        {
            let mut cache = self.cache.write().await;
            cache.refresh_after = Instant::now() + Duration::from_secs(30);
        }
        let response = self
            .client
            .get(&self.jwks_url)
            .send()
            .await
            .map_err(|_| VerifyError::Unavailable)?;
        if !response.status().is_success()
            || response
                .content_length()
                .is_some_and(|n| n > MAX_JWKS_BYTES as u64)
        {
            return Err(VerifyError::Unavailable);
        }
        let cache_control = response
            .headers()
            .get(reqwest::header::CACHE_CONTROL)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_owned();
        let mut bytes = Vec::new();
        let mut response = response;
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|_| VerifyError::Unavailable)?
        {
            if bytes.len() + chunk.len() > MAX_JWKS_BYTES {
                return Err(VerifyError::Unavailable);
            }
            bytes.extend_from_slice(&chunk);
        }
        let set: JwkSet = serde_json::from_slice(&bytes).map_err(|_| VerifyError::Unavailable)?;
        let keys = set
            .keys
            .into_iter()
            .filter(|k| {
                k.kty == "RSA"
                    && k.alg.as_deref().is_none_or(|a| a == "RS256")
                    && k.use_.as_deref().is_none_or(|u| u == "sig")
            })
            .map(|k| (k.kid, (k.n, k.e)))
            .collect::<HashMap<_, _>>();
        let ttl = cache_control
            .split(',')
            .map(str::trim)
            .find_map(|item| {
                item.strip_prefix("max-age=")
                    .and_then(|v| v.parse::<u64>().ok())
            })
            .unwrap_or(300)
            .clamp(60, 21_600);
        let mut cache = self.cache.write().await;
        cache.keys = keys;
        cache.expires_at = Instant::now() + Duration::from_secs(ttl);
        let key = cache.keys.get(kid).cloned();
        cache.refresh_after = if key.is_some() {
            Instant::now()
        } else {
            Instant::now() + Duration::from_secs(30)
        };
        key.ok_or(VerifyError::Invalid)
    }
}

fn audience_allowed(aud: &serde_json::Value, allowlist: &[String]) -> bool {
    match aud {
        serde_json::Value::String(value) => allowlist.iter().any(|id| id == value),
        serde_json::Value::Array(values) => values.iter().any(|v| {
            v.as_str()
                .is_some_and(|s| allowlist.iter().any(|id| id == s))
        }),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use jsonwebtoken::{encode, EncodingKey, Header};
    use serde::Serialize;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    };

    const MODULUS: &str = "rgMkuKRWIAbKu6Bd6yXVHs_54hHeplayUQykGNUbCQMjGL5x4idluZN_CsPjK4qFZEoobBRrsGQE0iiOQgH02coFIky64ZJrx-IM-Xu0YTbljrLvxXSyNaJ3hGqqYqKNukYTITHLo5FIvZnS5IftfjdNRMX3hoJND_jgkg-wqTNVsDyUuguGLT7nqEs5-nE-U5xIiN29X6NsRjag6zmHYFvadyR4L_H-nixEXT8KPz4qYT1lYzzbTlcgaKXzdxSogJ2_QxUFIsJyWkTUsTI6_fA0E5tg-gEaBbUqoPiYnxnjHUpvDSBuU4UCVRKLUKx8YLUWC5XDdNWYq24sznJpCw";

    #[derive(Serialize)]
    struct Claims {
        iss: String,
        aud: String,
        sub: String,
        exp: u64,
    }

    fn signed_token(kid: &str, subject: &str, audience: &str, expires: u64) -> String {
        let mut header = Header::new(Algorithm::RS256);
        header.kid = Some(kid.to_owned());
        encode(
            &header,
            &Claims {
                iss: "https://accounts.google.com".into(),
                aud: audience.into(),
                sub: subject.into(),
                exp: expires,
            },
            &EncodingKey::from_rsa_pem(include_bytes!("../tests/fixtures/test-rsa-private.pem"))
                .unwrap(),
        )
        .unwrap()
    }

    async fn jwks_server(
        status: u16,
        body: String,
    ) -> (String, Arc<AtomicUsize>, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/jwks", listener.local_addr().unwrap());
        let hits = Arc::new(AtomicUsize::new(0));
        let counter = hits.clone();
        let task = tokio::spawn(async move {
            while let Ok((mut stream, _)) = listener.accept().await {
                counter.fetch_add(1, Ordering::SeqCst);
                let mut request = [0u8; 2048];
                let _ = stream.read(&mut request).await;
                let response = format!("HTTP/1.1 {status} Test\r\nContent-Type: application/json\r\nCache-Control: public, max-age=60\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
                let _ = stream.write_all(response.as_bytes()).await;
            }
        });
        (url, hits, task)
    }

    fn fixture_jwks(kid: &str) -> String {
        serde_json::json!({"keys":[{"kid":kid,"kty":"RSA","alg":"RS256","use":"sig","n":MODULUS,"e":"AQAB"}]}).to_string()
    }

    #[tokio::test]
    async fn verifies_signed_tokens_and_rejects_expiry_audience_forgery_and_unknown_kids() {
        let (url, hits, server) = jwks_server(200, fixture_jwks("fixture-key")).await;
        let verifier = GoogleTokenVerifier::for_test(vec!["web-client-id".into()], url);
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let verified = verifier
            .verified_subject(&signed_token(
                "fixture-key",
                "account-1",
                "web-client-id",
                now + 300,
            ))
            .await;
        assert_eq!(
            hits.load(Ordering::SeqCst),
            1,
            "JWKS request should be made before verification: {verified:?}"
        );
        assert_eq!(verified.unwrap(), "account-1");
        assert!(matches!(
            verifier
                .verified_subject(&signed_token(
                    "fixture-key",
                    "account-1",
                    "other-client",
                    now + 300
                ))
                .await,
            Err(VerifyError::Invalid)
        ));
        assert!(matches!(
            verifier
                .verified_subject(&signed_token(
                    "fixture-key",
                    "account-1",
                    "web-client-id",
                    now - 1
                ))
                .await,
            Err(VerifyError::Invalid)
        ));
        let forged = signed_token("fixture-key", "account-1", "web-client-id", now + 300);
        let mut parts = forged.split('.').map(str::to_owned).collect::<Vec<_>>();
        let replacement = if parts[2].starts_with('A') { "B" } else { "A" };
        parts[2].replace_range(0..1, replacement);
        assert!(matches!(
            verifier.verified_subject(&parts.join(".")).await,
            Err(VerifyError::Invalid)
        ));
        assert!(matches!(
            verifier
                .verified_subject(&signed_token(
                    "unknown-key",
                    "account-1",
                    "web-client-id",
                    now + 300
                ))
                .await,
            Err(VerifyError::Invalid)
        ));
        assert_eq!(hits.load(Ordering::SeqCst), 2);
        server.abort();
    }

    #[tokio::test]
    async fn configuration_absence_and_jwks_outage_fail_closed_with_backoff() {
        let empty = GoogleTokenVerifier::for_test(vec![], "http://127.0.0.1:1/never".into());
        assert!(matches!(
            empty.verified_subject("anything").await,
            Err(VerifyError::NotConfigured)
        ));
        let (url, hits, server) = jwks_server(503, "{}".into()).await;
        let verifier = GoogleTokenVerifier::for_test(vec!["web-client-id".into()], url);
        let token = signed_token("fixture-key", "account-1", "web-client-id", 9_999_999_999);
        assert!(matches!(
            verifier.verified_subject(&token).await,
            Err(VerifyError::Unavailable)
        ));
        assert!(matches!(
            verifier.verified_subject(&token).await,
            Err(VerifyError::Unavailable)
        ));
        assert_eq!(hits.load(Ordering::SeqCst), 1);
        server.abort();
    }
}
