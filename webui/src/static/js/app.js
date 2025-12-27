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

    // Apply saved collapsed state for nodes overview
    applyNodesCollapsedState();
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
    // Update node sync status overview
    updateNodesOverview(stats);

    const grid = document.getElementById('poolsGrid');
    grid.innerHTML = '';

    // Create cards for each enabled pool (skip disabled pools)
    POOLS.forEach(pool => {
        const poolStats = stats[pool.id];
        if (poolStats && poolStats.enabled) {
            const card = createPoolCard(pool, poolStats);
            grid.appendChild(card);
        }
    });

    // Show message if no pools are enabled
    if (grid.children.length === 0) {
        grid.innerHTML = `
            <div class="empty-state" style="grid-column: 1 / -1;">
                <div class="empty-state-icon">⛏️</div>
                <p>No pools are currently enabled.</p>
            </div>
        `;
    }
}

// Nodes overview collapsed state persistence
const NODES_COLLAPSED_KEY = 'solopool_nodes_collapsed';

function isNodesCollapsed() {
    return localStorage.getItem(NODES_COLLAPSED_KEY) === 'true';
}

function setNodesCollapsed(collapsed) {
    localStorage.setItem(NODES_COLLAPSED_KEY, collapsed ? 'true' : 'false');
}

function toggleNodesOverview() {
    const nodesGrid = document.getElementById('nodesGrid');
    const nodesToggle = document.getElementById('nodesToggle');
    const nodesOverview = document.getElementById('nodesOverview');

    if (!nodesGrid || !nodesToggle) return;

    const isCollapsed = nodesGrid.classList.toggle('collapsed');
    nodesToggle.classList.toggle('collapsed', isCollapsed);
    setNodesCollapsed(isCollapsed);
}

function applyNodesCollapsedState() {
    if (isNodesCollapsed()) {
        const nodesGrid = document.getElementById('nodesGrid');
        const nodesToggle = document.getElementById('nodesToggle');
        if (nodesGrid) nodesGrid.classList.add('collapsed');
        if (nodesToggle) nodesToggle.classList.add('collapsed');
    }
}

// Node status overview - shows all blockchain node sync status at a glance
function updateNodesOverview(stats) {
    const nodesGrid = document.getElementById('nodesGrid');
    const nodesOverview = document.getElementById('nodesOverview');

    if (!nodesGrid || !nodesOverview) return;

    // Collect node sync status from all enabled pools
    // Group by unique node (XMR and XMR+XTM merge share the same XMR node, etc.)
    const nodes = [];
    const seenNodes = new Set();

    POOLS.forEach(pool => {
        const poolStats = stats[pool.id];
        if (!poolStats || !poolStats.enabled) return;

        const syncStatus = poolStats.sync_status || {};

        // For merge mining, we show combined status differently
        if (pool.id === 'xmr_xtm_merge') {
            // Parse the combined status message to extract individual node info
            nodes.push({
                id: 'xmr_xtm_merge',
                name: 'XMR+XTM (Merge)',
                symbol: 'MERGE',
                syncStatus: syncStatus,
                iconClass: 'merge'
            });
        } else {
            // Skip if we've already seen this node type from merge mining
            // XMR pool and XMR+XTM merge share the same XMR node
            if (pool.id === 'xmr' && stats.xmr_xtm_merge?.enabled) {
                // Skip standalone XMR if merge mining is enabled (same node)
            } else if (pool.id === 'xtm' && stats.xmr_xtm_merge?.enabled) {
                // Skip standalone XTM if merge mining is enabled (same node)
            } else {
                nodes.push({
                    id: pool.id,
                    name: pool.name,
                    symbol: pool.symbol,
                    syncStatus: syncStatus,
                    iconClass: pool.id
                });
            }
        }
    });

    // Hide overview if no nodes
    if (nodes.length === 0) {
        nodesOverview.style.display = 'none';
        return;
    }
    nodesOverview.style.display = 'block';

    // Render node cards
    nodesGrid.innerHTML = nodes.map(node => createNodeCard(node)).join('');
}

function createNodeCard(node) {
    const syncStatus = node.syncStatus;
    const isOnline = syncStatus.node_online;
    const isSynced = syncStatus.is_synced;
    const syncPercent = syncStatus.sync_percent || 0;
    const currentHeight = syncStatus.current_height || 0;
    const targetHeight = syncStatus.target_height || currentHeight;
    const statusMessage = syncStatus.status_message || '';

    // Determine status class and display
    let statusClass, statusIcon, statusText, progressHtml;

    if (!isOnline) {
        statusClass = 'offline';
        statusIcon = '⚠';
        statusText = 'Node Offline';
        progressHtml = '';
    } else if (isSynced) {
        statusClass = 'synced';
        statusIcon = '✓';
        statusText = 'Synced';
        progressHtml = `<span class="node-height">${formatHeight(currentHeight)}</span>`;
    } else {
        statusClass = 'syncing';
        statusIcon = '';
        statusText = `Syncing ${syncPercent.toFixed(1)}%`;
        progressHtml = `
            <div class="node-progress-bar">
                <div class="node-progress-fill ${node.iconClass}" style="width: ${syncPercent}%"></div>
            </div>
            <span class="node-height">${formatHeight(currentHeight)} / ${formatHeight(targetHeight)}</span>
        `;
    }

    return `
        <div class="node-card ${statusClass}" title="${escapeHtml(statusMessage)}">
            <div class="node-card-header">
                <span class="node-icon ${node.iconClass}">${node.symbol.substring(0, 3)}</span>
                <span class="node-name">${node.name}</span>
            </div>
            <div class="node-status ${statusClass}">
                ${statusIcon ? `<span class="node-status-icon">${statusIcon}</span>` : ''}
                <span class="node-status-text">${statusText}</span>
            </div>
            ${progressHtml ? `<div class="node-progress">${progressHtml}</div>` : ''}
        </div>
    `;
}

function formatHeight(height) {
    if (height >= 1000000) {
        return (height / 1000000).toFixed(2) + 'M';
    } else if (height >= 1000) {
        return (height / 1000).toFixed(1) + 'K';
    }
    return height.toString();
}

function createSyncStatusHtml(syncStatus, iconClass) {
    if (!syncStatus || !syncStatus.node_online) {
        // Node offline - show offline indicator
        if (syncStatus && syncStatus.status_message) {
            return `<div class="sync-status offline" title="${escapeHtml(syncStatus.status_message)}">
                <span class="sync-label">Node:</span>
                <span class="sync-icon">⚠</span>
                <span class="sync-text">Offline</span>
            </div>`;
        }
        return '';
    }

    if (syncStatus.is_synced) {
        // Fully synced - show green checkmark
        return `<div class="sync-status synced" title="${escapeHtml(syncStatus.status_message || 'Synced')}">
            <span class="sync-label">Node:</span>
            <span class="sync-icon">✓</span>
            <span class="sync-text">Synced</span>
        </div>`;
    }

    // Syncing - show progress circle
    const percent = syncStatus.sync_percent || 0;
    const circumference = 2 * Math.PI * 18; // radius = 18
    const strokeDashoffset = circumference - (percent / 100) * circumference;

    return `<div class="sync-status syncing" title="${escapeHtml(syncStatus.status_message || 'Syncing...')}">
        <span class="sync-label">Node:</span>
        <svg class="sync-progress-ring" width="44" height="44">
            <circle class="sync-progress-ring-bg" cx="22" cy="22" r="18" />
            <circle class="sync-progress-ring-fill ${iconClass}" cx="22" cy="22" r="18"
                style="stroke-dasharray: ${circumference}; stroke-dashoffset: ${strokeDashoffset}" />
        </svg>
        <span class="sync-progress-text">${percent.toFixed(1)}%</span>
    </div>`;
}

function createPoolCard(pool, stats) {
    const card = document.createElement('div');
    card.className = `pool-card${!stats.enabled ? ' disabled' : ''}`;

    const iconClass = pool.id === 'xmr_xtm_merge' ? 'merge' : pool.id;
    const statusClass = !stats.enabled ? 'disabled' : (stats.online ? 'online' : 'offline');
    const statusText = !stats.enabled ? 'Disabled' : (stats.online ? 'Online' : 'Offline');
    const workerCount = stats.worker_count || 0;

    // Build sync status display
    const syncStatus = stats.sync_status || {};
    const syncHtml = createSyncStatusHtml(syncStatus, iconClass);

    card.innerHTML = `
        <div class="pool-card-header">
            <h2>
                <span class="pool-icon ${iconClass}">${pool.symbol.substring(0, 3)}</span>
                ${pool.name}
            </h2>
            <div class="pool-header-right">
                ${syncHtml}
                <div class="pool-status-wrapper">
                    <span class="pool-status-label">Pool:</span>
                    <span class="pool-status ${statusClass}">${statusText}</span>
                </div>
            </div>
        </div>

        <div class="pool-stats">
            <div class="stat-item">
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

// =============================================================================
// Tab Navigation
// =============================================================================

let currentTab = 'pools';
let paymentStats = null;
let allPayments = [];
const PAYMENTS_REFRESH_INTERVAL = 30000; // 30 seconds

function switchTab(tabName) {
    currentTab = tabName;

    // Update tab buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.tab === tabName);
    });

    // Update tab content
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.toggle('active', content.id === `tab-${tabName}`);
    });

    // Fetch payments data when switching to payments tab
    if (tabName === 'payments') {
        fetchPaymentStats();
    }
}

// =============================================================================
// Payments Tab Functions
// =============================================================================

async function fetchPaymentStats() {
    try {
        const response = await fetch('/api/payments/stats');

        if (!response.ok) {
            if (response.status === 503) {
                updatePaymentsStatus(false, 'Payment processor not available');
                showPaymentsUnavailable();
                return;
            }
            throw new Error('Failed to fetch payment stats');
        }

        paymentStats = await response.json();
        updatePaymentsStatus(true);
        renderPaymentStats(paymentStats);

        // Also fetch recent payments for each coin
        await fetchAllRecentPayments();
    } catch (error) {
        console.error('Error fetching payment stats:', error);
        updatePaymentsStatus(false, error.message);
    }
}

function showPaymentsUnavailable() {
    const grid = document.getElementById('paymentStatsGrid');
    grid.innerHTML = `
        <div class="payment-stats-card" style="grid-column: 1 / -1; text-align: center; padding: 40px;">
            <div style="font-size: 2rem; margin-bottom: 15px;">⚠️</div>
            <h3 style="margin-bottom: 10px; color: var(--text-secondary);">Payment Processor Not Available</h3>
            <p style="color: var(--text-muted);">The payment processor service is not running or not configured.
            Payment statistics will appear here once the service is available.</p>
        </div>
    `;

    const tableBody = document.getElementById('paymentsTableBody');
    tableBody.innerHTML = '<tr><td colspan="6" class="no-data">No payments data available</td></tr>';
}

function updatePaymentsStatus(online, message) {
    const indicator = document.getElementById('paymentsStatusIndicator');
    const statusText = document.querySelector('.payments-status .status-text');

    if (online) {
        indicator.classList.add('online');
        statusText.textContent = 'Connected';
    } else {
        indicator.classList.remove('online');
        statusText.textContent = message || 'Disconnected';
    }
}

function renderPaymentStats(stats) {
    const grid = document.getElementById('paymentStatsGrid');
    grid.innerHTML = '';

    const coins = [
        { id: 'xmr', name: 'Monero', symbol: 'XMR' },
        { id: 'xtm', name: 'Tari', symbol: 'XTM' },
        { id: 'aleo', name: 'Aleo', symbol: 'ALEO' }
    ];

    coins.forEach(coin => {
        const coinStats = stats[coin.id];
        if (coinStats) {
            const card = createPaymentStatsCard(coin, coinStats);
            grid.appendChild(card);
        }
    });

    // If no coins have stats, show a message
    if (grid.children.length === 0) {
        grid.innerHTML = `
            <div class="payment-stats-card" style="grid-column: 1 / -1; text-align: center; padding: 40px;">
                <p style="color: var(--text-muted);">No payment statistics available yet.
                Stats will appear once miners start submitting shares.</p>
            </div>
        `;
    }
}

function createPaymentStatsCard(coin, stats) {
    const card = document.createElement('div');
    card.className = 'payment-stats-card';

    card.innerHTML = `
        <div class="payment-stats-card-header">
            <div class="coin-icon ${coin.id}">${coin.symbol}</div>
            <h3>${coin.name}</h3>
        </div>
        <div class="payment-stats-row">
            <span class="payment-stats-label">Total Miners</span>
            <span class="payment-stats-value highlight">${stats.total_miners}</span>
        </div>
        <div class="payment-stats-row">
            <span class="payment-stats-label">Pending Balance</span>
            <span class="payment-stats-value">${formatCoinAmount(stats.total_pending, coin.id)}</span>
        </div>
        <div class="payment-stats-row">
            <span class="payment-stats-label">Total Paid</span>
            <span class="payment-stats-value">${formatCoinAmount(stats.total_paid, coin.id)}</span>
        </div>
        <div class="payment-stats-row">
            <span class="payment-stats-label">Pending Payments</span>
            <span class="payment-stats-value">${stats.pending_payments}</span>
        </div>
    `;

    return card;
}

function formatCoinAmount(amount, coin) {
    const num = parseFloat(amount);
    if (isNaN(num)) return '0';

    // Different decimal places for different coins
    const decimals = {
        'xmr': 12,
        'xtm': 6,
        'aleo': 6
    };

    const dec = decimals[coin] || 8;
    return num.toFixed(Math.min(dec, 8));
}

async function fetchAllRecentPayments() {
    allPayments = [];
    const coins = ['xmr', 'xtm', 'aleo'];

    try {
        const promises = coins.map(coin =>
            fetch(`/api/payments/coin/${coin}?limit=20`)
                .then(r => r.ok ? r.json() : [])
                .catch(() => [])
        );

        const results = await Promise.all(promises);

        results.forEach((payments, index) => {
            payments.forEach(p => {
                p.coin = coins[index]; // Ensure coin is set
            });
            allPayments.push(...payments);
        });

        // Sort by date, newest first
        allPayments.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

        renderPaymentsTable(allPayments);
    } catch (error) {
        console.error('Error fetching recent payments:', error);
    }
}

function filterPayments() {
    const filter = document.getElementById('paymentsCoinFilter').value;

    if (filter === 'all') {
        renderPaymentsTable(allPayments);
    } else {
        const filtered = allPayments.filter(p => p.coin.toLowerCase() === filter);
        renderPaymentsTable(filtered);
    }
}

function renderPaymentsTable(payments) {
    const tbody = document.getElementById('paymentsTableBody');

    if (!payments || payments.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="no-data">No payments found</td></tr>';
        return;
    }

    tbody.innerHTML = payments.slice(0, 50).map(payment => `
        <tr>
            <td><span class="coin-badge ${payment.coin.toLowerCase()}">${payment.coin.toUpperCase()}</span></td>
            <td class="address-cell" title="${escapeHtml(payment.wallet_address)}">${truncateAddress(payment.wallet_address)}</td>
            <td class="amount-cell">${formatCoinAmount(payment.amount, payment.coin)}</td>
            <td><span class="status-badge ${payment.status}">${payment.status}</span></td>
            <td>${payment.tx_hash ? `<span class="tx-hash" onclick="copyToClipboard('${escapeHtml(payment.tx_hash)}')" title="${escapeHtml(payment.tx_hash)}">${truncateTxHash(payment.tx_hash)}</span>` : '-'}</td>
            <td class="date-cell">${formatDate(payment.created_at)}</td>
        </tr>
    `).join('');
}

function truncateTxHash(hash) {
    if (!hash) return '-';
    if (hash.length <= 16) return hash;
    return hash.substring(0, 8) + '...' + hash.substring(hash.length - 8);
}

function formatDate(dateString) {
    if (!dateString) return '-';
    const date = new Date(dateString);
    return date.toLocaleString([], {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

// =============================================================================
// Miner Lookup
// =============================================================================

async function lookupMiner() {
    const coin = document.getElementById('minerCoin').value;
    const address = document.getElementById('minerAddress').value.trim();

    if (!address) {
        showTooltip('Please enter a wallet address', true);
        return;
    }

    const container = document.getElementById('minerInfoContainer');
    container.style.display = 'block';
    container.innerHTML = '<div class="loading"><div class="spinner"></div></div>';

    try {
        const response = await fetch(`/api/payments/miner/${coin}/${encodeURIComponent(address)}`);

        if (!response.ok) {
            throw new Error('Miner not found');
        }

        const minerInfo = await response.json();
        renderMinerInfo(minerInfo);
    } catch (error) {
        container.innerHTML = `
            <div style="text-align: center; padding: 30px; color: var(--text-muted);">
                <p>No data found for this address.</p>
                <p style="font-size: 0.85rem; margin-top: 10px;">The miner may not have submitted any shares yet.</p>
            </div>
        `;
    }
}

function renderMinerInfo(info) {
    const container = document.getElementById('minerInfoContainer');

    const coinSymbol = info.coin.toUpperCase();

    container.innerHTML = `
        <div class="miner-info-header">
            <h4><span class="coin-badge ${info.coin}">${coinSymbol}</span> Miner Statistics</h4>
            <span class="miner-info-address">${truncateAddress(info.wallet_address)}</span>
        </div>

        <div class="miner-info-grid">
            <div class="miner-info-item">
                <div class="miner-info-label">Pending Balance</div>
                <div class="miner-info-value highlight">${formatCoinAmount(info.pending_balance, info.coin)} ${coinSymbol}</div>
            </div>
            <div class="miner-info-item">
                <div class="miner-info-label">Total Paid</div>
                <div class="miner-info-value">${formatCoinAmount(info.total_paid, info.coin)} ${coinSymbol}</div>
            </div>
            <div class="miner-info-item">
                <div class="miner-info-label">Total Shares</div>
                <div class="miner-info-value">${formatNumber(info.total_shares)}</div>
            </div>
            <div class="miner-info-item">
                <div class="miner-info-label">Last Share</div>
                <div class="miner-info-value" style="font-size: 0.9rem;">${info.last_share ? formatDate(info.last_share) : 'Never'}</div>
            </div>
        </div>

        ${info.recent_payments && info.recent_payments.length > 0 ? `
            <div class="miner-payments-list">
                <h5>Recent Payments</h5>
                ${info.recent_payments.map(p => `
                    <div class="miner-payment-item">
                        <span class="miner-payment-amount">${formatCoinAmount(p.amount, info.coin)} ${coinSymbol}</span>
                        <span class="status-badge ${p.status}">${p.status}</span>
                        <span class="miner-payment-date">${formatDate(p.created_at)}</span>
                    </div>
                `).join('')}
            </div>
        ` : `
            <div style="text-align: center; padding: 20px; color: var(--text-muted);">
                <p>No payments yet</p>
            </div>
        `}
    `;
}

function showTooltip(message, isError = false) {
    const tooltip = document.createElement('div');
    tooltip.className = 'copy-tooltip' + (isError ? ' error' : '');
    tooltip.textContent = message;
    document.body.appendChild(tooltip);
    setTimeout(() => tooltip.remove(), isError ? 3000 : 1500);
}

// Start payments refresh when on payments tab
setInterval(() => {
    if (currentTab === 'payments') {
        fetchPaymentStats();
    }
}, PAYMENTS_REFRESH_INTERVAL);
