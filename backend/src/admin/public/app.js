import { renderQrSvgElement } from './qr.js';

const state = {
    session: null,
    overview: null,
    tree: [],
    items: [],
    selectedContainerId: null,
    selectedQrIds: new Set(),
    qrInitialized: false,
    ollama: null,
    settingsData: null,
    tokens: [],
};

// ---- DOM Helpers (XSS-safe: always textContent, never unsanitized innerHTML) ----

const $ = (selector) => document.querySelector(selector);

function el(tag, props = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
        if (value === undefined || value === null) continue;
        if (key === 'className') {
            node.className = value;
        } else if (key === 'style' && typeof value === 'object') {
            Object.assign(node.style, value);
        } else if (key.startsWith('on') && typeof value === 'function') {
            node.addEventListener(key.slice(2).toLowerCase(), value);
        } else {
            node.setAttribute(key, String(value));
        }
    }
    for (const child of children.flat()) {
        if (child === undefined || child === null) continue;
        node.appendChild(
            typeof child === 'string' || typeof child === 'number'
                ? document.createTextNode(String(child))
                : child,
        );
    }
    return node;
}

let toastTimer;
let pendingToast = null;

function isAnyModalOpen() {
    return Boolean(document.querySelector('dialog[open]'));
}

function hideToast() {
    const toast = $('#toast');
    clearTimeout(toastTimer);
    if (typeof toast.hidePopover === 'function') {
        try {
            if (toast.matches(':popover-open')) toast.hidePopover();
        } catch {
            toast.classList.remove(':popover-open');
        }
    } else {
        toast.classList.remove(':popover-open');
    }
}

function showToast(message, tone = 'info') {
    // Do not surface background toasts while a modal dialog makes the page inert
    if (isAnyModalOpen()) {
        pendingToast = { message, tone };
        return;
    }

    const toast = $('#toast');
    const msgEl = $('#toast-message');
    const live = $('#toast-live');

    msgEl.textContent = message;
    toast.dataset.tone = tone;

    if (typeof toast.showPopover === 'function') {
        try {
            if (!toast.matches(':popover-open')) toast.showPopover();
        } catch {
            toast.classList.add(':popover-open');
        }
    } else {
        toast.classList.add(':popover-open');
    }

    if (typeof document.ariaNotify === 'function') {
        document.ariaNotify(message);
    } else if (live) {
        live.textContent = '';
        requestAnimationFrame(() => {
            live.textContent = message;
        });
    }

    clearTimeout(toastTimer);
    const scheduleDismiss = () => {
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => {
            if (toast.contains(document.activeElement)) {
                scheduleDismiss();
                return;
            }
            hideToast();
        }, 4200);
    };
    scheduleDismiss();
}

function setupModalLightDismiss(dialog) {
    // Fallback for browsers without native <dialog closedby="any"> (e.g. Safari)
    if (!('closedBy' in HTMLDialogElement.prototype)) {
        dialog.addEventListener('click', (event) => {
            if (event.target !== dialog) return;
            const rect = dialog.getBoundingClientRect();
            const insideContent =
                rect.top <= event.clientY &&
                event.clientY <= rect.top + rect.height &&
                rect.left <= event.clientX &&
                event.clientX <= rect.left + rect.width;
            if (!insideContent) {
                dialog.close();
            }
        });
    }
    // Flush any toast deferred while the modal was open
    dialog.addEventListener('close', () => {
        if (pendingToast && !isAnyModalOpen()) {
            const next = pendingToast;
            pendingToast = null;
            showToast(next.message, next.tone);
        }
    });
}

async function apiFetch(path, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (options.body && typeof options.body === 'string' && !headers['Content-Type']) {
        headers['Content-Type'] = 'application/json';
    }
    const response = await fetch(path, {
        credentials: 'same-origin',
        ...options,
        headers,
    });
    if (response.status === 204) return null;
    const isJson = (response.headers.get('content-type') || '').includes('application/json');
    const data = isJson ? await response.json() : await response.text();
    if (!response.ok) {
        const msg =
            (typeof data === 'object' && data && data.error) ||
            `Errore HTTP ${response.status}`;
        const err = new Error(msg);
        err.status = response.status;
        throw err;
    }
    return data;
}

function formatBytes(bytes) {
    if (!bytes) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    let value = bytes;
    let idx = 0;
    while (value >= 1024 && idx < units.length - 1) {
        value /= 1024;
        idx++;
    }
    return `${value.toFixed(idx === 0 ? 0 : 1)} ${units[idx]}`;
}

function formatDate(iso) {
    if (!iso) return '—';
    try {
        return new Date(iso).toLocaleString('it-IT', {
            dateStyle: 'short',
            timeStyle: 'short',
        });
    } catch {
        return iso;
    }
}

function flattenContainers() {
    const list = [];
    for (const house of state.tree) {
        for (const room of house.rooms || []) {
            for (const container of room.containers || []) {
                list.push({
                    ...container,
                    roomName: room.name,
                    houseId: house.id,
                    houseName: house.name,
                });
            }
        }
    }
    return list;
}

// ---- Theme Switcher (Light: Indaco & Grafite / Dark: Notte & Ambra) ----

const THEME_STORAGE_KEY = 'hs_theme';

function getStoredTheme() {
    try {
        const stored = window.localStorage.getItem(THEME_STORAGE_KEY);
        return stored === 'light' || stored === 'dark' ? stored : null;
    } catch {
        return null;
    }
}

function getPreferredTheme() {
    const stored = getStoredTheme();
    if (stored) return stored;
    return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function applyTheme(theme) {
    const resolved = theme === 'dark' ? 'dark' : 'light';
    document.documentElement.dataset.theme = resolved;
    const btn = $('#theme-toggle');
    const icon = $('#theme-toggle-icon');
    const label = $('#theme-toggle-label');
    if (btn) {
        const isDark = resolved === 'dark';
        btn.setAttribute('aria-pressed', String(isDark));
        btn.setAttribute(
            'aria-label',
            isDark
                ? 'Passa al tema chiaro (Indaco e Grafite)'
                : 'Passa al tema scuro (Notte e Ambra)',
        );
        if (icon) icon.textContent = isDark ? '☀️' : '🌙';
        if (label) label.textContent = isDark ? 'Chiaro' : 'Scuro';
    }
}

function initTheme() {
    applyTheme(getPreferredTheme());
    const btn = $('#theme-toggle');
    if (btn) {
        btn.addEventListener('click', () => {
            const current =
                document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
            const next = current === 'dark' ? 'light' : 'dark';
            try {
                window.localStorage.setItem(THEME_STORAGE_KEY, next);
            } catch {
                // Ignore storage quota / privacy mode errors
            }
            applyTheme(next);
        });
    }
    const media = window.matchMedia?.('(prefers-color-scheme: dark)');
    if (media && typeof media.addEventListener === 'function') {
        media.addEventListener('change', (event) => {
            if (!getStoredTheme()) {
                applyTheme(event.matches ? 'dark' : 'light');
            }
        });
    }
}

// ---- Boot & Authentication ----

async function boot() {
    initTheme();
    bindTabs();
    bindForms();
    document.querySelectorAll('dialog').forEach(setupModalLightDismiss);
    $('#toast-close').addEventListener('click', () => hideToast());
    renderApiSnippet();

    const params = new URLSearchParams(window.location.search);
    const authError = params.get('authError');
    if (authError) {
        const messages = {
            unauthorized_email: 'Questa email Google non è autorizzata (controlla AUTH_ALLOWED_EMAILS).',
            invalid_state: 'Sessione OAuth scaduta o non valida. Riprova.',
            token_exchange: 'Impossibile completare il login con Google.',
            userinfo_failed: 'Impossibile verificare il profilo Google.',
            google_disabled: 'Google OAuth non è abilitato sul server.',
            oauth_error: 'Errore di rete durante il login Google.',
        };
        const errBox = $('#login-error');
        errBox.textContent = messages[authError] || `Errore login (${authError})`;
        errBox.hidden = false;
        window.history.replaceState({}, '', '/admin');
    }

    try {
        const [config, session] = await Promise.all([
            apiFetch('/api/auth/config'),
            apiFetch('/api/auth/session'),
        ]);
        state.session = session;
        if (session.authenticated && session.role === 'admin') {
            showConsole(session);
            await refreshAll();
        } else {
            showLogin(config);
        }
    } catch (error) {
        showToast(error.message, 'error');
    }
}

function showLogin(config) {
    $('#console-shell').hidden = true;
    $('#login-view').hidden = false;
    $('#session-pill').hidden = true;
    $('#logout-btn').hidden = true;

    $('#google-login-wrap').hidden = !config.methods.google;
    $('#password-login-form').hidden = !config.methods.password;
    $('#cf-hint').hidden = !config.methods.cloudflare;
}

function showConsole(session) {
    $('#login-view').hidden = true;
    $('#console-shell').hidden = false;

    const pill = $('#session-pill');
    const methodLabels = {
        cloudflare: 'Cloudflare',
        google: 'Google',
        password: 'Admin',
        open: 'Locale (senza auth)',
        'master-token': 'API Master',
    };
    pill.textContent = `${session.subject} · ${methodLabels[session.method] || session.method}`;
    pill.hidden = false;
    $('#logout-btn').hidden = !session.authEnabled || session.method === 'cloudflare';
}

// ---- Tabs (modern-web-guidance: tabs with focusgroup + roving tabindex fallback + until-found) ----

function bindTabs() {
    const buttons = Array.from(document.querySelectorAll('.tab-btn'));
    const panels = Array.from(document.querySelectorAll('main .panel-host'));

    const activateTab = (targetBtn, { moveFocus = false } = {}) => {
        const target = targetBtn.dataset.tab;
        buttons.forEach((btn) => {
            const selected = btn === targetBtn;
            btn.setAttribute('aria-selected', String(selected));
            btn.toggleAttribute('focusgroupstart', selected);
            btn.tabIndex = selected ? 0 : -1;
        });
        panels.forEach((panel) => {
            const match = panel.id === `tab-${target}`;
            if (match) {
                panel.removeAttribute('hidden');
            } else {
                panel.setAttribute('hidden', 'until-found');
            }
        });
        targetBtn.scrollIntoView({
            block: 'nearest',
            inline: 'nearest',
            container: 'nearest',
        });
        if (moveFocus) targetBtn.focus();
        if (target === 'qr') renderQrTab();
    };

    buttons.forEach((btn, index) => {
        btn.addEventListener('click', () => activateTab(btn));

        // Keyboard fallback when native focusgroup is unavailable (Firefox/Safari)
        btn.addEventListener('keydown', (event) => {
            let nextIndex = -1;
            if (event.key === 'ArrowRight') nextIndex = (index + 1) % buttons.length;
            else if (event.key === 'ArrowLeft')
                nextIndex = (index - 1 + buttons.length) % buttons.length;
            else if (event.key === 'Home') nextIndex = 0;
            else if (event.key === 'End') nextIndex = buttons.length - 1;
            if (nextIndex !== -1) {
                event.preventDefault();
                activateTab(buttons[nextIndex], { moveFocus: true });
            }
        });
    });

    // Sync active tab when browser find-in-page reveals a hidden="until-found" panel
    panels.forEach((panel) => {
        panel.addEventListener('beforematch', () => {
            const tabKey = panel.id.replace(/^tab-/, '');
            const matchingBtn = buttons.find((b) => b.dataset.tab === tabKey);
            if (matchingBtn) activateTab(matchingBtn);
        });
    });
}

// ---- Data Loading ----

async function refreshAll() {
    await Promise.all([
        loadOverview(),
        loadOllama(),
        loadInventoryData(),
        loadSettings(),
        loadTokens(),
    ]);
}

async function loadOverview() {
    const data = await apiFetch('/api/admin/overview');
    state.overview = data;
    renderOverview();
}

async function loadOllama() {
    try {
        state.ollama = await apiFetch('/api/admin/ollama/models');
    } catch (error) {
        state.ollama = { online: false, baseUrl: '', models: [], error: error.message };
    }
    renderVisionStatus();
    populateOllamaDatalist();
}

async function loadInventoryData() {
    const [treeData, itemsData] = await Promise.all([
        apiFetch('/api/admin/tree'),
        apiFetch('/api/admin/items'),
    ]);
    state.tree = treeData.houses || [];
    state.items = itemsData.items || [];
    renderSpaceTree();
    renderCategoryFilter();
    renderItemsTable();
    renderQrTab();
}

async function loadSettings() {
    const data = await apiFetch('/api/admin/settings');
    state.settingsData = data;
    $('#setting-primary').value = data.settings.primaryProvider || '';
    $('#setting-fallback').value = data.settings.fallbackProvider || '';
    $('#setting-ollama-model').value = data.settings.ollamaModel || '';
    $('#setting-cloud-timeout').value = data.settings.cloudTimeoutMs || '';
    $('#setting-ollama-timeout').value = data.settings.ollamaTimeoutMs || '';
    $('#setting-prompt').value = data.settings.promptTemplate || '';
    $('#setting-prompt').placeholder = data.defaultPrompt || '';
}

async function loadTokens() {
    const data = await apiFetch('/api/admin/tokens');
    state.tokens = data.tokens || [];
    renderTokensTable();
}

// ---- Rendering: Overview ----

function renderOverview() {
    const data = state.overview;
    if (!data) return;
    const { stats, scanLogs } = data;

    const kpis = [
        ['Case', stats.houses],
        ['Stanze', stats.rooms],
        ['Contenitori', stats.containers],
        ['Oggetti unici', stats.distinctItems],
        ['Totale pezzi', stats.totalQuantity],
        ['Database SQLite', formatBytes(stats.dbSizeBytes)],
    ];

    const grid = $('#kpi-grid');
    grid.replaceChildren(
        ...kpis.map(([label, value]) =>
            el(
                'div',
                { className: 'kpi-card' },
                el('div', { className: 'kpi-label' }, label),
                el('div', { className: 'kpi-value' }, value),
            ),
        ),
    );

    renderVisionStatus();

    const tbody = $('#scan-logs-body');
    if (!scanLogs.length) {
        tbody.replaceChildren(
            el(
                'tr',
                {},
                el(
                    'td',
                    { colspan: '6', className: 'help-text' },
                    'Nessuna scansione AI registrata finora.',
                ),
            ),
        );
        return;
    }

    tbody.replaceChildren(
        ...scanLogs.map((log) =>
            el(
                'tr',
                {},
                el('td', {}, formatDate(log.createdAt)),
                el('td', {}, log.provider),
                el(
                    'td',
                    {},
                    log.usedFallback
                        ? el('span', { className: 'badge badge-warn' }, 'Fallback')
                        : el('span', { className: 'badge badge-neutral' }, 'Primario'),
                ),
                el('td', {}, `${log.latencyMs} ms`),
                el('td', {}, String(log.itemsCount)),
                el(
                    'td',
                    {},
                    log.status === 'ok'
                        ? el('span', { className: 'badge badge-ok' }, 'OK')
                        : el(
                              'span',
                              { className: 'badge badge-danger' },
                              log.errorCode || 'Errore',
                          ),
                ),
            ),
        ),
    );
}

function renderVisionStatus() {
    const container = $('#vision-status-body');
    const rec = state.overview?.recognition;
    const ollama = state.ollama;
    const children = [];

    if (rec) {
        children.push(
            el(
                'div',
                { className: 'row-inline', style: { marginBottom: '0.75rem' } },
                el(
                    'span',
                    {
                        className: rec.available
                            ? 'badge badge-ok'
                            : 'badge badge-danger',
                    },
                    rec.available ? 'AI attiva' : 'Nessun provider configurato',
                ),
                el(
                    'span',
                    { className: 'help-text' },
                    rec.providers.length
                        ? `Catena: ${rec.providers.join(' → ')}`
                        : 'Configura GITHUB_MODELS_TOKEN, ANTHROPIC_API_KEY o OLLAMA_BASE_URL.',
                ),
            ),
        );
    }

    if (ollama) {
        children.push(
            el(
                'div',
                { className: 'row-inline', style: { marginBottom: '0.5rem' } },
                el(
                    'span',
                    {
                        className: ollama.online
                            ? 'badge badge-ok'
                            : 'badge badge-warn',
                    },
                    ollama.online ? 'Ollama online' : 'Ollama non raggiungibile',
                ),
                el('span', { className: 'help-text' }, ollama.baseUrl || ''),
            ),
        );

        if (ollama.online && ollama.models.length > 0) {
            children.push(
                el(
                    'div',
                    { className: 'row-inline' },
                    ...ollama.models.map((m) =>
                        el(
                            'span',
                            { className: 'badge badge-neutral' },
                            `${m.name} (${formatBytes(m.size)})`,
                        ),
                    ),
                ),
            );
        } else if (ollama.online) {
            children.push(
                el(
                    'p',
                    { className: 'help-text' },
                    'Ollama raggiungibile ma nessun modello installato (esegui: ollama pull qwen2.5vl:3b).',
                ),
            );
        } else if (ollama.error) {
            children.push(el('p', { className: 'help-text' }, ollama.error));
        }
    }

    container.replaceChildren(...children);
}

function populateOllamaDatalist() {
    const datalist = $('#ollama-models-datalist');
    const models = state.ollama?.models || [];
    datalist.replaceChildren(
        ...models.map((m) => el('option', { value: m.name })),
    );
}

// ---- Rendering: Spaces Tree & Items Table ----

function renderSpaceTree() {
    const treeRoot = $('#space-tree');
    if (!state.tree.length) {
        treeRoot.replaceChildren(
            el('p', { className: 'help-text' }, 'Nessuna casa ancora configurata.'),
        );
        return;
    }

    treeRoot.replaceChildren(
        ...state.tree.map((house) => {
            const roomNodes = (house.rooms || []).map((room) => {
                const containerNodes = (room.containers || []).map((c) => {
                    const isSelected = state.selectedContainerId === c.id;
                    return el(
                        'div',
                        { className: 'row-inline' },
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'tree-container-btn',
                                style: { flex: '1' },
                                'aria-pressed': String(isSelected),
                                onClick: () => {
                                    state.selectedContainerId = isSelected ? null : c.id;
                                    renderSpaceTree();
                                    renderItemsTable();
                                },
                            },
                            el('span', {}, `${c.name} (${c.type})`),
                            el(
                                'span',
                                { className: 'badge badge-neutral' },
                                `${c.itemCount} · x${c.totalQuantity}`,
                            ),
                        ),
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'btn btn-sm',
                                'aria-label': `Modifica contenitore ${c.name}`,
                                onClick: () => openSpaceDialog('container', c, room.id),
                            },
                            '✎',
                        ),
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'btn btn-danger btn-sm',
                                'aria-label': `Elimina contenitore ${c.name}`,
                                onClick: () =>
                                    deleteSpace(
                                        'containers',
                                        c.id,
                                        `contenitore "${c.name}" (${c.itemCount} oggetti)`,
                                    ),
                            },
                            '✕',
                        ),
                    );
                });

                return el(
                    'div',
                    {},
                    el(
                        'div',
                        { className: 'tree-row' },
                        el('strong', { style: { fontSize: '0.92rem' } }, room.name),
                        el(
                            'div',
                            { className: 'row-inline' },
                            el(
                                'button',
                                {
                                    type: 'button',
                                    className: 'btn btn-sm',
                                    onClick: () => openSpaceDialog('container', null, room.id),
                                },
                                '+ Box',
                            ),
                            el(
                                'button',
                                {
                                    type: 'button',
                                    className: 'btn btn-sm',
                                    'aria-label': `Rinomina stanza ${room.name}`,
                                    onClick: () => openSpaceDialog('room', room, house.id),
                                },
                                '✎',
                            ),
                            el(
                                'button',
                                {
                                    type: 'button',
                                    className: 'btn btn-danger btn-sm',
                                    'aria-label': `Elimina stanza ${room.name}`,
                                    onClick: () =>
                                        deleteSpace('rooms', room.id, `stanza "${room.name}"`),
                                },
                                '✕',
                            ),
                        ),
                    ),
                    el('div', { className: 'tree-containers' }, ...containerNodes),
                );
            });

            return el(
                'div',
                { className: 'tree-house' },
                el(
                    'div',
                    { className: 'tree-row' },
                    el('strong', {}, house.name),
                    el(
                        'div',
                        { className: 'row-inline' },
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'btn btn-sm',
                                onClick: () => openSpaceDialog('room', null, house.id),
                            },
                            '+ Stanza',
                        ),
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'btn btn-sm',
                                'aria-label': `Rinomina casa ${house.name}`,
                                onClick: () => openSpaceDialog('house', house, null),
                            },
                            '✎',
                        ),
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'btn btn-danger btn-sm',
                                'aria-label': `Elimina casa ${house.name}`,
                                onClick: () =>
                                    deleteSpace('houses', house.id, `casa "${house.name}"`),
                            },
                            '✕',
                        ),
                    ),
                ),
                el('div', { className: 'tree-rooms' }, ...roomNodes),
            );
        }),
    );
}

function renderCategoryFilter() {
    const select = $('#inventory-category-filter');
    const current = select.value;
    const categories = [...new Set(state.items.map((i) => i.category))].sort((a, b) =>
        a.localeCompare(b, 'it'),
    );
    select.replaceChildren(
        el('option', { value: '' }, 'Tutte le categorie'),
        ...categories.map((cat) => el('option', { value: cat }, cat)),
    );
    select.value = categories.includes(current) ? current : '';
}

function renderItemsTable() {
    const query = ($('#inventory-search').value || '').trim().toLowerCase();
    const category = $('#inventory-category-filter').value;
    const containers = flattenContainers();
    const selectedContainer = containers.find((c) => c.id === state.selectedContainerId);

    $('#items-heading').textContent = selectedContainer
        ? `${selectedContainer.houseName} › ${selectedContainer.roomName} › ${selectedContainer.name}`
        : 'Tutti gli oggetti';

    const filtered = state.items.filter((item) => {
        if (state.selectedContainerId && item.containerId !== state.selectedContainerId) {
            return false;
        }
        if (category && item.category !== category) {
            return false;
        }
        if (!query) return true;
        const haystack = [
            item.name,
            item.category,
            item.shortDescription,
            item.notes,
            item.houseName,
            item.roomName,
            item.containerName,
        ]
            .join(' ')
            .toLowerCase();
        return haystack.includes(query);
    });

    const tbody = $('#items-table-body');
    if (!filtered.length) {
        tbody.replaceChildren(
            el(
                'tr',
                {},
                el(
                    'td',
                    { colspan: '5', className: 'help-text' },
                    'Nessun oggetto trovato con i filtri attuali.',
                ),
            ),
        );
        return;
    }

    tbody.replaceChildren(
        ...filtered.map((item) =>
            el(
                'tr',
                {},
                el(
                    'td',
                    {},
                    el('strong', {}, item.name),
                    item.shortDescription
                        ? el('div', { className: 'help-text' }, item.shortDescription)
                        : null,
                    item.notes
                        ? el('div', { className: 'help-text' }, `Note: ${item.notes}`)
                        : null,
                ),
                el('td', {}, el('span', { className: 'badge badge-neutral' }, item.category)),
                el(
                    'td',
                    {},
                    `${item.houseName} › ${item.roomName} › ${item.containerName}`,
                ),
                el(
                    'td',
                    {},
                    el(
                        'div',
                        { className: 'qty-control' },
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'qty-btn',
                                'aria-label': `Diminuisci quantità di ${item.name}`,
                                onClick: () => updateItemQty(item, -1),
                            },
                            '−',
                        ),
                        el('strong', {}, String(item.quantity)),
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'qty-btn',
                                'aria-label': `Aumenta quantità di ${item.name}`,
                                onClick: () => updateItemQty(item, 1),
                            },
                            '+',
                        ),
                    ),
                ),
                el(
                    'td',
                    {},
                    el(
                        'div',
                        { className: 'row-inline' },
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'btn btn-sm',
                                onClick: () => openItemDialog(item),
                            },
                            'Modifica',
                        ),
                        el(
                            'button',
                            {
                                type: 'button',
                                className: 'btn btn-danger btn-sm',
                                onClick: () => deleteItem(item),
                            },
                            'Elimina',
                        ),
                    ),
                ),
            ),
        ),
    );
}

async function updateItemQty(item, delta) {
    const nextQty = item.quantity + delta;
    if (nextQty <= 0) {
        await deleteItem(item);
        return;
    }
    try {
        await apiFetch(`/api/items/${item.id}`, {
            method: 'PATCH',
            body: JSON.stringify({ quantity: nextQty }),
        });
        await Promise.all([loadInventoryData(), loadOverview()]);
    } catch (error) {
        showToast(error.message, 'error');
    }
}

async function deleteItem(item) {
    const confirmed = await confirmAction({
        title: 'Elimina oggetto',
        message: `Eliminare "${item.name}" dall'inventario?`,
        confirmLabel: 'Elimina',
    });
    if (!confirmed) return;
    try {
        await apiFetch(`/api/items/${item.id}`, { method: 'DELETE' });
        showToast('Oggetto eliminato.', 'ok');
        await Promise.all([loadInventoryData(), loadOverview()]);
    } catch (error) {
        showToast(error.message, 'error');
    }
}

async function deleteSpace(resource, id, label) {
    const confirmed = await confirmAction({
        title: 'Conferma eliminazione',
        message: `Eliminare ${label}? Verranno eliminati in cascata anche tutti gli elementi contenuti.`,
        confirmLabel: 'Elimina',
    });
    if (!confirmed) {
        return;
    }
    try {
        await apiFetch(`/api/${resource}/${id}`, { method: 'DELETE' });
        if (resource === 'containers' && state.selectedContainerId === id) {
            state.selectedContainerId = null;
        }
        showToast('Spazio eliminato.', 'ok');
        await Promise.all([loadInventoryData(), loadOverview()]);
    } catch (error) {
        showToast(error.message, 'error');
    }
}

// ---- Dialogs ----

function openItemDialog(item) {
    const containers = flattenContainers();
    if (!containers.length) {
        showToast('Crea prima almeno una casa, una stanza e un contenitore.', 'error');
        return;
    }

    const select = $('#item-container');
    select.replaceChildren(
        ...containers.map((c) =>
            el(
                'option',
                { value: c.id },
                `${c.houseName} › ${c.roomName} › ${c.name} (${c.type})`,
            ),
        ),
    );

    $('#item-dialog-title').textContent = item ? 'Modifica oggetto' : 'Nuovo oggetto';
    $('#item-id').value = item ? String(item.id) : '';
    $('#item-name').value = item ? item.name : '';
    $('#item-category').value = item ? item.category : '';
    $('#item-quantity').value = item ? String(item.quantity) : '1';
    $('#item-container').value = item
        ? String(item.containerId)
        : String(state.selectedContainerId || containers[0].id);
    $('#item-desc').value = item ? item.shortDescription : '';
    $('#item-notes').value = item ? item.notes || '' : '';

    $('#item-dialog').showModal();
}

function openSpaceDialog(kind, record, parentId) {
    const titles = {
        house: record ? 'Rinomina casa' : 'Nuova casa',
        room: record ? 'Rinomina stanza' : 'Nuova stanza',
        container: record ? 'Modifica contenitore' : 'Nuovo contenitore',
    };
    $('#space-dialog-title').textContent = titles[kind];
    $('#space-kind').value = kind;
    $('#space-id').value = record ? String(record.id) : '';
    $('#space-parent-id').value = parentId ? String(parentId) : '';
    $('#space-name').value = record ? record.name : '';
    $('#space-type-field').hidden = kind !== 'container';
    if (kind === 'container') {
        $('#space-type').value = record ? record.type : 'scatolone';
    }
    $('#space-dialog').showModal();
}

// ---- QR Labels Tab ----

function renderQrTab() {
    const containers = flattenContainers();
    const selectorList = $('#qr-selector-list');
    const grid = $('#qr-labels-grid');

    if (!containers.length) {
        selectorList.replaceChildren(
            el('p', { className: 'help-text' }, 'Crea almeno un contenitore per generare etichette QR.'),
        );
        grid.replaceChildren();
        return;
    }

    if (!state.qrInitialized) {
        containers.forEach((c) => state.selectedQrIds.add(c.id));
        state.qrInitialized = true;
    }

    selectorList.replaceChildren(
        ...containers.map((c) => {
            const checked = state.selectedQrIds.has(c.id);
            const checkbox = el('input', {
                type: 'checkbox',
                ...(checked ? { checked: 'checked' } : {}),
                onChange: (ev) => {
                    if (ev.target.checked) state.selectedQrIds.add(c.id);
                    else state.selectedQrIds.delete(c.id);
                    renderQrCards(containers);
                },
            });
            return el(
                'label',
                {
                    className: 'btn btn-sm',
                    style: { fontWeight: '500' },
                },
                checkbox,
                `${c.houseName} › ${c.roomName} › ${c.name}`,
            );
        }),
    );

    renderQrCards(containers);
}

function renderQrCards(containers) {
    const grid = $('#qr-labels-grid');
    const selected = containers.filter((c) => state.selectedQrIds.has(c.id));
    const printBtn = $('#qr-print-btn');
    if (printBtn) {
        printBtn.disabled = selected.length === 0;
        printBtn.textContent =
            selected.length === 0
                ? 'Stampa etichette'
                : selected.length === 1
                  ? 'Stampa 1 etichetta'
                  : `Stampa ${selected.length} etichette`;
    }
    if (!selected.length) {
        grid.replaceChildren(
            el('p', { className: 'help-text' }, 'Seleziona almeno un contenitore sopra.'),
        );
        return;
    }

    const origin = window.location.origin;
    grid.replaceChildren(
        ...selected.map((c) => {
            // Flutter Web defaults to HashUrlStrategy (#/inventory?...)
            const url = `${origin}/#/inventory?containerId=${c.id}&title=${encodeURIComponent(c.name)}`;
            let qrNode;
            try {
                qrNode = renderQrSvgElement(url, { sizePx: 148 });
            } catch {
                // Fallback to shorter URL without title if host+title is very long
                qrNode = renderQrSvgElement(`${origin}/#/inventory?containerId=${c.id}`, {
                    sizePx: 148,
                });
            }
            return el(
                'div',
                { className: 'qr-label-card' },
                qrNode,
                el('div', { className: 'qr-label-title' }, c.name),
                el(
                    'div',
                    { className: 'qr-label-path' },
                    `${c.houseName} › ${c.roomName} (${c.type})`,
                ),
                el('div', { className: 'qr-label-url' }, `#${c.id} · ${origin}`),
            );
        }),
    );
}

// ---- Tokens Table & Snippets ----

function renderTokensTable() {
    const tbody = $('#tokens-table-body');
    if (!state.tokens.length) {
        tbody.replaceChildren(
            el(
                'tr',
                {},
                el(
                    'td',
                    { colspan: '6', className: 'help-text' },
                    'Nessun token integrativo creato.',
                ),
            ),
        );
        return;
    }

    tbody.replaceChildren(
        ...state.tokens.map((tok) =>
            el(
                'tr',
                {},
                el('td', {}, el('strong', {}, tok.name)),
                el('td', {}, el('code', {}, `${tok.prefix}…`)),
                el(
                    'td',
                    {},
                    el(
                        'span',
                        {
                            className:
                                tok.scope === 'write'
                                    ? 'badge badge-warn'
                                    : 'badge badge-ok',
                        },
                        tok.scope,
                    ),
                ),
                el('td', {}, formatDate(tok.createdAt)),
                el('td', {}, formatDate(tok.lastUsedAt)),
                el(
                    'td',
                    {},
                    el(
                        'button',
                        {
                            type: 'button',
                            className: 'btn btn-danger btn-sm',
                            onClick: () => revokeToken(tok),
                        },
                        'Revoca',
                    ),
                ),
            ),
        ),
    );
}

async function revokeToken(tok) {
    const confirmed = await confirmAction({
        title: 'Revoca token API',
        message: `Revocare il token "${tok.name}"? Le integrazioni che lo usano perderanno subito l'accesso.`,
        confirmLabel: 'Revoca token',
    });
    if (!confirmed) return;
    try {
        await apiFetch(`/api/admin/tokens/${tok.id}`, { method: 'DELETE' });
        showToast('Token revocato.', 'ok');
        await loadTokens();
    } catch (error) {
        showToast(error.message, 'error');
    }
}

// ---- Confirmation Dialog & Clipboard Helpers ----

function confirmAction({ title, message, confirmLabel = 'Conferma' }) {
    const dialog = $('#confirm-dialog');
    $('#confirm-dialog-title').textContent = title;
    $('#confirm-dialog-message').textContent = message;
    const okBtn = $('#confirm-dialog-ok');
    const cancelBtn = $('#confirm-dialog-cancel');
    okBtn.textContent = confirmLabel;

    return new Promise((resolve) => {
        let settled = false;
        const finish = (accepted) => {
            if (settled) return;
            settled = true;
            okBtn.removeEventListener('click', onOk);
            cancelBtn.removeEventListener('click', onCancel);
            dialog.removeEventListener('close', onClose);
            if (dialog.open) dialog.close();
            resolve(accepted);
        };
        const onOk = () => finish(true);
        const onCancel = () => finish(false);
        const onClose = () => finish(false);

        okBtn.addEventListener('click', onOk);
        cancelBtn.addEventListener('click', onCancel);
        dialog.addEventListener('close', onClose);
        dialog.showModal();
    });
}

async function copyTextWithFeedback(text, button, defaultLabel) {
    if (!text) return;
    try {
        if (navigator.clipboard?.writeText) {
            await navigator.clipboard.writeText(text);
        } else {
            throw new Error('Clipboard API non disponibile');
        }
        button.textContent = 'Copiato!';
        showToast('Copiato negli appunti.', 'ok');
        setTimeout(() => {
            button.textContent = defaultLabel;
        }, 1800);
    } catch {
        showToast('Impossibile copiare automaticamente: seleziona il testo manualmente.', 'error');
    }
}

function renderApiSnippet() {
    const base = window.location.origin;
    $('#api-snippet').textContent = [
        '# Ricerca oggetti con percorso completo (ideale per Hermes Agent / Home Assistant)',
        `curl -H "X-Api-Key: <IL_TUO_TOKEN_READ>" "${base}/api/search?q=hdmi"`,
        '',
        '# Export completo JSON',
        `curl -H "X-Api-Key: <IL_TUO_TOKEN_READ>" "${base}/api/export"`,
    ].join('\n');
}

// ---- Form Handlers ----

function bindForms() {
    $('#password-login-form').addEventListener('submit', async (ev) => {
        ev.preventDefault();
        const errBox = $('#login-error');
        errBox.hidden = true;
        const password = $('#login-password').value;
        let session;
        try {
            session = await apiFetch('/api/auth/login', {
                method: 'POST',
                body: JSON.stringify({ password }),
            });
        } catch (error) {
            errBox.textContent = error.message;
            errBox.hidden = false;
            return;
        }
        $('#login-password').value = '';
        showConsole({ ...session, authEnabled: true });
        try {
            await refreshAll();
        } catch (error) {
            showToast(error.message, 'error');
        }
    });

    $('#logout-btn').addEventListener('click', async () => {
        try {
            await apiFetch('/api/auth/logout', { method: 'POST' });
            window.location.reload();
        } catch (error) {
            showToast(error.message, 'error');
        }
    });

    $('#refresh-overview-btn').addEventListener('click', async () => {
        try {
            await loadOverview();
        } catch (error) {
            showToast(error.message, 'error');
        }
    });
    $('#refresh-ollama-btn').addEventListener('click', () => loadOllama());

    $('#test-vision-form').addEventListener('submit', async (ev) => {
        ev.preventDefault();
        const file = $('#test-vision-file').files?.[0];
        if (!file) return;
        if (file.size > 5 * 1024 * 1024) {
            showToast("L'immagine supera il limite di 5 MB.", 'error');
            return;
        }
        const submitBtn = $('#test-vision-submit');
        submitBtn.disabled = true;
        submitBtn.textContent = 'Analisi in corso...';

        try {
            const base64 = await fileToBase64(file);
            const t0 = performance.now();
            const res = await fetch('/api/recognize', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    imageBase64: base64,
                    mimeType: file.type || 'image/jpeg',
                    existingItems: [],
                }),
            });
            const elapsed = Math.round(performance.now() - t0);
            const provider = res.headers.get('x-vision-provider') || 'sconosciuto';
            const usedFallback = res.headers.get('x-vision-fallback') === 'true';
            const isJson = (res.headers.get('content-type') || '').includes(
                'application/json',
            );
            const payload = isJson ? await res.json() : null;
            if (!res.ok) {
                throw new Error(
                    (payload && payload.error) || `Errore HTTP ${res.status}`,
                );
            }

            const box = $('#test-vision-result');
            box.hidden = false;
            box.replaceChildren(
                el(
                    'div',
                    { className: 'row-inline', style: { marginBottom: '0.5rem' } },
                    el('span', { className: 'badge badge-ok' }, `Provider: ${provider}`),
                    usedFallback
                        ? el('span', { className: 'badge badge-warn' }, 'Fallback attivo')
                        : null,
                    el('span', { className: 'badge badge-neutral' }, `${elapsed} ms`),
                ),
                el('pre', { className: 'code-block' }, JSON.stringify(payload, null, 2)),
            );
            await loadOverview();
        } catch (error) {
            showToast(error.message, 'error');
        } finally {
            submitBtn.disabled = false;
            submitBtn.textContent = 'Analizza con pipeline AI';
        }
    });

    $('#inventory-search').addEventListener('input', () => renderItemsTable());
    $('#inventory-category-filter').addEventListener('change', () => renderItemsTable());
    $('#show-all-items-btn').addEventListener('click', () => {
        state.selectedContainerId = null;
        renderSpaceTree();
        renderItemsTable();
    });
    $('#add-house-btn').addEventListener('click', () => openSpaceDialog('house', null, null));
    $('#add-item-btn').addEventListener('click', () => openItemDialog(null));

    $('#item-dialog-cancel').addEventListener('click', () => $('#item-dialog').close());
    $('#item-dialog-form').addEventListener('submit', async (ev) => {
        ev.preventDefault();
        const id = $('#item-id').value;
        const body = {
            name: $('#item-name').value.trim(),
            category: $('#item-category').value.trim(),
            quantity: Number.parseInt($('#item-quantity').value, 10),
            containerId: Number.parseInt($('#item-container').value, 10),
            shortDescription: $('#item-desc').value.trim(),
            notes: $('#item-notes').value.trim(),
        };
        try {
            if (id) {
                await apiFetch(`/api/items/${id}`, {
                    method: 'PATCH',
                    body: JSON.stringify(body),
                });
                showToast('Oggetto aggiornato.', 'ok');
            } else {
                await apiFetch('/api/items', {
                    method: 'POST',
                    body: JSON.stringify(body),
                });
                showToast('Oggetto aggiunto.', 'ok');
            }
            $('#item-dialog').close();
            await Promise.all([loadInventoryData(), loadOverview()]);
        } catch (error) {
            showToast(error.message, 'error');
        }
    });

    $('#space-dialog-cancel').addEventListener('click', () => $('#space-dialog').close());
    $('#space-dialog-form').addEventListener('submit', async (ev) => {
        ev.preventDefault();
        const kind = $('#space-kind').value;
        const id = $('#space-id').value;
        const parentId = Number.parseInt($('#space-parent-id').value || '0', 10);
        const name = $('#space-name').value.trim();

        try {
            if (kind === 'house') {
                await apiFetch(id ? `/api/houses/${id}` : '/api/houses', {
                    method: id ? 'PATCH' : 'POST',
                    body: JSON.stringify({ name }),
                });
            } else if (kind === 'room') {
                await apiFetch(id ? `/api/rooms/${id}` : '/api/rooms', {
                    method: id ? 'PATCH' : 'POST',
                    body: JSON.stringify(id ? { name } : { name, houseId: parentId }),
                });
            } else if (kind === 'container') {
                const type = $('#space-type').value;
                await apiFetch(id ? `/api/containers/${id}` : '/api/containers', {
                    method: id ? 'PATCH' : 'POST',
                    body: JSON.stringify(
                        id ? { name, type } : { name, type, roomId: parentId },
                    ),
                });
            }
            $('#space-dialog').close();
            showToast('Spazio salvato.', 'ok');
            await Promise.all([loadInventoryData(), loadOverview()]);
        } catch (error) {
            showToast(error.message, 'error');
        }
    });

    $('#qr-select-all-btn').addEventListener('click', () => {
        flattenContainers().forEach((c) => state.selectedQrIds.add(c.id));
        renderQrTab();
    });
    $('#qr-clear-btn').addEventListener('click', () => {
        state.selectedQrIds.clear();
        renderQrTab();
    });
    $('#qr-print-btn').addEventListener('click', () => window.print());

    $('#ai-settings-form').addEventListener('submit', async (ev) => {
        ev.preventDefault();
        try {
            await apiFetch('/api/admin/settings', {
                method: 'PUT',
                body: JSON.stringify({
                    primaryProvider: $('#setting-primary').value,
                    fallbackProvider: $('#setting-fallback').value,
                    ollamaModel: $('#setting-ollama-model').value,
                    cloudTimeoutMs: $('#setting-cloud-timeout').value,
                    ollamaTimeoutMs: $('#setting-ollama-timeout').value,
                    promptTemplate: $('#setting-prompt').value,
                }),
            });
            showToast('Impostazioni AI salvate (attive subito).', 'ok');
            await Promise.all([loadOverview(), loadSettings()]);
        } catch (error) {
            showToast(error.message, 'error');
        }
    });

    $('#reset-prompt-btn').addEventListener('click', () => {
        $('#setting-prompt').value = '';
        showToast('Prompt ripristinato al default (clicca Salva per confermare).');
    });

    $('#check-integrity-btn').addEventListener('click', async () => {
        try {
            const res = await apiFetch('/api/admin/maintenance/integrity', {
                method: 'POST',
            });
            $('#maintenance-output').textContent = res.ok
                ? 'Integrità SQLite OK.'
                : `Anomalie rilevate: ${res.messages.join(', ')}`;
        } catch (error) {
            showToast(error.message, 'error');
        }
    });

    $('#rebuild-fts-btn').addEventListener('click', async () => {
        try {
            await apiFetch('/api/admin/maintenance/rebuild-fts', {
                method: 'POST',
            });
            $('#maintenance-output').textContent = 'Indice FTS5 ricostruito correttamente.';
            showToast('Indice FTS5 aggiornato.', 'ok');
        } catch (error) {
            showToast(error.message, 'error');
        }
    });

    const runImport = async (dryRun) => {
        const file = $('#import-json-file').files?.[0];
        if (!file) {
            showToast('Seleziona prima un file JSON.', 'error');
            return;
        }
        try {
            const text = await file.text();
            const parsed = JSON.parse(text);
            const summary = await apiFetch(
                `/api/admin/import?dryRun=${dryRun ? 'true' : 'false'}`,
                {
                    method: 'POST',
                    body: JSON.stringify(parsed),
                },
            );
            $('#import-output').textContent = `${
                dryRun ? 'Anteprima' : 'Importati'
            }: ${summary.housesAdded} case, ${summary.roomsAdded} stanze, ${summary.containersAdded} contenitori, ${summary.itemsAdded} oggetti.`;
            if (!dryRun) {
                showToast('Importazione completata.', 'ok');
                await Promise.all([loadInventoryData(), loadOverview()]);
            }
        } catch (error) {
            showToast(error.message, 'error');
        }
    };

    $('#import-dryrun-btn').addEventListener('click', () => runImport(true));
    $('#import-json-form').addEventListener('submit', (ev) => {
        ev.preventDefault();
        runImport(false);
    });

    $('#create-token-form').addEventListener('submit', async (ev) => {
        ev.preventDefault();
        try {
            const created = await apiFetch('/api/admin/tokens', {
                method: 'POST',
                body: JSON.stringify({
                    name: $('#token-name').value.trim(),
                    scope: $('#token-scope').value,
                }),
            });
            $('#token-name').value = '';
            $('#new-token-value').textContent = created.token;
            $('#new-token-banner').hidden = false;
            showToast('Token API generato.', 'ok');
            await loadTokens();
        } catch (error) {
            showToast(error.message, 'error');
        }
    });

    $('#copy-token-btn').addEventListener('click', (ev) => {
        copyTextWithFeedback(
            $('#new-token-value').textContent,
            ev.currentTarget,
            'Copia token',
        );
    });

    $('#copy-snippet-btn').addEventListener('click', (ev) => {
        copyTextWithFeedback(
            $('#api-snippet').textContent,
            ev.currentTarget,
            'Copia snippet',
        );
    });
}

function fileToBase64(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const result = String(reader.result || '');
            const comma = result.indexOf(',');
            resolve(comma >= 0 ? result.slice(comma + 1) : result);
        };
        reader.onerror = () => reject(new Error('Impossibile leggere il file.'));
        reader.readAsDataURL(file);
    });
}

boot();
