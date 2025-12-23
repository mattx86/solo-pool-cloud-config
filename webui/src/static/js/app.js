// Solo Pool Dashboard JavaScript

const POOLS = [
    { id: 'btc', name: 'Bitcoin', symbol: 'BTC', algorithm: 'SHA-256' },
    { id: 'bch', name: 'Bitcoin Cash', symbol: 'BCH', algorithm: 'SHA-256' },
    { id: 'dgb', name: 'DigiByte', symbol: 'DGB', algorithm: 'SHA-256' },
    { id: 'xmr', name: 'Monero', symbol: 'XMR', algorithm: 'RandomX' },
    { id: 'xtm', name: 'Tari', symbol: 'XTM', algorithm: 'RandomX' },
    { id: 'xmr_xtm_merge', name: 'XMR+XTM Merge', symbol: 'MERGE', algorithm: 'RandomX' },
    { id: 'aleo', name: 'Aleo', symbol: 'ALEO', algorithm: 'AleoBFT' }
];

const REFRESH_INTERVAL = 10000; // 10 seconds

let lastStats = null;

// Hidden workers management (persisted in localStorage)
const HIDDEN_WORKERS_KEY = 'solopool_hidden_workers';

function getHiddenWorkers() {
    try {
        const stored = localStorage.getItem(HIDDEN_WORKERS_KEY);
        return stored ? JSON.parse(stored) : {};
    } catch {
        return {};
    }
}

function saveHiddenWorkers(hidden) {
    try {
        localStorage.setItem(HIDDEN_WORKERS_KEY, JSON.stringify(hidden));
    } catch (e) {
        console.error('Failed to save hidden workers:', e);
    }
}

function hideWorker(poolId, workerName) {
    const hidden = getHiddenWorkers();
    if (!hidden[poolId]) {
        hidden[poolId] = [];
    }
    if (!hidden[poolId].includes(workerName)) {
        hidden[poolId].push(workerName);
    }
    saveHiddenWorkers(hidden);
}

function isWorkerHidden(poolId, workerName) {
    const hidden = getHiddenWorkers();
    return hidden[poolId] && hidden[poolId].includes(workerName);
}

function unhideWorker(poolId, workerName) {
    const hidden = getHiddenWorkers();
    if (hidden[poolId]) {
        hidden[poolId] = hidden[poolId].filter(w => w !== workerName);
        if (hidden[poolId].length === 0) {
            delete hidden[poolId];
        }
    }
    saveHiddenWorkers(hidden);
}

// Initialize dashboard
document.addEventListener('DOMContentLoaded', async () => {
    // Check authentication first
    const authenticated = await checkAuth();
    if (!authenticated) {
        window.location.href = '/login';
        return;
    }

    initDashboard();
    fetchStats();
    setInterval(fetchStats, REFRESH_INTERVAL);
});

// Check authentication status
async function checkAuth() {
    try {
        const response = await fetch('/api/auth/check');
        if (response.ok) {
            const data = await response.json();
            // Display username
            const userNameEl = document.getElementById('userName');
            const userInfoEl = document.getElementById('userInfo');
            if (userNameEl && data.username) {
                userNameEl.textContent = data.username;
                userInfoEl.style.display = 'flex';
            }
            return true;
        }
        return false;
    } catch (error) {
        console.error('Auth check failed:', error);
        return false;
    }
}

// Logout function
async function logout() {
    try {
        const response = await fetch('/api/auth/logout', {
            method: 'POST'
        });
        if (response.ok) {
            window.location.href = '/login';
        } else {
            console.error('Logout failed');
        }
    } catch (error) {
        console.error('Logout error:', error);
    }
}

function initDashboard() {
    const grid = document.getElementById('poolsGrid');
    grid.innerHTML = '<div class="loading"><div class="spinner"></div></div>';
}

async function fetchStats() {
    try {
        const response = await fetch('/api/stats');
        if (!response.ok) throw new Error('Failed to fetch stats');

        const stats = response.json ? await response.json() : JSON.parse(await response.text());
        lastStats = stats;

        updateDashboard(stats);
        updateStatus(true, stats.last_updated);
    } catch (error) {
        console.error('Error fetching stats:', error);
        updateStatus(false);
    }
}

function updateDashboard(stats) {
    const grid = document.getElementById('poolsGrid');
    grid.innerHTML = '';

    // Create cards for each pool
    POOLS.forEach(pool => {
        const poolStats = stats[pool.id];
        if (poolStats) {
            const card = createPoolCard(pool, poolStats);
            grid.appendChild(card);
        }
    });
}

function createPoolCard(pool, stats) {
    const card = document.createElement('div');
    card.className = `pool-card${!stats.enabled ? ' disabled' : ''}`;

    const iconClass = pool.id === 'xmr_xtm_merge' ? 'merge' : pool.id;
    const statusClass = !stats.enabled ? 'disabled' : (stats.online ? 'online' : 'offline');
    const statusText = !stats.enabled ? 'Disabled' : (stats.online ? 'Online' : 'Offline');
    const workerCount = stats.worker_count || 0;

    card.innerHTML = `
        <div class="pool-card-header">
            <h2>
                <span class="pool-icon ${iconClass}">${pool.symbol.substring(0, 3)}</span>
                ${pool.name}
            </h2>
            <span class="pool-status ${statusClass}">${statusText}</span>
        </div>

        <div class="pool-stats">
            <div class="stat-item stat-primary">
                <div class="stat-label">Hashrate (${workerCount} miner${workerCount !== 1 ? 's' : ''})</div>
                <div class="stat-value hashrate">
                    ${formatNumber(stats.total_hashrate)}
                    <span class="stat-unit">${stats.hashrate_unit || 'H/s'}</span>
                </div>
            </div>
            <div class="stat-item">
                <div class="stat-label">Blocks Found</div>
                <div class="stat-value">${formatNumber(stats.blocks_found)}</div>
            </div>
            <div class="stat-item">
                <div class="stat-label">Pool Fee</div>
                <div class="stat-value fee-free">${stats.pool_fee_percent === 0 ? 'Fee Free (0%)' : stats.pool_fee_percent + '%'}</div>
            </div>
        </div>

        ${stats.workers && stats.workers.length > 0 ? createWorkersSection(pool.id, stats.workers) : ''}

        ${createPoolWalletSection(pool, stats)}

        <div class="connection-info">
            <h4>Miner Connection</h4>
            <div class="connection-row">
                <span class="connection-label">Stratum URL:</span>
                <span class="connection-value copyable" onclick="copyToClipboard('${escapeHtml(stats.stratum_url)}')">${stats.stratum_url || 'N/A'}</span>
            </div>
            <div class="connection-row">
                <span class="connection-label">Username:</span>
                <span class="connection-value">${stats.username_format || 'YOUR_WALLET_ADDRESS.worker_name'}</span>
            </div>
            <div class="connection-row">
                <span class="connection-label">Password:</span>
                <span class="connection-value">${stats.password || 'x'}</span>
            </div>
        </div>
    `;

    // Add click handler for workers toggle
    const workersHeader = card.querySelector('.workers-header');
    if (workersHeader) {
        workersHeader.addEventListener('click', () => {
            const list = card.querySelector('.workers-list');
            const toggle = card.querySelector('.workers-toggle');
            list.classList.toggle('visible');
            toggle.classList.toggle('expanded');
        });
    }

    return card;
}

function createWorkersSection(poolId, workers) {
    // Filter out hidden workers
    const visibleWorkers = workers.filter(w => !isWorkerHidden(poolId, w.name));
    const hiddenCount = workers.length - visibleWorkers.length;

    if (visibleWorkers.length === 0 && hiddenCount === 0) {
        return '';
    }

    return `
        <div class="workers-section" data-pool-id="${poolId}">
            <div class="workers-header">
                <h3>Workers (${visibleWorkers.length}${hiddenCount > 0 ? ` <span class="hidden-count">+${hiddenCount} hidden</span>` : ''})</h3>
                <span class="workers-toggle">&#9660;</span>
            </div>
            <div class="workers-list">
                ${visibleWorkers.map(worker => {
                    const totalShares = worker.shares_accepted + (worker.shares_rejected || 0);
                    const acceptPct = totalShares > 0 ? ((worker.shares_accepted / totalShares) * 100).toFixed(1) : '100.0';
                    const rejectPct = totalShares > 0 ? (((worker.shares_rejected || 0) / totalShares) * 100).toFixed(1) : '0.0';
                    return `
                    <div class="worker-item ${worker.is_online ? '' : 'worker-offline'}" data-worker-name="${escapeHtml(worker.name)}">
                        <div class="worker-name">
                            <span class="worker-status ${worker.is_online ? 'online' : 'offline'}"></span>
                            ${escapeHtml(worker.name)}
                        </div>
                        <div class="worker-hashrate">
                            ${formatNumber(worker.hashrate)} ${worker.hashrate_unit || 'H/s'}
                        </div>
                        <div class="worker-shares">
                            <span class="shares-accepted">${formatNumber(worker.shares_accepted)} (${acceptPct}%)</span>
                            <span class="shares-rejected">${formatNumber(worker.shares_rejected || 0)} rej (${rejectPct}%)</span>
                        </div>
                        <div class="worker-blocks">
                            ${worker.blocks_found || 0} blocks
                        </div>
                        ${!worker.is_online ? `
                        <button class="worker-delete-btn" onclick="confirmDeleteWorker('${poolId}', '${escapeHtml(worker.name)}')" title="Delete worker from database">
                            &#10005;
                        </button>
                        ` : ''}
                    </div>
                `;}).join('')}
                ${hiddenCount > 0 ? `
                <div class="hidden-workers-info">
                    <span>${hiddenCount} worker${hiddenCount !== 1 ? 's' : ''} hidden</span>
                    <button class="restore-workers-btn" onclick="restoreHiddenWorkers('${poolId}')">Restore All</button>
                </div>
                ` : ''}
            </div>
        </div>
    `;
}

function createPoolWalletSection(pool, stats) {
    // CKPool pools (BTC, BCH, DGB) use BTCSOLO mode - miners receive rewards directly
    const ckpoolPools = ['btc', 'bch', 'dgb'];
    if (ckpoolPools.includes(pool.id)) {
        return `
            <div class="pool-wallet-info">
                <h4>Pool Wallet Address</h4>
                <div class="wallet-row">
                    <span class="wallet-label">${pool.symbol}:</span>
                    <span class="wallet-address na">Not Applicable (Direct to Miner)</span>
                </div>
            </div>
        `;
    }

    // Pools that use PPLNS and have a pool wallet
    const poolsWithWallet = ['xmr', 'xtm', 'xmr_xtm_merge', 'aleo'];
    if (!poolsWithWallet.includes(pool.id)) {
        return '';
    }

    // Check if we have any wallet addresses to display
    const hasWallet = stats.pool_wallet_address || stats.pool_wallet_address_secondary;
    if (!hasWallet) {
        return '';
    }

    // For merge mining, show both XMR and XTM addresses
    if (pool.id === 'xmr_xtm_merge') {
        return `
            <div class="pool-wallet-info">
                <h4>Pool Wallet Addresses</h4>
                ${stats.pool_wallet_address ? `
                <div class="wallet-row">
                    <span class="wallet-label">XMR:</span>
                    <span class="wallet-address copyable" onclick="copyToClipboard('${escapeHtml(stats.pool_wallet_address)}')" title="Click to copy">${truncateAddress(stats.pool_wallet_address)}</span>
                </div>
                ` : ''}
                ${stats.pool_wallet_address_secondary ? `
                <div class="wallet-row">
                    <span class="wallet-label">XTM:</span>
                    <span class="wallet-address copyable" onclick="copyToClipboard('${escapeHtml(stats.pool_wallet_address_secondary)}')" title="Click to copy">${truncateAddress(stats.pool_wallet_address_secondary)}</span>
                </div>
                ` : ''}
            </div>
        `;
    }

    // For single-coin pools (XMR, XTM, ALEO)
    const coinLabel = pool.symbol;
    return `
        <div class="pool-wallet-info">
            <h4>Pool Wallet Address</h4>
            <div class="wallet-row">
                <span class="wallet-label">${coinLabel}:</span>
                <span class="wallet-address copyable" onclick="copyToClipboard('${escapeHtml(stats.pool_wallet_address)}')" title="Click to copy">${truncateAddress(stats.pool_wallet_address)}</span>
            </div>
        </div>
    `;
}

function truncateAddress(address) {
    if (!address) return 'N/A';
    if (address.length <= 20) return address;
    return address.substring(0, 10) + '...' + address.substring(address.length - 10);
}

function updateStatus(online, lastUpdated) {
    const indicator = document.getElementById('statusIndicator');
    const lastUpdatedEl = document.getElementById('lastUpdated');

    if (online) {
        indicator.classList.add('online');
        if (lastUpdated) {
            const date = new Date(lastUpdated);
            lastUpdatedEl.textContent = `Updated: ${formatTime(date)}`;
        } else {
            lastUpdatedEl.textContent = 'Connected';
        }
    } else {
        indicator.classList.remove('online');
        lastUpdatedEl.textContent = 'Connection error';
    }
}

// Utility functions
function formatNumber(num) {
    if (num === undefined || num === null) return '0';
    if (num >= 1000000) {
        return (num / 1000000).toFixed(2) + 'M';
    } else if (num >= 1000) {
        return (num / 1000).toFixed(2) + 'K';
    }
    return num.toFixed(2);
}

function formatTime(date) {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
        // Show brief tooltip or feedback
        const tooltip = document.createElement('div');
        tooltip.className = 'copy-tooltip';
        tooltip.textContent = 'Copied!';
        document.body.appendChild(tooltip);
        setTimeout(() => tooltip.remove(), 1500);
    }).catch(err => {
        console.error('Failed to copy:', err);
    });
}

// Worker deletion confirmation dialog
function confirmDeleteWorker(poolId, workerName) {
    // Create modal overlay
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.innerHTML = `
        <div class="modal-dialog">
            <div class="modal-header">
                <h3>Delete Worker</h3>
            </div>
            <div class="modal-body">
                <p>Are you sure you want to delete <strong>${escapeHtml(workerName)}</strong> from the database?</p>
                <p class="modal-note">This worker is offline. Deleting it will permanently remove all its statistics (hashrate history, shares, blocks found) from the database. The worker will be re-added if it reconnects.</p>
            </div>
            <div class="modal-actions">
                <button class="btn-cancel" onclick="closeModal()">Cancel</button>
                <button class="btn-confirm btn-delete" onclick="executeDeleteWorker('${poolId}', '${escapeHtml(workerName)}')">Delete</button>
            </div>
        </div>
    `;
    document.body.appendChild(overlay);

    // Close on overlay click
    overlay.addEventListener('click', (e) => {
        if (e.target === overlay) closeModal();
    });

    // Close on Escape key
    document.addEventListener('keydown', handleEscapeKey);
}

function handleEscapeKey(e) {
    if (e.key === 'Escape') closeModal();
}

function closeModal() {
    const overlay = document.querySelector('.modal-overlay');
    if (overlay) {
        overlay.remove();
        document.removeEventListener('keydown', handleEscapeKey);
    }
}

async function executeDeleteWorker(poolId, workerName) {
    closeModal();

    try {
        const response = await fetch('/api/workers/' + encodeURIComponent(poolId) + '/' + encodeURIComponent(workerName), {
            method: 'DELETE'
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.error || 'Failed to delete worker');
        }

        // Show success feedback
        const tooltip = document.createElement('div');
        tooltip.className = 'copy-tooltip';
        tooltip.textContent = 'Worker deleted';
        document.body.appendChild(tooltip);
        setTimeout(() => tooltip.remove(), 1500);

        // Refresh stats from server to get updated worker list
        await fetchStats();
    } catch (error) {
        console.error('Failed to delete worker:', error);

        // Show error feedback
        const tooltip = document.createElement('div');
        tooltip.className = 'copy-tooltip error';
        tooltip.textContent = 'Delete failed: ' + error.message;
        document.body.appendChild(tooltip);
        setTimeout(() => tooltip.remove(), 3000);
    }
}

function restoreHiddenWorkers(poolId) {
    const hidden = getHiddenWorkers();
    if (hidden[poolId]) {
        delete hidden[poolId];
        saveHiddenWorkers(hidden);

        // Show success feedback
        const tooltip = document.createElement('div');
        tooltip.className = 'copy-tooltip';
        tooltip.textContent = 'Workers restored';
        document.body.appendChild(tooltip);
        setTimeout(() => tooltip.remove(), 1500);

        // Refresh dashboard
        if (lastStats) {
            updateDashboard(lastStats);
        }
    }
}
