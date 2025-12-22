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

// Initialize dashboard
document.addEventListener('DOMContentLoaded', () => {
    initDashboard();
    fetchStats();
    setInterval(fetchStats, REFRESH_INTERVAL);
});

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

    card.innerHTML = `
        <div class="pool-card-header">
            <h2>
                <span class="pool-icon ${iconClass}">${pool.symbol.substring(0, 3)}</span>
                ${pool.name}
            </h2>
            <span class="pool-status ${statusClass}">${statusText}</span>
        </div>

        <div class="pool-stats">
            <div class="stat-item">
                <div class="stat-label">Hashrate</div>
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
                <div class="stat-label">Workers</div>
                <div class="stat-value">${stats.worker_count || 0}</div>
            </div>
        </div>

        ${stats.workers && stats.workers.length > 0 ? createWorkersSection(stats.workers) : ''}

        ${stats.stratum_url ? `
            <div class="connection-info">
                <div class="stratum-url">
                    <span>Stratum:</span> ${stats.stratum_url}:${stats.stratum_port || ''}
                </div>
            </div>
        ` : ''}
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

function createWorkersSection(workers) {
    return `
        <div class="workers-section">
            <div class="workers-header">
                <h3>Workers (${workers.length})</h3>
                <span class="workers-toggle">&#9660;</span>
            </div>
            <div class="workers-list">
                ${workers.map(worker => `
                    <div class="worker-item">
                        <div class="worker-name">
                            <span class="worker-status ${worker.is_online ? 'online' : 'offline'}"></span>
                            ${escapeHtml(worker.name)}
                        </div>
                        <div class="worker-hashrate">
                            ${formatNumber(worker.hashrate)} ${worker.hashrate_unit || 'H/s'}
                        </div>
                        <div class="worker-shares">
                            ${formatNumber(worker.shares_accepted)} accepted
                        </div>
                    </div>
                `).join('')}
            </div>
        </div>
    `;
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
