use reqwest::{Client, StatusCode};
use serde_json::json;
use std::{
    env,
    net::IpAddr,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::task::JoinSet;

#[derive(Clone)]
struct Sample {
    label: &'static str,
    elapsed: Duration,
    ok: bool,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let url = args
        .first()
        .map(String::as_str)
        .unwrap_or("http://127.0.0.1:8080");
    let concurrency = args
        .get(1)
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(32)
        .clamp(1, 128);
    let requests = args
        .get(2)
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(2_000)
        .clamp(1, 100_000);
    let parsed = reqwest::Url::parse(url)?;
    let host = parsed.host_str().ok_or("URL has no host")?;
    let loopback = match host.parse::<IpAddr>() {
        Ok(ip) => ip.is_loopback(),
        Err(_) => host.eq_ignore_ascii_case("localhost"),
    };
    if parsed.scheme() != "http" || !loopback {
        return Err("loadgen only accepts http://localhost or a loopback IP".into());
    }
    let client = Client::builder()
        .no_proxy()
        .timeout(Duration::from_secs(10))
        .build()?;
    let base = url.trim_end_matches('/').to_owned();
    let get_start = Instant::now();
    let get_samples = run_phase(concurrency, requests, {
        let client = client.clone();
        let base = base.clone();
        move |_| {
            let client = client.clone();
            let url = format!("{base}/v1/rankings?period=all");
            async move {
                let started = Instant::now();
                let ok = match client.get(url).send().await {
                    Ok(response) => {
                        let status = response.status();
                        response.bytes().await.is_ok() && status == StatusCode::OK
                    }
                    Err(_) => false,
                };
                vec![Sample {
                    label: "GET rankings",
                    elapsed: started.elapsed(),
                    ok,
                }]
            }
        }
    })
    .await;
    report_phase("GET rankings", &get_samples, get_start.elapsed());

    let prefix = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos() as u64;
    let seq = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
    let write_start = Instant::now();
    let write_samples=run_phase(concurrency,requests,{
        let client=client.clone(); let base=base.clone(); let seq=seq.clone();
        move |_| { let client=client.clone(); let base=base.clone(); let n=seq.fetch_add(1,std::sync::atomic::Ordering::Relaxed); async move {
            let batch=format!("{prefix:016x}{n:016x}");
            let token=format!("{prefix:016x}{:048x}",n+1);
            let body=json!({"schema_version":1,"batch_id":batch,"delete_token":token,"items":[{"shortcut_id":"copy","count":1}]});
            let post_started=Instant::now();
            let accepted=match client.post(format!("{base}/v1/contributions")).json(&body).send().await {
                Ok(response)=>{let status=response.status(); response.bytes().await.is_ok() && (status==StatusCode::CREATED || status==StatusCode::OK)}, Err(_)=>false
            };
            let post_sample=Sample{label:"POST",elapsed:post_started.elapsed(),ok:accepted};
            if !accepted { return vec![post_sample]; }
            let delete_started=Instant::now();
            let deleted=match client.delete(format!("{base}/v1/contributions/{batch}")).bearer_auth(token).send().await {
                Ok(response)=>{let status=response.status(); response.bytes().await.is_ok() && status==StatusCode::NO_CONTENT}, Err(_)=>false
            };
            vec![post_sample,Sample{label:"DELETE",elapsed:delete_started.elapsed(),ok:deleted}]
        } }
    }).await;
    report_phase("POST + DELETE", &write_samples, write_start.elapsed());
    let failures = get_samples
        .iter()
        .chain(&write_samples)
        .filter(|sample| !sample.ok)
        .count();
    if failures > 0 {
        return Err(format!(
            "load run had {failures} failed HTTP operations; see error counts above"
        )
        .into());
    }
    Ok(())
}

async fn run_phase<F, Fut>(concurrency: usize, count: usize, make: F) -> Vec<Sample>
where
    F: Fn(usize) -> Fut + Clone + Send + Sync + 'static,
    Fut: std::future::Future<Output = Vec<Sample>> + Send + 'static,
{
    let mut tasks = JoinSet::new();
    let mut samples = Vec::with_capacity(count);
    for i in 0..count {
        while tasks.len() >= concurrency {
            if let Some(result) = tasks.join_next().await {
                collect_result(result, &mut samples);
            }
        }
        let make = make.clone();
        tasks.spawn(async move { make(i).await });
    }
    while let Some(result) = tasks.join_next().await {
        collect_result(result, &mut samples);
    }
    samples
}

fn collect_result(result: Result<Vec<Sample>, tokio::task::JoinError>, samples: &mut Vec<Sample>) {
    match result {
        Ok(mut completed) => samples.append(&mut completed),
        Err(_) => samples.push(Sample {
            label: "task",
            elapsed: Duration::ZERO,
            ok: false,
        }),
    }
}

fn report_phase(label: &str, samples: &[Sample], wall: Duration) {
    let throughput = samples.len() as f64 / wall.as_secs_f64();
    println!(
        "{label}: operations={} throughput={throughput:.1}/s wall={:.3}s",
        samples.len(),
        wall.as_secs_f64()
    );
    for name in ["GET rankings", "POST", "DELETE", "task"] {
        let mut durations = samples
            .iter()
            .filter(|s| s.label == name)
            .map(|s| s.elapsed.as_micros())
            .collect::<Vec<_>>();
        if durations.is_empty() {
            continue;
        }
        durations.sort_unstable();
        let percentile = |p: usize| durations[((durations.len() - 1) * p) / 100] as f64 / 1000.0;
        let errors = samples.iter().filter(|s| s.label == name && !s.ok).count();
        println!(
            "  {name}: n={} errors={errors} p50={:.2}ms p95={:.2}ms",
            durations.len(),
            percentile(50),
            percentile(95)
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn run_phase_collects_every_completion_and_failure() {
        let samples = run_phase(32, 200, |index| async move {
            vec![Sample {
                label: "test",
                elapsed: Duration::from_millis(index as u64),
                ok: index % 17 != 0,
            }]
        })
        .await;
        assert_eq!(samples.len(), 200);
        assert_eq!(samples.iter().filter(|s| !s.ok).count(), 12);
        assert_eq!(
            samples.iter().map(|s| s.elapsed.as_millis()).max(),
            Some(199)
        );
    }
}
