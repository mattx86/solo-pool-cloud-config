use axum::{
    body::Body,
    extract::ConnectInfo,
    http::{Request, Response},
};
use chrono::Utc;
use std::{
    fs::{File, OpenOptions},
    io::Write,
    net::SocketAddr,
    path::Path,
    sync::{Arc, Mutex},
    task::{Context, Poll},
    time::Instant,
};
use tower::{Layer, Service};

/// Apache Combined Log Format writer
pub struct AccessLogWriter {
    file: Arc<Mutex<File>>,
}

impl AccessLogWriter {
    pub fn new(log_path: &Path) -> std::io::Result<Self> {
        // Ensure parent directory exists
        if let Some(parent) = log_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_path)?;

        Ok(Self {
            file: Arc::new(Mutex::new(file)),
        })
    }

    pub fn write_log(&self, entry: &AccessLogEntry) {
        let log_line = entry.format_combined();
        if let Ok(mut file) = self.file.lock() {
            let _ = writeln!(file, "{}", log_line);
            let _ = file.flush();
        }
    }
}

impl Clone for AccessLogWriter {
    fn clone(&self) -> Self {
        Self {
            file: Arc::clone(&self.file),
        }
    }
}

/// Single access log entry
pub struct AccessLogEntry {
    pub remote_addr: String,
    pub remote_user: String,
    pub time: chrono::DateTime<Utc>,
    pub method: String,
    pub path: String,
    pub protocol: String,
    pub status: u16,
    pub bytes: u64,
    pub referer: String,
    pub user_agent: String,
    pub response_time_ms: u64,
}

impl AccessLogEntry {
    /// Format as Apache Combined Log Format
    /// Format: %h %l %u %t "%r" %>s %b "%{Referer}i" "%{User-agent}i"
    pub fn format_combined(&self) -> String {
        format!(
            "{} - {} [{}] \"{} {} {}\" {} {} \"{}\" \"{}\" {}ms",
            self.remote_addr,
            if self.remote_user.is_empty() { "-" } else { &self.remote_user },
            self.time.format("%d/%b/%Y:%H:%M:%S %z"),
            self.method,
            self.path,
            self.protocol,
            self.status,
            if self.bytes == 0 { "-".to_string() } else { self.bytes.to_string() },
            if self.referer.is_empty() { "-" } else { &self.referer },
            if self.user_agent.is_empty() { "-" } else { &self.user_agent },
            self.response_time_ms,
        )
    }
}

/// Tower layer for access logging
#[derive(Clone)]
pub struct AccessLogLayer {
    writer: AccessLogWriter,
}

impl AccessLogLayer {
    pub fn new(writer: AccessLogWriter) -> Self {
        Self { writer }
    }
}

impl<S> Layer<S> for AccessLogLayer {
    type Service = AccessLogService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        AccessLogService {
            inner,
            writer: self.writer.clone(),
        }
    }
}

/// Tower service for access logging
#[derive(Clone)]
pub struct AccessLogService<S> {
    inner: S,
    writer: AccessLogWriter,
}

impl<S, ReqBody, ResBody> Service<Request<ReqBody>> for AccessLogService<S>
where
    S: Service<Request<ReqBody>, Response = Response<ResBody>> + Clone + Send + 'static,
    S::Future: Send,
    ReqBody: Send + 'static,
    ResBody: Default + Send + 'static,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: Request<ReqBody>) -> Self::Future {
        let start = Instant::now();
        let writer = self.writer.clone();

        // Extract request info before consuming
        let method = req.method().to_string();
        let path = req.uri().path_and_query()
            .map(|pq| pq.to_string())
            .unwrap_or_else(|| req.uri().path().to_string());
        let protocol = format!("{:?}", req.version());

        let remote_addr = req
            .extensions()
            .get::<ConnectInfo<SocketAddr>>()
            .map(|ci| ci.0.ip().to_string())
            .unwrap_or_else(|| "-".to_string());

        let referer = req
            .headers()
            .get("referer")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string();

        let user_agent = req
            .headers()
            .get("user-agent")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string();

        let time = Utc::now();

        let future = self.inner.call(req);

        Box::pin(async move {
            let response = future.await?;

            let status = response.status().as_u16();
            let response_time_ms = start.elapsed().as_millis() as u64;

            // Try to get content-length, default to 0
            let bytes = response
                .headers()
                .get("content-length")
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.parse().ok())
                .unwrap_or(0);

            let entry = AccessLogEntry {
                remote_addr,
                remote_user: String::new(),
                time,
                method,
                path,
                protocol,
                status,
                bytes,
                referer,
                user_agent,
                response_time_ms,
            };

            writer.write_log(&entry);

            Ok(response)
        })
    }
}
