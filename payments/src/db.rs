//! Database module for share tracking and payment history
//!
//! Uses SQLite with WAL mode for concurrent reads.
//! Writes are serialized through a tokio mutex to prevent lock contention.

use anyhow::Result;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{sqlite::SqlitePoolOptions, SqlitePool};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

/// Supported coins for payment processing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "lowercase")]
pub enum Coin {
    Xmr,
    Xtm,
    Aleo,
}

impl std::fmt::Display for Coin {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Coin::Xmr => write!(f, "xmr"),
            Coin::Xtm => write!(f, "xtm"),
            Coin::Aleo => write!(f, "aleo"),
        }
    }
}

impl std::str::FromStr for Coin {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "xmr" => Ok(Coin::Xmr),
            "xtm" => Ok(Coin::Xtm),
            "aleo" => Ok(Coin::Aleo),
            _ => Err(anyhow::anyhow!("Unknown coin: {}", s)),
        }
    }
}

/// A share submitted by a miner
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Share {
    pub id: i64,
    pub coin: Coin,
    pub wallet_address: String,
    pub worker_name: String,
    pub difficulty: Decimal,
    pub timestamp: DateTime<Utc>,
    pub block_height: Option<i64>,
    /// Whether this share found a block
    pub is_block: bool,
}

/// Miner balance for a specific coin
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MinerBalance {
    pub wallet_address: String,
    pub coin: Coin,
    /// Pending balance (unpaid)
    pub pending_balance: Decimal,
    /// Total paid out
    pub total_paid: Decimal,
    /// Total shares submitted
    pub total_shares: i64,
    /// Last share timestamp
    pub last_share: Option<DateTime<Utc>>,
    /// Last payment timestamp
    pub last_payment: Option<DateTime<Utc>>,
}

/// Payment status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "lowercase")]
pub enum PaymentStatus {
    Pending,
    Processing,
    Confirmed,
    Failed,
}

/// A payment record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Payment {
    pub id: String,
    pub coin: Coin,
    pub wallet_address: String,
    pub amount: Decimal,
    pub tx_hash: Option<String>,
    pub status: PaymentStatus,
    pub created_at: DateTime<Utc>,
    pub confirmed_at: Option<DateTime<Utc>>,
    pub error_message: Option<String>,
}

/// Block found by the pool
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockFound {
    pub id: i64,
    pub coin: Coin,
    pub block_height: i64,
    pub block_hash: String,
    pub reward: Decimal,
    pub finder_wallet: String,
    pub finder_worker: String,
    pub timestamp: DateTime<Utc>,
    /// Whether reward has been distributed
    pub distributed: bool,
}

/// Database connection and operations
///
/// Uses a write lock to serialize write operations (SQLite limitation)
/// while allowing concurrent reads via WAL mode.
#[derive(Clone)]
pub struct Database {
    pool: SqlitePool,
    /// Write lock to serialize write operations
    write_lock: Arc<Mutex<()>>,
}

impl Database {
    /// Create a new database connection
    pub async fn new(path: &Path) -> Result<Self> {
        // Create parent directory if needed
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        let db_url = format!("sqlite:{}?mode=rwc", path.display());
        let pool = SqlitePoolOptions::new()
            .max_connections(10)  // More connections for reads
            .connect(&db_url)
            .await?;

        // Enable WAL mode for better concurrent read performance
        sqlx::query("PRAGMA journal_mode=WAL")
            .execute(&pool)
            .await?;

        // Set busy timeout to wait for locks instead of failing immediately
        sqlx::query("PRAGMA busy_timeout=5000")
            .execute(&pool)
            .await?;

        // Synchronous mode: NORMAL is a good balance of safety and performance
        sqlx::query("PRAGMA synchronous=NORMAL")
            .execute(&pool)
            .await?;

        let db = Self {
            pool,
            write_lock: Arc::new(Mutex::new(())),
        };
        db.init_schema().await?;

        Ok(db)
    }

    /// Initialize database schema
    async fn init_schema(&self) -> Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS shares (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                coin TEXT NOT NULL,
                wallet_address TEXT NOT NULL,
                worker_name TEXT NOT NULL,
                difficulty TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                block_height INTEGER,
                is_block INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_shares_wallet ON shares(coin, wallet_address);
            CREATE INDEX IF NOT EXISTS idx_shares_timestamp ON shares(timestamp);

            CREATE TABLE IF NOT EXISTS balances (
                wallet_address TEXT NOT NULL,
                coin TEXT NOT NULL,
                pending_balance TEXT NOT NULL DEFAULT '0',
                total_paid TEXT NOT NULL DEFAULT '0',
                total_shares INTEGER NOT NULL DEFAULT 0,
                last_share TEXT,
                last_payment TEXT,
                PRIMARY KEY (wallet_address, coin)
            );

            CREATE TABLE IF NOT EXISTS payments (
                id TEXT PRIMARY KEY,
                coin TEXT NOT NULL,
                wallet_address TEXT NOT NULL,
                amount TEXT NOT NULL,
                tx_hash TEXT,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                confirmed_at TEXT,
                error_message TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_payments_wallet ON payments(coin, wallet_address);
            CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);

            CREATE TABLE IF NOT EXISTS blocks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                coin TEXT NOT NULL,
                block_height INTEGER NOT NULL,
                block_hash TEXT NOT NULL,
                reward TEXT NOT NULL,
                finder_wallet TEXT NOT NULL,
                finder_worker TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                distributed INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_blocks_coin ON blocks(coin);
            CREATE UNIQUE INDEX IF NOT EXISTS idx_blocks_hash ON blocks(block_hash);

            CREATE TABLE IF NOT EXISTS pool_stats (
                coin TEXT PRIMARY KEY,
                total_shares INTEGER NOT NULL DEFAULT 0,
                total_blocks INTEGER NOT NULL DEFAULT 0,
                total_paid TEXT NOT NULL DEFAULT '0',
                last_block_time TEXT,
                last_updated TEXT NOT NULL
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Record a share submission (serialized write)
    pub async fn record_share(
        &self,
        coin: Coin,
        wallet_address: &str,
        worker_name: &str,
        difficulty: Decimal,
        block_height: Option<i64>,
        is_block: bool,
    ) -> Result<i64> {
        // Acquire write lock
        let _lock = self.write_lock.lock().await;

        let now = Utc::now();
        let coin_str = coin.to_string();
        let diff_str = difficulty.to_string();
        let timestamp_str = now.to_rfc3339();

        let result = sqlx::query(
            r#"
            INSERT INTO shares (coin, wallet_address, worker_name, difficulty, timestamp, block_height, is_block)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&coin_str)
        .bind(wallet_address)
        .bind(worker_name)
        .bind(&diff_str)
        .bind(&timestamp_str)
        .bind(block_height)
        .bind(is_block as i32)
        .execute(&self.pool)
        .await?;

        // Update balance
        sqlx::query(
            r#"
            INSERT INTO balances (wallet_address, coin, total_shares, last_share)
            VALUES (?, ?, 1, ?)
            ON CONFLICT(wallet_address, coin) DO UPDATE SET
                total_shares = total_shares + 1,
                last_share = excluded.last_share
            "#,
        )
        .bind(wallet_address)
        .bind(&coin_str)
        .bind(&timestamp_str)
        .execute(&self.pool)
        .await?;

        Ok(result.last_insert_rowid())
    }

    /// Record a block found (serialized write)
    pub async fn record_block(
        &self,
        coin: Coin,
        block_height: i64,
        block_hash: &str,
        reward: Decimal,
        finder_wallet: &str,
        finder_worker: &str,
    ) -> Result<i64> {
        let _lock = self.write_lock.lock().await;
        let now = Utc::now();
        let coin_str = coin.to_string();
        let reward_str = reward.to_string();
        let timestamp_str = now.to_rfc3339();

        let result = sqlx::query(
            r#"
            INSERT INTO blocks (coin, block_height, block_hash, reward, finder_wallet, finder_worker, timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(block_hash) DO NOTHING
            "#,
        )
        .bind(&coin_str)
        .bind(block_height)
        .bind(block_hash)
        .bind(&reward_str)
        .bind(finder_wallet)
        .bind(finder_worker)
        .bind(&timestamp_str)
        .execute(&self.pool)
        .await?;

        Ok(result.last_insert_rowid())
    }

    /// Get undistributed blocks for a coin
    pub async fn get_undistributed_blocks(&self, coin: Coin) -> Result<Vec<BlockFound>> {
        let coin_str = coin.to_string();

        let rows = sqlx::query_as::<_, (i64, String, i64, String, String, String, String, String, i32)>(
            r#"
            SELECT id, coin, block_height, block_hash, reward, finder_wallet, finder_worker, timestamp, distributed
            FROM blocks
            WHERE coin = ? AND distributed = 0
            ORDER BY block_height ASC
            "#,
        )
        .bind(&coin_str)
        .fetch_all(&self.pool)
        .await?;

        let blocks = rows
            .into_iter()
            .map(|row| BlockFound {
                id: row.0,
                coin: row.1.parse().unwrap_or(coin),
                block_height: row.2,
                block_hash: row.3,
                reward: row.4.parse().unwrap_or_default(),
                finder_wallet: row.5,
                finder_worker: row.6,
                timestamp: DateTime::parse_from_rfc3339(&row.7)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
                distributed: row.8 != 0,
            })
            .collect();

        Ok(blocks)
    }

    /// Mark a block as distributed (serialized write)
    pub async fn mark_block_distributed(&self, block_id: i64) -> Result<()> {
        let _lock = self.write_lock.lock().await;
        sqlx::query("UPDATE blocks SET distributed = 1 WHERE id = ?")
            .bind(block_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Add to a miner's pending balance (serialized write)
    pub async fn add_pending_balance(
        &self,
        coin: Coin,
        wallet_address: &str,
        amount: Decimal,
    ) -> Result<()> {
        let _lock = self.write_lock.lock().await;
        let coin_str = coin.to_string();
        let amount_str = amount.to_string();

        sqlx::query(
            r#"
            INSERT INTO balances (wallet_address, coin, pending_balance)
            VALUES (?, ?, ?)
            ON CONFLICT(wallet_address, coin) DO UPDATE SET
                pending_balance = CAST(
                    (CAST(pending_balance AS REAL) + CAST(? AS REAL)) AS TEXT
                )
            "#,
        )
        .bind(wallet_address)
        .bind(&coin_str)
        .bind(&amount_str)
        .bind(&amount_str)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Get all balances above minimum payout threshold
    pub async fn get_payable_balances(
        &self,
        coin: Coin,
        min_payout: Decimal,
    ) -> Result<Vec<MinerBalance>> {
        let coin_str = coin.to_string();
        let min_str = min_payout.to_string();

        let rows = sqlx::query_as::<_, (String, String, String, String, i64, Option<String>, Option<String>)>(
            r#"
            SELECT wallet_address, coin, pending_balance, total_paid, total_shares, last_share, last_payment
            FROM balances
            WHERE coin = ? AND CAST(pending_balance AS REAL) >= CAST(? AS REAL)
            "#,
        )
        .bind(&coin_str)
        .bind(&min_str)
        .fetch_all(&self.pool)
        .await?;

        let balances = rows
            .into_iter()
            .map(|row| MinerBalance {
                wallet_address: row.0,
                coin: row.1.parse().unwrap_or(coin),
                pending_balance: row.2.parse().unwrap_or_default(),
                total_paid: row.3.parse().unwrap_or_default(),
                total_shares: row.4,
                last_share: row.5.and_then(|s| {
                    DateTime::parse_from_rfc3339(&s)
                        .map(|dt| dt.with_timezone(&Utc))
                        .ok()
                }),
                last_payment: row.6.and_then(|s| {
                    DateTime::parse_from_rfc3339(&s)
                        .map(|dt| dt.with_timezone(&Utc))
                        .ok()
                }),
            })
            .collect();

        Ok(balances)
    }

    /// Get a miner's balance for a specific coin
    pub async fn get_miner_balance(
        &self,
        coin: Coin,
        wallet_address: &str,
    ) -> Result<Option<MinerBalance>> {
        let coin_str = coin.to_string();

        let row = sqlx::query_as::<_, (String, String, String, String, i64, Option<String>, Option<String>)>(
            r#"
            SELECT wallet_address, coin, pending_balance, total_paid, total_shares, last_share, last_payment
            FROM balances
            WHERE coin = ? AND wallet_address = ?
            "#,
        )
        .bind(&coin_str)
        .bind(wallet_address)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|row| MinerBalance {
            wallet_address: row.0,
            coin: row.1.parse().unwrap_or(coin),
            pending_balance: row.2.parse().unwrap_or_default(),
            total_paid: row.3.parse().unwrap_or_default(),
            total_shares: row.4,
            last_share: row.5.and_then(|s| {
                DateTime::parse_from_rfc3339(&s)
                    .map(|dt| dt.with_timezone(&Utc))
                    .ok()
            }),
            last_payment: row.6.and_then(|s| {
                DateTime::parse_from_rfc3339(&s)
                    .map(|dt| dt.with_timezone(&Utc))
                    .ok()
            }),
        }))
    }

    /// Create a payment record (serialized write)
    pub async fn create_payment(
        &self,
        coin: Coin,
        wallet_address: &str,
        amount: Decimal,
    ) -> Result<String> {
        let _lock = self.write_lock.lock().await;
        let id = Uuid::new_v4().to_string();
        let now = Utc::now();
        let coin_str = coin.to_string();
        let amount_str = amount.to_string();
        let timestamp_str = now.to_rfc3339();

        sqlx::query(
            r#"
            INSERT INTO payments (id, coin, wallet_address, amount, status, created_at)
            VALUES (?, ?, ?, ?, 'pending', ?)
            "#,
        )
        .bind(&id)
        .bind(&coin_str)
        .bind(wallet_address)
        .bind(&amount_str)
        .bind(&timestamp_str)
        .execute(&self.pool)
        .await?;

        Ok(id)
    }

    /// Update payment status (serialized write)
    pub async fn update_payment_status(
        &self,
        payment_id: &str,
        status: PaymentStatus,
        tx_hash: Option<&str>,
        error_message: Option<&str>,
    ) -> Result<()> {
        let _lock = self.write_lock.lock().await;
        let status_str = match status {
            PaymentStatus::Pending => "pending",
            PaymentStatus::Processing => "processing",
            PaymentStatus::Confirmed => "confirmed",
            PaymentStatus::Failed => "failed",
        };

        let confirmed_at = if status == PaymentStatus::Confirmed {
            Some(Utc::now().to_rfc3339())
        } else {
            None
        };

        sqlx::query(
            r#"
            UPDATE payments
            SET status = ?, tx_hash = COALESCE(?, tx_hash), confirmed_at = ?, error_message = ?
            WHERE id = ?
            "#,
        )
        .bind(status_str)
        .bind(tx_hash)
        .bind(confirmed_at)
        .bind(error_message)
        .bind(payment_id)
        .execute(&self.pool)
        .await?;

        // If confirmed, update the balance
        if status == PaymentStatus::Confirmed {
            let now = Utc::now().to_rfc3339();

            sqlx::query(
                r#"
                UPDATE balances
                SET pending_balance = CAST(
                        (CAST(pending_balance AS REAL) - (
                            SELECT CAST(amount AS REAL) FROM payments WHERE id = ?
                        )) AS TEXT
                    ),
                    total_paid = CAST(
                        (CAST(total_paid AS REAL) + (
                            SELECT CAST(amount AS REAL) FROM payments WHERE id = ?
                        )) AS TEXT
                    ),
                    last_payment = ?
                WHERE wallet_address = (SELECT wallet_address FROM payments WHERE id = ?)
                  AND coin = (SELECT coin FROM payments WHERE id = ?)
                "#,
            )
            .bind(payment_id)
            .bind(payment_id)
            .bind(&now)
            .bind(payment_id)
            .bind(payment_id)
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    /// Get pending payments for a coin
    pub async fn get_pending_payments(&self, coin: Coin) -> Result<Vec<Payment>> {
        let coin_str = coin.to_string();

        let rows = sqlx::query_as::<_, (String, String, String, String, Option<String>, String, String, Option<String>, Option<String>)>(
            r#"
            SELECT id, coin, wallet_address, amount, tx_hash, status, created_at, confirmed_at, error_message
            FROM payments
            WHERE coin = ? AND status IN ('pending', 'processing')
            ORDER BY created_at ASC
            "#,
        )
        .bind(&coin_str)
        .fetch_all(&self.pool)
        .await?;

        let payments = rows
            .into_iter()
            .map(|row| Payment {
                id: row.0,
                coin: row.1.parse().unwrap_or(coin),
                wallet_address: row.2,
                amount: row.3.parse().unwrap_or_default(),
                tx_hash: row.4,
                status: match row.5.as_str() {
                    "processing" => PaymentStatus::Processing,
                    "confirmed" => PaymentStatus::Confirmed,
                    "failed" => PaymentStatus::Failed,
                    _ => PaymentStatus::Pending,
                },
                created_at: DateTime::parse_from_rfc3339(&row.6)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
                confirmed_at: row.7.and_then(|s| {
                    DateTime::parse_from_rfc3339(&s)
                        .map(|dt| dt.with_timezone(&Utc))
                        .ok()
                }),
                error_message: row.8,
            })
            .collect();

        Ok(payments)
    }

    /// Get payment history for a miner
    pub async fn get_miner_payments(
        &self,
        coin: Coin,
        wallet_address: &str,
        limit: i32,
    ) -> Result<Vec<Payment>> {
        let coin_str = coin.to_string();

        let rows = sqlx::query_as::<_, (String, String, String, String, Option<String>, String, String, Option<String>, Option<String>)>(
            r#"
            SELECT id, coin, wallet_address, amount, tx_hash, status, created_at, confirmed_at, error_message
            FROM payments
            WHERE coin = ? AND wallet_address = ?
            ORDER BY created_at DESC
            LIMIT ?
            "#,
        )
        .bind(&coin_str)
        .bind(wallet_address)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        let payments = rows
            .into_iter()
            .map(|row| Payment {
                id: row.0,
                coin: row.1.parse().unwrap_or(coin),
                wallet_address: row.2,
                amount: row.3.parse().unwrap_or_default(),
                tx_hash: row.4,
                status: match row.5.as_str() {
                    "processing" => PaymentStatus::Processing,
                    "confirmed" => PaymentStatus::Confirmed,
                    "failed" => PaymentStatus::Failed,
                    _ => PaymentStatus::Pending,
                },
                created_at: DateTime::parse_from_rfc3339(&row.6)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
                confirmed_at: row.7.and_then(|s| {
                    DateTime::parse_from_rfc3339(&s)
                        .map(|dt| dt.with_timezone(&Utc))
                        .ok()
                }),
                error_message: row.8,
            })
            .collect();

        Ok(payments)
    }

    /// Get share count for a miner in a time range (for proportional payout calculation)
    pub async fn get_share_count_in_range(
        &self,
        coin: Coin,
        wallet_address: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> Result<i64> {
        let coin_str = coin.to_string();
        let from_str = from.to_rfc3339();
        let to_str = to.to_rfc3339();

        let row = sqlx::query_as::<_, (i64,)>(
            r#"
            SELECT COUNT(*)
            FROM shares
            WHERE coin = ? AND wallet_address = ? AND timestamp >= ? AND timestamp <= ?
            "#,
        )
        .bind(&coin_str)
        .bind(wallet_address)
        .bind(&from_str)
        .bind(&to_str)
        .fetch_one(&self.pool)
        .await?;

        Ok(row.0)
    }

    /// Get total share count for all miners in a time range
    pub async fn get_total_shares_in_range(
        &self,
        coin: Coin,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> Result<i64> {
        let coin_str = coin.to_string();
        let from_str = from.to_rfc3339();
        let to_str = to.to_rfc3339();

        let row = sqlx::query_as::<_, (i64,)>(
            r#"
            SELECT COUNT(*)
            FROM shares
            WHERE coin = ? AND timestamp >= ? AND timestamp <= ?
            "#,
        )
        .bind(&coin_str)
        .bind(&from_str)
        .bind(&to_str)
        .fetch_one(&self.pool)
        .await?;

        Ok(row.0)
    }

    /// Get all miners who submitted shares in a time range
    pub async fn get_miners_in_range(
        &self,
        coin: Coin,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> Result<Vec<String>> {
        let coin_str = coin.to_string();
        let from_str = from.to_rfc3339();
        let to_str = to.to_rfc3339();

        let rows = sqlx::query_as::<_, (String,)>(
            r#"
            SELECT DISTINCT wallet_address
            FROM shares
            WHERE coin = ? AND timestamp >= ? AND timestamp <= ?
            "#,
        )
        .bind(&coin_str)
        .bind(&from_str)
        .bind(&to_str)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.into_iter().map(|r| r.0).collect())
    }
}
