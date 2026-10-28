-- =====================================================================
-- mono_admin | server/database.lua
-- Wlasne, wersjonowane migracje (ta sama zasada co w mono_core:
-- nowa zmiana schematu = NOWA migracja na koncu listy).
-- =====================================================================

Admin = Admin or {}

local PREFIX = '[MONO_ADMIN][DB]'
local DEFAULT_WAIT_TIMEOUT_MS = 30000
local TABLE_OPTIONS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'

local state = 'pending' -- 'pending' | 'ready' | 'failed'

local function Log(message)
    print(('%s %s'):format(PREFIX, message))
end

-- kind: 'insert' | 'update' | 'query' | 'single' | 'scalar'
-- Zwraca: ok (boolean), wynik.
function Admin.DB(kind, sql, params)
    local ok, result = pcall(function()
        return MySQL[kind].await(sql, params or {})
    end)

    if not ok then
        Log(('Blad SQL: %s'):format(tostring(result)))
        return false, nil
    end

    return true, result
end

local MIGRATIONS = {
    {
        version = 1,
        name = 'baseline_tables',
        steps = {
            ([[
                CREATE TABLE IF NOT EXISTS mono_bans (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    license VARCHAR(64) NOT NULL,
                    identifiers LONGTEXT NOT NULL,
                    tokens LONGTEXT NOT NULL,
                    player_name VARCHAR(100) NOT NULL,
                    reason VARCHAR(255) NOT NULL,
                    banned_by_name VARCHAR(100) NOT NULL,
                    banned_by_license VARCHAR(64) NULL DEFAULT NULL,
                    created_at BIGINT UNSIGNED NOT NULL,
                    expires_at BIGINT UNSIGNED NOT NULL DEFAULT 0,
                    revoked TINYINT(1) NOT NULL DEFAULT 0,
                    revoked_by VARCHAR(100) NULL DEFAULT NULL,
                    revoked_at BIGINT UNSIGNED NULL DEFAULT NULL,
                    PRIMARY KEY (id),
                    KEY idx_mono_bans_license (license),
                    KEY idx_mono_bans_active (revoked, expires_at)
                ) %s
            ]]):format(TABLE_OPTIONS),

            ([[
                CREATE TABLE IF NOT EXISTS mono_warns (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    license VARCHAR(64) NOT NULL,
                    player_name VARCHAR(100) NOT NULL,
                    reason VARCHAR(255) NOT NULL,
                    warned_by_name VARCHAR(100) NOT NULL,
                    warned_by_license VARCHAR(64) NULL DEFAULT NULL,
                    created_at BIGINT UNSIGNED NOT NULL,
                    revoked TINYINT(1) NOT NULL DEFAULT 0,
                    PRIMARY KEY (id),
                    KEY idx_mono_warns_license (license, revoked)
                ) %s
            ]]):format(TABLE_OPTIONS),

            ([[
                CREATE TABLE IF NOT EXISTS mono_admin_logs (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    admin_name VARCHAR(100) NOT NULL,
                    admin_license VARCHAR(64) NULL DEFAULT NULL,
                    action VARCHAR(50) NOT NULL,
                    target_name VARCHAR(100) NULL DEFAULT NULL,
                    target_license VARCHAR(64) NULL DEFAULT NULL,
                    details TEXT NULL,
                    created_at BIGINT UNSIGNED NOT NULL,
                    PRIMARY KEY (id),
                    KEY idx_mono_admin_logs_created (created_at)
                ) %s
            ]]):format(TABLE_OPTIONS)
        }
    }
}

local function RunMigrations()
    local created = Admin.DB(
        'update',
        ([[
            CREATE TABLE IF NOT EXISTS mono_admin_migrations (
                version INT UNSIGNED NOT NULL,
                name VARCHAR(100) NOT NULL,
                applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (version)
            ) %s
        ]]):format(TABLE_OPTIONS)
    )

    if not created then
        return false
    end

    local ok, rows = Admin.DB('query', 'SELECT version FROM mono_admin_migrations')

    if not ok then
        return false
    end

    local applied = {}

    for _, row in ipairs(rows or {}) do
        applied[tonumber(row.version)] = true
    end

    table.sort(MIGRATIONS, function(a, b)
        return a.version < b.version
    end)

    local appliedNow = 0

    for _, migration in ipairs(MIGRATIONS) do
        if not applied[migration.version] then
            Log(('Migracja %03d: %s'):format(migration.version, migration.name))

            for index, step in ipairs(migration.steps) do
                local stepOk = Admin.DB('update', step)

                if not stepOk then
                    Log(('Migracja %03d (%s) nie powiodla sie na kroku %d. Zatrzymano.'):format(
                        migration.version,
                        migration.name,
                        index
                    ))

                    return false
                end
            end

            local recorded = Admin.DB(
                'update',
                'INSERT INTO mono_admin_migrations (version, name) VALUES (?, ?)',
                { migration.version, migration.name }
            )

            if not recorded then
                return false
            end

            appliedNow = appliedNow + 1
        end
    end

    Log(('Schemat bazy jest aktualny (wykonane migracje: %d).'):format(appliedNow))

    return true
end

function Admin.WaitForDatabase(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or DEFAULT_WAIT_TIMEOUT_MS)

    while state == 'pending' and GetGameTimer() < deadline do
        Wait(50)
    end

    return state == 'ready'
end

CreateThread(function()
    MySQL.ready(function()
        local ok, result = pcall(RunMigrations)

        if not ok then
            Log(('Nieoczekiwany blad migracji: %s'):format(tostring(result)))
        end

        state = (ok and result) and 'ready' or 'failed'

        if state == 'failed' then
            Log('MIGRACJE NIE POWIODLY SIE - panel admina jest zablokowany do czasu naprawy.')
        end
    end)
end)
