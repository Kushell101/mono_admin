const RES = typeof GetParentResourceName === 'function'
    ? GetParentResourceName()
    : 'mono_admin';

const ERRORS = {
    no_permission: 'Brak uprawnień.',
    player_not_found: 'Nie znaleziono gracza (mógł wyjść z serwera).',
    cannot_target_self: 'Nie możesz wykonać tej akcji na sobie.',
    target_immune: 'Ten gracz jest chroniony przed tą akcją.',
    invalid_reason: 'Podaj powód (3–200 znaków).',
    invalid_duration: 'Nieprawidłowy czas bana.',
    ban_not_found: 'Nie znaleziono bana.',
    rate_limited: 'Zwolnij trochę.',
    database_error: 'Błąd bazy danych.',
    license_not_found: 'Gracz nie ma identyfikatora license.',
    not_in_game: 'Najpierw wybierz postać.',
    internal_error: 'Błąd wewnętrzny serwera (sprawdź konsolę).',
    no_ped: 'Brak peda gracza po stronie serwera (czy OneSync jest włączony?).',
    unknown_feature: 'Nieznana funkcja.',
    invalid_coords: 'Nieprawidłowe koordynaty (podaj: x, y, z).',
    target_no_waypoint: 'Gracz nie ma ustawionego waypointu — poproś go o zaznaczenie punktu na mapie.',
    target_waypoint_out_of_map: 'Waypoint gracza leży poza mapą.',
    target_busy: 'Gracz jest w trakcie innego teleportu — spróbuj za chwilę.',
    target_no_response: 'Klient gracza nie odpowiedział.',
    unknown_weapon: 'Nieznany model broni (np. weapon_pistol).',
    invalid_ammo: 'Nieprawidłowa ilość amunicji.',
    timeout: 'Serwer nie odpowiedział.'
};

const DURATIONS = [
    ['1 godzina', 3600],
    ['6 godzin', 21600],
    ['1 dzień', 86400],
    ['3 dni', 259200],
    ['7 dni', 604800],
    ['30 dni', 2592000],
    ['Permanentny', 0]
];

const state = {
    open: false,
    tab: 'players',
    perms: new Set(),
    players: [],
    bans: [],
    selectedId: null,
    details: null,
    self: {},
    selfId: null,
    modal: false,
    waypoint: null
};

const $ = (id) => document.getElementById(id);

const els = {
    root: $('root'),
    nav: $('nav'),
    title: $('tab-title'),
    search: $('search'),
    body: $('body'),
    list: $('list'),
    drawer: $('drawer'),
    adminName: $('admin-name'),
    modalLayer: $('modal-layer'),
    toasts: $('toasts')
};

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

// Budowanie DOM bez innerHTML - nazwy graczy sa kontrolowane przez graczy.
function h(tag, props, ...children) {
    const el = document.createElement(tag);

    for (const [key, value] of Object.entries(props || {})) {
        if (value === false || value == null) continue;

        if (key === 'class') el.className = value;
        else if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
        else el.setAttribute(key, value);
    }

    for (const child of children.flat()) {
        if (child == null || child === false) continue;
        el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }

    return el;
}

async function api(name, payload = {}) {
    try {
        const res = await fetch(`https://${RES}/request`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, payload })
        });

        return await res.json();
    } catch {
        return { ok: false, error: 'timeout' };
    }
}

// Wywolanie NUI callbacku z odpowiedzia (post() ja ignoruje).
async function nui(name, body = {}) {
    try {
        const res = await fetch(`https://${RES}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });

        return await res.json();
    } catch {
        return null;
    }
}

function post(name) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}'
    }).catch(() => {});
}

function errorText(code) {
    return ERRORS[code] || `Błąd: ${code}`;
}

function toast(text, isError = false) {
    const el = h('div', { class: 'toast' + (isError ? ' error' : '') }, text);

    els.toasts.append(el);

    setTimeout(() => el.remove(), 3800);
}

function fmtDate(ts) {
    return new Date(ts * 1000).toLocaleString('pl-PL', {
        dateStyle: 'short',
        timeStyle: 'short'
    });
}

function can(permission) {
    return state.perms.has(permission);
}

function matches(query, ...values) {
    if (!query) return true;

    const needle = query.toLowerCase();

    return values.some((value) => String(value ?? '').toLowerCase().includes(needle));
}

/* ------------------------------------------------------------------ */
/* Modal                                                               */
/* ------------------------------------------------------------------ */

function closeModal() {
    state.modal = false;
    els.modalLayer.classList.add('hidden');
    els.modalLayer.replaceChildren();
}

// fields: [{ key, label, type: 'textarea' | 'select', options?, placeholder? }]
// onSubmit(values) -> odpowiedz api() ({ ok, data, error })
function openModal({ title, subtitle, fields = [], confirm, tone = 'primary', onSubmit, onSuccess }) {
    const inputs = {};

    const fieldNodes = fields.map((field) => {
        let input;

        if (field.type === 'select') {
            input = h('select', {}, field.options.map(([label, value]) => h('option', { value }, label)));
        } else {
            input = h('textarea', {
                placeholder: field.placeholder || '',
                maxlength: 200
            });
        }

        inputs[field.key] = input;

        return h('div', { class: 'field' }, h('label', {}, field.label.toUpperCase()), input);
    });

    const confirmBtn = h('button', { class: `btn ${tone}` }, confirm);

    const submit = async () => {
        const values = {};

        for (const [key, input] of Object.entries(inputs)) {
            values[key] = input.value;
        }

        confirmBtn.disabled = true;

        const res = await onSubmit(values);

        if (res.ok) {
            closeModal();
            onSuccess?.(res.data);
        } else {
            confirmBtn.disabled = false;
            toast(errorText(res.error), true);
        }
    };

    confirmBtn.addEventListener('click', submit);

    const modal = h(
        'div',
        { class: 'modal' },
        h('h2', {}, title),
        subtitle && h('p', { class: 'modal-sub' }, subtitle),
        fieldNodes,
        h(
            'div',
            { class: 'modal-actions' },
            h('button', { class: 'btn', onclick: closeModal }, 'Anuluj'),
            confirmBtn
        )
    );

    els.modalLayer.replaceChildren(modal);
    els.modalLayer.classList.remove('hidden');
    state.modal = true;

    Object.values(inputs)[0]?.focus();
}

/* ------------------------------------------------------------------ */
/* Gracze                                                              */
/* ------------------------------------------------------------------ */

function pingClass(ping) {
    if (ping >= 200) return 'ping bad';
    if (ping >= 100) return 'ping mid';
    return 'ping';
}

function playerRow(player) {
    return h(
        'div',
        {
            class: 'row' + (state.selectedId === player.id ? ' selected' : ''),
            onclick: () => selectPlayer(player.id)
        },
        h('span', { class: 'id-badge' }, player.id),
        h('div', { class: 'cell' }, h('span', { class: 'cell-main' }, player.name)),
        h(
            'div',
            { class: 'cell' },
            player.character
                ? h('span', { class: 'cell-main' }, player.character)
                : h('span', { class: 'muted' }, 'brak postaci')
        ),
        h('span', { class: pingClass(player.ping) }, `${player.ping} ms`)
    );
}

function renderPlayers() {
    const query = els.search.value.trim();

    const rows = state.players.filter((p) => matches(query, p.id, p.name, p.character));

    els.list.replaceChildren(
        ...(rows.length
            ? rows.map(playerRow)
            : [h('div', { class: 'empty' }, 'Brak graczy do wyświetlenia.')])
    );

    renderNav();
}

async function loadPlayers() {
    const res = await api('getPlayers');

    if (!res.ok) {
        return toast(errorText(res.error), true);
    }

    state.players = res.data;

    if (state.tab === 'players') {
        renderPlayers();
    }
}

async function selectPlayer(id) {
    state.selectedId = id;
    state.details = null;

    renderPlayers();
    renderDrawer();

    const res = await api('getPlayerDetails', { id });

    if (state.selectedId !== id) return;

    if (!res.ok) {
        state.selectedId = null;
        toast(errorText(res.error), true);
        renderPlayers();
    } else {
        state.details = res.data;
    }

    renderDrawer();
}

function reasonField(placeholder) {
    return { key: 'reason', label: 'Powód', type: 'textarea', placeholder };
}

function playerAction(kind, player) {
    const subtitle = `${player.name} [${player.id}]`;

    const done = (message) => () => {
        toast(message);
        loadPlayers();
        selectPlayer(player.id);
    };

    const gone = (message) => () => {
        toast(message);
        state.selectedId = null;
        state.details = null;
        loadPlayers();
        renderDrawer();
    };

    if (kind === 'warn') {
        openModal({
            title: 'Ostrzeż gracza',
            subtitle,
            fields: [reasonField('Za co dostaje ostrzeżenie?')],
            confirm: 'Ostrzeż',
            tone: 'warn',
            onSubmit: (v) => api('warn', { id: player.id, reason: v.reason }),
            onSuccess: (data) => done(`Ostrzeżenie dodane (aktywne: ${data.count}).`)()
        });
    }

    if (kind === 'kick') {
        openModal({
            title: 'Wyrzuć gracza',
            subtitle,
            fields: [reasonField('Powód wyrzucenia')],
            confirm: 'Wyrzuć',
            tone: 'danger',
            onSubmit: (v) => api('kick', { id: player.id, reason: v.reason }),
            onSuccess: (data) => gone(`Wyrzucono: ${data.name}.`)()
        });
    }

    if (kind === 'ban') {
        openModal({
            title: 'Zbanuj gracza',
            subtitle,
            fields: [
                reasonField('Powód bana'),
                { key: 'duration', label: 'Czas trwania', type: 'select', options: DURATIONS }
            ],
            confirm: 'Zbanuj',
            tone: 'danger',
            onSubmit: (v) => api('ban', {
                id: player.id,
                reason: v.reason,
                duration: Number(v.duration)
            }),
            onSuccess: (data) => gone(`Zbanowano: ${data.name} (ban #${data.id}).`)()
        });
    }
}

async function quick(name, player, message, closeAfter = false) {
    const res = await api(name, { id: player.id });

    if (!res.ok) {
        return toast(errorText(res.error), true);
    }

    toast(message(res.data));

    if (closeAfter) {
        requestClose();
    } else if (name === 'heal' || name === 'freeze') {
        loadPlayers();
    }
}

function renderDrawer() {
    if (state.tab !== 'players') return;

    els.body.classList.toggle('with-drawer', state.selectedId !== null);

    if (state.selectedId === null) {
        return els.drawer.replaceChildren();
    }

    const d = state.details;

    if (!d) {
        return els.drawer.replaceChildren(h('div', { class: 'empty' }, 'Ładowanie...'));
    }

    const btn = (label, cls, onclick) => h('button', { class: `btn ${cls}`, onclick }, label);

    const moderation = [
        can('warn') && btn('Ostrzeż', 'warn', () => playerAction('warn', d)),
        can('kick') && btn('Wyrzuć', 'danger', () => playerAction('kick', d)),
        can('ban') && btn('Zbanuj', 'danger', () => playerAction('ban', d))
    ].filter(Boolean);

    const tools = [
        can('teleport') && btn('Teleport do', '', () => quick('teleportToPlayer', d, () => `Teleportowano do ${d.name}.`)),
        can('teleport') && btn('Przyciągnij', '', () => quick('bringPlayer', d, () => `Przyciągnięto: ${d.name}.`)),
        can('heal') && btn('Ulecz', '', () => quick('heal', d, () => `Uleczono: ${d.name}.`)),
        can('freeze') && btn('Zamroź', '', () => quick('freeze', d, (r) => (r.enabled ? `Zamrożono: ${d.name}.` : `Odmrożono: ${d.name}.`))),
        can('spectate') && btn('Podgląd', '', () => quick('spectate', d, () => 'Podgląd włączony.', true)),
        can('teleport') && btn(
            'Teleportuj na waypoint gracza',
            'wide',
            () => quick('teleportPlayerToWaypoint', d, () => `Teleportowanie ${d.name} na jego waypoint...`)
        )
    ].filter(Boolean);

    const identifierRows = d.identifiers.map((identifier) => {
        const [prefix, ...rest] = identifier.split(':');

        return h(
            'div',
            { class: 'kv', title: identifier },
            h('span', {}, prefix),
            h('span', {}, rest.join(':'))
        );
    });

    const section = (title, ...content) =>
        h('div', {}, h('div', { class: 'section-title' }, title), ...content);

    const sections = [
        h(
            'div',
            {},
            h('div', { class: 'd-title' }, d.name),
            h('div', { class: 'd-sub' }, `ID ${d.id} · ${d.ping} ms`)
        ),

        section(
            'POSTAĆ',
            d.character
                ? [
                    h('div', { class: 'kv' }, h('span', {}, 'Imię i nazwisko'), h('span', {}, `${d.character.first_name} ${d.character.last_name}`)),
                    h('div', { class: 'kv' }, h('span', {}, 'Data urodzenia'), h('span', {}, d.character.date_of_birth)),
                    h('div', { class: 'kv' }, h('span', {}, 'Płeć'), h('span', {}, d.character.gender))
                ]
                : h('div', { class: 'muted' }, 'Gracz nie wybrał jeszcze postaci.')
        ),

        moderation.length ? section('MODERACJA', h('div', { class: 'actions' }, moderation)) : null,

        tools.length ? section('NARZĘDZIA', h('div', { class: 'actions' }, tools)) : null,

        section(
            `OSTRZEŻENIA (${d.warnCount})`,
            d.warns.length
                ? d.warns.map((w) =>
                    h('div', { class: 'warn-item' }, w.reason, h('small', {}, `${w.warned_by_name} · ${fmtDate(w.created_at)}`))
                )
                : h('div', { class: 'muted' }, 'Brak aktywnych ostrzeżeń.')
        ),

        section('IDENTYFIKATORY', identifierRows)
    ].filter(Boolean);

    els.drawer.replaceChildren(...sections);
}

/* ------------------------------------------------------------------ */
/* Bany                                                                */
/* ------------------------------------------------------------------ */

function banRow(ban) {
    return h(
        'div',
        { class: 'row ban' },
        h('span', { class: 'id-badge' }, `#${ban.id}`),
        h(
            'div',
            { class: 'cell' },
            h('span', { class: 'cell-main' }, ban.player_name),
            h('span', { class: 'cell-sub', title: ban.license }, ban.license)
        ),
        h(
            'div',
            { class: 'cell' },
            h('span', { class: 'cell-main' }, ban.reason),
            h('span', { class: 'cell-sub' }, `${ban.banned_by_name} · ${fmtDate(ban.created_at)}`)
        ),
        h('span', { class: 'muted' }, ban.expires_at === 0 ? 'Permanentny' : `do ${fmtDate(ban.expires_at)}`),
        can('unban')
            ? h('button', { class: 'btn small', onclick: () => confirmUnban(ban) }, 'Odbanuj')
            : h('span')
    );
}

function confirmUnban(ban) {
    openModal({
        title: 'Odbanuj gracza',
        subtitle: `${ban.player_name} · ban #${ban.id}`,
        confirm: 'Odbanuj',
        tone: 'primary',
        onSubmit: () => api('unban', { id: ban.id }),
        onSuccess: (data) => {
            toast(`Odbanowano: ${data.name}.`);
            loadBans();
        }
    });
}

function renderBans() {
    const query = els.search.value.trim();

    const rows = state.bans.filter((b) => matches(query, b.id, b.player_name, b.license, b.reason, b.banned_by_name));

    els.list.replaceChildren(
        ...(rows.length
            ? rows.map(banRow)
            : [h('div', { class: 'empty' }, 'Brak aktywnych banów.')])
    );

    renderNav();
}

async function loadBans() {
    const res = await api('getBans');

    if (!res.ok) {
        return toast(errorText(res.error), true);
    }

    state.bans = res.data;

    if (state.tab === 'bans') {
        renderBans();
    }
}

/* ------------------------------------------------------------------ */
/* Ja (narzedzia wlasne)                                               */
/* ------------------------------------------------------------------ */

const SELF_PERMS = ['noclip', 'godmode', 'invisible', 'teleport', 'heal', 'giveitem'];

const FEATURE_META = [
    ['noclip', 'Noclip', 'Latanie bez kolizji, 4 poziomy prędkości (scroll lub 1–4). Jesteś niewidzialny dla graczy. Panel zamyka się sam.'],
    ['godmode', 'God mode', 'Nieśmiertelność.'],
    ['invisible', 'Niewidzialność', 'Niewidzialny dla graczy — u siebie widzisz się jako półprzezroczysty.']
];

let toggleBusy = false;

async function toggleFeature(key, label) {
    if (toggleBusy) return;

    toggleBusy = true;

    const res = await api('toggleFeature', { feature: key });

    toggleBusy = false;

    if (!res.ok) {
        return toast(errorText(res.error), true);
    }

    state.self[key] = res.data.enabled;

    toast(`${label}: ${res.data.enabled ? 'włączony' : 'wyłączony'}.`);

    if (key === 'noclip' && res.data.enabled) {
        return requestClose();
    }

    renderSelf();
}

async function loadWaypoint() {
    const wp = await nui('getWaypoint');

    state.waypoint = wp && wp.active ? wp : { active: false };

    if (state.open && state.tab === 'self') {
        renderSelf();
    }
}

async function teleportToWaypoint() {
    // Swieze sprawdzenie tuz przed teleportem (waypoint mogl zniknac).
    const wp = await nui('getWaypoint');

    if (!wp || !wp.active) {
        state.waypoint = { active: false };
        renderSelf();

        return toast('Najpierw ustaw waypoint na mapie (ESC → mapa).', true);
    }

    const res = await api('teleportWaypoint', {});

    if (!res.ok) {
        return toast(errorText(res.error), true);
    }

    // Zamykamy panel, zeby bylo widac teleport.
    requestClose();
}

async function selfCall(name, payload, message) {
    const res = await api(name, payload);

    if (!res.ok) {
        return toast(errorText(res.error), true);
    }

    toast(message);
}

function openCoordsModal() {
    openModal({
        title: 'Teleport na koordynaty',
        subtitle: 'Wklej x, y, z (np. 215.3, -810.1, 30.7 albo vector3(…)).',
        fields: [{ key: 'coords', label: 'Koordynaty', type: 'textarea', placeholder: 'x, y, z' }],
        confirm: 'Teleportuj',
        onSubmit: (v) => {
            const numbers = (v.coords.match(/-?\d+(?:\.\d+)?/g) || []).map(Number);

            if (numbers.length < 3) {
                return { ok: false, error: 'invalid_coords' };
            }

            return api('teleportCoords', { x: numbers[0], y: numbers[1], z: numbers[2] });
        },
        onSuccess: () => toast('Teleportowanie...')
    });
}

function waypointDescription() {
    if (!state.waypoint) return 'Sprawdzanie waypointu...';

    if (!state.waypoint.active) {
        return 'Brak waypointu. Zamknij panel, ustaw punkt na mapie (ESC → mapa) i otwórz panel ponownie.';
    }

    return `Waypoint: X ${state.waypoint.x.toFixed(1)}, Y ${state.waypoint.y.toFixed(1)}. Wysokość zostanie dobrana automatycznie.`;
}

function renderSelf() {
    const card = (title, desc, control) =>
        h(
            'div',
            { class: 'card' },
            h('div', { class: 'card-text' }, h('div', { class: 'card-title' }, title), h('div', { class: 'card-desc' }, desc)),
            control
        );

    const cards = [];

    for (const [key, label, desc] of FEATURE_META) {
        if (!can(key)) continue;

        const on = !!state.self[key];

        cards.push(
            card(
                label,
                desc,
                h('button', { type: 'button', class: 'switch' + (on ? ' on' : ''), onclick: () => toggleFeature(key, label) }, h('span'))
            )
        );
    }

    if (can('teleport')) {
        cards.push(
            card(
                'Teleport na waypoint',
                waypointDescription(),
                h(
                    'button',
                    {
                        class: 'btn small',
                        disabled: !(state.waypoint && state.waypoint.active),
                        onclick: teleportToWaypoint
                    },
                    'Teleportuj'
                )
            ),
            card(
                'Teleport na koordynaty',
                'Podaj x, y, z.',
                h('button', { class: 'btn small', onclick: openCoordsModal }, 'Podaj')
            )
        );
    }

    if (can('heal')) {
        cards.push(
            card(
                'Ulecz mnie',
                'Pełne zdrowie i reanimacja.',
                h('button', { class: 'btn small', onclick: () => selfCall('heal', { id: state.selfId }, 'Uleczono.') }, 'Ulecz')
            )
        );
    }

    if (can('giveitem')) {
        cards.push(
            card(
                'Dodaj wszystkie bronie',
                'Dodaje do kółka wyboru wszystkie bronie dostępne w GTA V (z domyślną amunicją). Pojedyncza broń: /giveweapon [model] [amunicja].',
                h('button', { class: 'btn small', onclick: () => selfCall('giveAllWeapons', {}, 'Dodawanie broni...') }, 'Dodaj')
            )
        );
    }

    els.list.replaceChildren(h('div', { class: 'self-grid' }, ...cards));

    renderNav();
}

/* ------------------------------------------------------------------ */
/* Nawigacja                                                           */
/* ------------------------------------------------------------------ */

function tabs() {
    return [
        { id: 'players', label: 'Gracze', count: state.players.length },
        can('ban') && { id: 'bans', label: 'Bany', count: state.bans.length },
        SELF_PERMS.some(can) && { id: 'self', label: 'Ja', count: 0 }
    ].filter(Boolean);
}

function renderNav() {
    els.nav.replaceChildren(
        ...tabs().map((tab) =>
            h(
                'button',
                {
                    class: 'nav-item' + (state.tab === tab.id ? ' active' : ''),
                    onclick: () => setTab(tab.id)
                },
                h('span', {}, tab.label),
                h('span', { class: 'nav-count' }, tab.count || '')
            )
        )
    );
}

function setTab(tab) {
    state.tab = tab;
    els.search.value = '';
    els.search.classList.toggle('hidden', tab === 'self');

    els.title.textContent = { players: 'Gracze', bans: 'Bany', self: 'Ja' }[tab];

    if (tab === 'players') {
        els.body.classList.toggle('with-drawer', state.selectedId !== null);
        renderPlayers();
        renderDrawer();
        loadPlayers();
    } else if (tab === 'bans') {
        els.body.classList.remove('with-drawer');
        renderBans();
        loadBans();
    } else {
        els.body.classList.remove('with-drawer');
        renderSelf();
        loadWaypoint();
    }
}

function refresh() {
    if (state.tab === 'players') loadPlayers();
    else if (state.tab === 'bans') loadBans();
    else loadWaypoint();
}

function rerender() {
    if (state.tab === 'players') renderPlayers();
    else if (state.tab === 'bans') renderBans();
}

/* ------------------------------------------------------------------ */
/* Otwieranie / zamykanie                                              */
/* ------------------------------------------------------------------ */

function openPanel(data) {
    state.open = true;
    state.perms = new Set(data.permissions || []);
    state.players = [];
    state.bans = [];
    state.selectedId = null;
    state.details = null;
    state.self = data.self || {};
    state.selfId = data.id ?? null;
    state.waypoint = null;

    els.adminName.textContent = data.admin || '—';
    els.root.classList.remove('hidden');

    closeModal();
    setTab('players');

    if (can('ban')) {
        loadBans();
    }
}

function hidePanel() {
    state.open = false;
    els.root.classList.add('hidden');
    closeModal();
}

function requestClose() {
    hidePanel();
    post('close');
}

/* ------------------------------------------------------------------ */
/* Legenda noclipa (lewy dolny rog)                                    */
/* ------------------------------------------------------------------ */

const hudEl = $('hud');

function hudKey(keys, text) {
    return h('div', { class: 'hud-row' }, h('kbd', {}, keys), h('span', {}, text));
}

function renderHud(data) {
    if (!data.visible) {
        hudEl.classList.add('hidden');
        hudEl.replaceChildren();

        return;
    }

    hudEl.replaceChildren(
        h('div', { class: 'hud-title' }, 'NOCLIP'),
        h(
            'div',
            { class: 'hud-levels' },
            (data.levels || []).map((name, index) =>
                h(
                    'div',
                    { class: 'hud-level' + (index + 1 === data.level ? ' active' : '') },
                    h('kbd', {}, String(index + 1)),
                    h('span', {}, name)
                )
            )
        ),
        hudKey('W A S D', 'Ruch'),
        hudKey('Spacja', 'W górę'),
        hudKey('Ctrl', 'W dół'),
        hudKey('Scroll / 1–4', 'Prędkość')
    );

    hudEl.classList.remove('hidden');
}

window.addEventListener('message', (event) => {
    const data = event.data;

    if (!data || !data.action) return;

    if (data.action === 'open') openPanel(data);
    if (data.action === 'close') hidePanel();
    if (data.action === 'noclipHud') renderHud(data);
});

window.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || !state.open) return;

    if (state.modal) closeModal();
    else requestClose();
});

els.search.addEventListener('input', rerender);
$('refresh').addEventListener('click', refresh);
$('close').addEventListener('click', requestClose);

// Auto-odswiezanie listy graczy (gdy nic nie jest w trakcie edycji).
setInterval(() => {
    if (state.open && state.tab === 'players' && !state.modal) {
        loadPlayers();
    }
}, 5000);
