//! Authentication module for Solo Pool WebUI
//!
//! Provides session-based authentication using cookies.
//! Credentials are loaded from a bash-style credentials file.

use axum::{
    body::Body,
    extract::State,
    http::{header, Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Redirect, Response},
};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tower_cookies::{Cookie, Cookies};

use crate::config::AuthConfig;

/// Credentials loaded from file
#[derive(Debug, Clone)]
pub struct Credentials {
    pub username: String,
    pub password_hash: String,
}

/// Session data
#[derive(Debug, Clone)]
pub struct Session {
    pub username: String,
    pub created_at: Instant,
}

/// Session store (in-memory)
pub struct SessionStore {
    sessions: RwLock<HashMap<String, Session>>,
    timeout: Duration,
}

impl SessionStore {
    pub fn new(timeout_secs: u64) -> Self {
        Self {
            sessions: RwLock::new(HashMap::new()),
            timeout: Duration::from_secs(timeout_secs),
        }
    }

    /// Create a new session and return the session ID
    pub async fn create(&self, username: String) -> String {
        let session_id = uuid::Uuid::new_v4().to_string();
        let session = Session {
            username,
            created_at: Instant::now(),
        };
        self.sessions.write().await.insert(session_id.clone(), session);
        session_id
    }

    /// Validate a session and return the username if valid
    pub async fn validate(&self, session_id: &str) -> Option<String> {
        let sessions = self.sessions.read().await;
        if let Some(session) = sessions.get(session_id) {
            if session.created_at.elapsed() < self.timeout {
                return Some(session.username.clone());
            }
        }
        None
    }

    /// Remove a session
    pub async fn remove(&self, session_id: &str) {
        self.sessions.write().await.remove(session_id);
    }

    /// Clean up expired sessions
    pub async fn cleanup(&self) {
        let mut sessions = self.sessions.write().await;
        sessions.retain(|_, session| session.created_at.elapsed() < self.timeout);
    }
}

/// Hash a password using SHA256
pub fn hash_password(password: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(password.as_bytes());
    hex::encode(hasher.finalize())
}

/// Load credentials from a bash-style credentials file
/// Format:
///   SOLO_POOL_WEBUI_USER="username"
///   SOLO_POOL_WEBUI_PASS="password"
pub fn load_credentials(path: &str) -> anyhow::Result<Credentials> {
    let content = std::fs::read_to_string(path)?;

    let mut username = None;
    let mut password = None;

    for line in content.lines() {
        let line = line.trim();
        if line.starts_with("SOLO_POOL_WEBUI_USER=") {
            // Extract value between quotes
            if let Some(val) = extract_quoted_value(line, "SOLO_POOL_WEBUI_USER=") {
                username = Some(val);
            }
        } else if line.starts_with("SOLO_POOL_WEBUI_PASS=") {
            if let Some(val) = extract_quoted_value(line, "SOLO_POOL_WEBUI_PASS=") {
                password = Some(val);
            }
        }
    }

    match (username, password) {
        (Some(u), Some(p)) => Ok(Credentials {
            username: u,
            password_hash: hash_password(&p),
        }),
        _ => anyhow::bail!("Missing SOLO_POOL_WEBUI_USER or SOLO_POOL_WEBUI_PASS in credentials file"),
    }
}

/// Extract a value from a line like KEY="value" or KEY='value'
fn extract_quoted_value(line: &str, prefix: &str) -> Option<String> {
    let rest = line.strip_prefix(prefix)?;
    let rest = rest.trim();

    // Handle both single and double quotes
    if (rest.starts_with('"') && rest.ends_with('"')) ||
       (rest.starts_with('\'') && rest.ends_with('\'')) {
        Some(rest[1..rest.len()-1].to_string())
    } else {
        // No quotes, just use the value
        Some(rest.to_string())
    }
}

/// Authentication state shared across handlers
pub struct AuthState {
    pub credentials: Credentials,
    pub sessions: SessionStore,
    pub cookie_name: String,
    pub enabled: bool,
}

impl AuthState {
    pub fn new(config: &AuthConfig) -> anyhow::Result<Self> {
        let credentials = if config.enabled {
            load_credentials(&config.credentials_file)?
        } else {
            // Dummy credentials when auth is disabled
            Credentials {
                username: "admin".to_string(),
                password_hash: String::new(),
            }
        };

        Ok(Self {
            credentials,
            sessions: SessionStore::new(config.session_timeout_secs),
            cookie_name: config.cookie_name.clone(),
            enabled: config.enabled,
        })
    }

    /// Verify login credentials
    pub fn verify(&self, username: &str, password: &str) -> bool {
        username == self.credentials.username &&
        hash_password(password) == self.credentials.password_hash
    }
}

/// Middleware to require authentication
pub async fn require_auth(
    State(auth): State<Arc<AuthState>>,
    cookies: Cookies,
    request: Request<Body>,
    next: Next,
) -> Response {
    // Skip auth if disabled
    if !auth.enabled {
        return next.run(request).await;
    }

    let path = request.uri().path();

    // Allow login page and static assets for login
    if path == "/login" ||
       path == "/login.html" ||
       path.starts_with("/api/auth/") ||
       path == "/css/style.css" ||
       path == "/css/login.css" {
        return next.run(request).await;
    }

    // Check for valid session
    if let Some(session_cookie) = cookies.get(&auth.cookie_name) {
        if auth.sessions.validate(session_cookie.value()).await.is_some() {
            return next.run(request).await;
        }
    }

    // Not authenticated - redirect to login or return 401 for API
    if path.starts_with("/api/") {
        return (StatusCode::UNAUTHORIZED, "Authentication required").into_response();
    }

    Redirect::to("/login").into_response()
}
