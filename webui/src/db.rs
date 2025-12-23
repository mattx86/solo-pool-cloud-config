//! Database module for persistent worker and pool statistics
//!
//! Uses SQLite to store worker stats that persist across WebUI restarts.
//! Stats are updated periodically from pool backends and stored for display.

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use std::path::Path;
use std::sync::Mutex;

/// Database wrapper with thread-safe connection
pub struct Database {
    conn: Mutex<Connection>,
}

/// Worker statistics from database
#[derive(Debug, Clone)]
pub struct DbWorkerStats {
    pub id: i64,
    pub pool_id: String,
    pub worker_name: String,
    pub wallet_address: String,
    pub hashrate: f64,
    pub hashrate_unit: String,
    pub shares_accepted: u64,
    pub shares_rejected: u64,
    pub blocks_found: u64,
    pub is_online: bool,
    pub last_seen: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

/// Pool aggregate statistics from database
#[derive(Debug, Clone)]
pub struct DbPoolStats {
    pub pool_id: String,
    pub total_hashrate: f64,
    pub hashrate_unit: String,
    pub total_workers: u64,
    pub online_workers: u64,
    pub total_blocks_found: u64,
    pub last_updated: DateTime<Utc>,
}

impl Database {
    /// Initialize the database at the given path
    pub fn new<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let conn = Connection::open(db_path)?;
        let db = Self {
            conn: Mutex::new(conn),
        };
        db.init_schema()?;
        Ok(db)
    }

    /// Create an in-memory database (for testing)
    #[allow(dead_code)]
    pub fn in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        let db = Self {
            conn: Mutex::new(conn),
        };
        db.init_schema()?;
        Ok(db)
    }

    /// Initialize database schema
    fn init_schema(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();

        // Enable WAL mode for better concurrent read performance
        // WAL allows multiple readers while maintaining a single writer
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA synchronous = NORMAL;
             PRAGMA busy_timeout = 5000;"
        )?;

        // Workers table - stores per-worker statistics
        conn.execute(
            r#"
            CREATE TABLE IF NOT EXISTS workers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                pool_id TEXT NOT NULL,
                worker_name TEXT NOT NULL,
                wallet_address TEXT NOT NULL DEFAULT '',
                hashrate REAL NOT NULL DEFAULT 0.0,
                hashrate_unit TEXT NOT NULL DEFAULT 'H/s',
                shares_accepted INTEGER NOT NULL DEFAULT 0,
                shares_rejected INTEGER NOT NULL DEFAULT 0,
                blocks_found INTEGER NOT NULL DEFAULT 0,
                is_online INTEGER NOT NULL DEFAULT 1,
                last_seen TEXT NOT NULL DEFAULT (datetime('now')),
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE(pool_id, worker_name)
            )
            "#,
            [],
        )?;

        // Pool stats table - stores aggregate pool statistics
        conn.execute(
            r#"
            CREATE TABLE IF NOT EXISTS pool_stats (
                pool_id TEXT PRIMARY KEY,
                total_hashrate REAL NOT NULL DEFAULT 0.0,
                hashrate_unit TEXT NOT NULL DEFAULT 'H/s',
                total_workers INTEGER NOT NULL DEFAULT 0,
                online_workers INTEGER NOT NULL DEFAULT 0,
                total_blocks_found INTEGER NOT NULL DEFAULT 0,
                last_updated TEXT NOT NULL DEFAULT (datetime('now'))
            )
            "#,
            [],
        )?;

        // Create indexes for faster lookups
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_workers_pool_id ON workers(pool_id)",
            [],
        )?;
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_workers_is_online ON workers(is_online)",
            [],
        )?;

        Ok(())
    }

    /// Upsert (insert or update) worker stats
    pub fn upsert_worker(
        &self,
        pool_id: &str,
        worker_name: &str,
        wallet_address: &str,
        hashrate: f64,
        hashrate_unit: &str,
        shares_accepted: u64,
        shares_rejected: u64,
        blocks_found: u64,
        is_online: bool,
    ) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();

        conn.execute(
            r#"
            INSERT INTO workers (pool_id, worker_name, wallet_address, hashrate, hashrate_unit,
                                shares_accepted, shares_rejected, blocks_found, is_online, last_seen)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            ON CONFLICT(pool_id, worker_name) DO UPDATE SET
                wallet_address = excluded.wallet_address,
                hashrate = excluded.hashrate,
                hashrate_unit = excluded.hashrate_unit,
                shares_accepted = excluded.shares_accepted,
                shares_rejected = excluded.shares_rejected,
                blocks_found = excluded.blocks_found,
                is_online = excluded.is_online,
                last_seen = CASE WHEN excluded.is_online = 1 THEN excluded.last_seen ELSE workers.last_seen END
            "#,
            params![
                pool_id,
                worker_name,
                wallet_address,
                hashrate,
                hashrate_unit,
                shares_accepted as i64,
                shares_rejected as i64,
                blocks_found as i64,
                is_online as i32,
                now,
            ],
        )?;

        Ok(())
    }

    /// Mark workers as offline if not in the provided list
    pub fn mark_workers_offline(&self, pool_id: &str, online_worker_names: &[String]) -> Result<()> {
        let conn = self.conn.lock().unwrap();

        if online_worker_names.is_empty() {
            // Mark all workers in this pool as offline
            conn.execute(
                "UPDATE workers SET is_online = 0, hashrate = 0 WHERE pool_id = ?1",
                params![pool_id],
            )?;
        } else {
            // Build placeholders for IN clause
            let placeholders: Vec<String> = (0..online_worker_names.len())
                .map(|i| format!("?{}", i + 2))
                .collect();
            let sql = format!(
                "UPDATE workers SET is_online = 0, hashrate = 0 WHERE pool_id = ?1 AND worker_name NOT IN ({})",
                placeholders.join(", ")
            );

            // Build params
            let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::new();
            params_vec.push(&pool_id);
            for name in online_worker_names {
                params_vec.push(name);
            }

            conn.execute(&sql, params_vec.as_slice())?;
        }

        Ok(())
    }

    /// Get all workers for a pool
    pub fn get_workers(&self, pool_id: &str) -> Result<Vec<DbWorkerStats>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            r#"
            SELECT id, pool_id, worker_name, wallet_address, hashrate, hashrate_unit,
                   shares_accepted, shares_rejected, blocks_found, is_online, last_seen, created_at
            FROM workers
            WHERE pool_id = ?1
            ORDER BY is_online DESC, hashrate DESC, worker_name ASC
            "#,
        )?;

        let workers = stmt
            .query_map(params![pool_id], |row| {
                Ok(DbWorkerStats {
                    id: row.get(0)?,
                    pool_id: row.get(1)?,
                    worker_name: row.get(2)?,
                    wallet_address: row.get(3)?,
                    hashrate: row.get(4)?,
                    hashrate_unit: row.get(5)?,
                    shares_accepted: row.get::<_, i64>(6)? as u64,
                    shares_rejected: row.get::<_, i64>(7)? as u64,
                    blocks_found: row.get::<_, i64>(8)? as u64,
                    is_online: row.get::<_, i32>(9)? != 0,
                    last_seen: parse_datetime(&row.get::<_, String>(10)?),
                    created_at: parse_datetime(&row.get::<_, String>(11)?),
                })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        Ok(workers)
    }

    /// Delete a worker by pool_id and worker_name
    pub fn delete_worker(&self, pool_id: &str, worker_name: &str) -> Result<bool> {
        let conn = self.conn.lock().unwrap();
        let rows_affected = conn.execute(
            "DELETE FROM workers WHERE pool_id = ?1 AND worker_name = ?2",
            params![pool_id, worker_name],
        )?;
        Ok(rows_affected > 0)
    }

    /// Delete all workers for a pool
    #[allow(dead_code)]
    pub fn delete_all_workers(&self, pool_id: &str) -> Result<u64> {
        let conn = self.conn.lock().unwrap();
        let rows_affected = conn.execute(
            "DELETE FROM workers WHERE pool_id = ?1",
            params![pool_id],
        )?;
        Ok(rows_affected as u64)
    }

    /// Update pool aggregate statistics
    pub fn update_pool_stats(
        &self,
        pool_id: &str,
        total_hashrate: f64,
        hashrate_unit: &str,
        total_blocks_found: u64,
    ) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();

        // Count workers
        let (total_workers, online_workers): (i64, i64) = conn.query_row(
            "SELECT COUNT(*), SUM(CASE WHEN is_online = 1 THEN 1 ELSE 0 END) FROM workers WHERE pool_id = ?1",
            params![pool_id],
            |row| Ok((row.get(0)?, row.get::<_, Option<i64>>(1)?.unwrap_or(0))),
        )?;

        conn.execute(
            r#"
            INSERT INTO pool_stats (pool_id, total_hashrate, hashrate_unit, total_workers, online_workers, total_blocks_found, last_updated)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            ON CONFLICT(pool_id) DO UPDATE SET
                total_hashrate = excluded.total_hashrate,
                hashrate_unit = excluded.hashrate_unit,
                total_workers = excluded.total_workers,
                online_workers = excluded.online_workers,
                total_blocks_found = excluded.total_blocks_found,
                last_updated = excluded.last_updated
            "#,
            params![
                pool_id,
                total_hashrate,
                hashrate_unit,
                total_workers,
                online_workers,
                total_blocks_found as i64,
                now,
            ],
        )?;

        Ok(())
    }

    /// Get pool aggregate statistics
    pub fn get_pool_stats(&self, pool_id: &str) -> Result<Option<DbPoolStats>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            r#"
            SELECT pool_id, total_hashrate, hashrate_unit, total_workers, online_workers,
                   total_blocks_found, last_updated
            FROM pool_stats
            WHERE pool_id = ?1
            "#,
        )?;

        let result = stmt.query_row(params![pool_id], |row| {
            Ok(DbPoolStats {
                pool_id: row.get(0)?,
                total_hashrate: row.get(1)?,
                hashrate_unit: row.get(2)?,
                total_workers: row.get::<_, i64>(3)? as u64,
                online_workers: row.get::<_, i64>(4)? as u64,
                total_blocks_found: row.get::<_, i64>(5)? as u64,
                last_updated: parse_datetime(&row.get::<_, String>(6)?),
            })
        });

        match result {
            Ok(stats) => Ok(Some(stats)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// Get worker count for a pool
    pub fn get_worker_count(&self, pool_id: &str) -> Result<(u64, u64)> {
        let conn = self.conn.lock().unwrap();
        let (total, online): (i64, i64) = conn.query_row(
            "SELECT COUNT(*), SUM(CASE WHEN is_online = 1 THEN 1 ELSE 0 END) FROM workers WHERE pool_id = ?1",
            params![pool_id],
            |row| Ok((row.get(0)?, row.get::<_, Option<i64>>(1)?.unwrap_or(0))),
        )?;
        Ok((total as u64, online as u64))
    }

    /// Calculate acceptance rate for a worker
    pub fn get_acceptance_rate(&self, pool_id: &str, worker_name: &str) -> Result<Option<f64>> {
        let conn = self.conn.lock().unwrap();
        let result: Result<(i64, i64), _> = conn.query_row(
            "SELECT shares_accepted, shares_rejected FROM workers WHERE pool_id = ?1 AND worker_name = ?2",
            params![pool_id, worker_name],
            |row| Ok((row.get(0)?, row.get(1)?)),
        );

        match result {
            Ok((accepted, rejected)) => {
                let total = accepted + rejected;
                if total > 0 {
                    Ok(Some((accepted as f64 / total as f64) * 100.0))
                } else {
                    Ok(Some(100.0)) // No shares = 100% acceptance
                }
            }
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }
}

/// Parse datetime string from SQLite format
fn parse_datetime(s: &str) -> DateTime<Utc> {
    chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S")
        .map(|dt| dt.and_utc())
        .unwrap_or_else(|_| Utc::now())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_worker_crud() {
        let db = Database::in_memory().unwrap();

        // Insert worker
        db.upsert_worker(
            "btc", "worker1", "1BvBMSE...", 100.0, "TH/s", 1000, 5, 0, true,
        )
        .unwrap();

        // Get workers
        let workers = db.get_workers("btc").unwrap();
        assert_eq!(workers.len(), 1);
        assert_eq!(workers[0].worker_name, "worker1");
        assert_eq!(workers[0].shares_accepted, 1000);
        assert_eq!(workers[0].shares_rejected, 5);

        // Update worker
        db.upsert_worker(
            "btc", "worker1", "1BvBMSE...", 110.0, "TH/s", 1100, 6, 0, true,
        )
        .unwrap();

        let workers = db.get_workers("btc").unwrap();
        assert_eq!(workers.len(), 1);
        assert_eq!(workers[0].hashrate, 110.0);

        // Delete worker
        let deleted = db.delete_worker("btc", "worker1").unwrap();
        assert!(deleted);

        let workers = db.get_workers("btc").unwrap();
        assert_eq!(workers.len(), 0);
    }

    #[test]
    fn test_pool_stats() {
        let db = Database::in_memory().unwrap();

        // Add workers
        db.upsert_worker("btc", "w1", "", 100.0, "TH/s", 1000, 5, 1, true).unwrap();
        db.upsert_worker("btc", "w2", "", 50.0, "TH/s", 500, 2, 0, true).unwrap();
        db.upsert_worker("btc", "w3", "", 0.0, "TH/s", 100, 1, 0, false).unwrap();

        // Update pool stats
        db.update_pool_stats("btc", 150.0, "TH/s", 1).unwrap();

        // Get pool stats
        let stats = db.get_pool_stats("btc").unwrap().unwrap();
        assert_eq!(stats.total_workers, 3);
        assert_eq!(stats.online_workers, 2);
        assert_eq!(stats.total_blocks_found, 1);
    }
}
