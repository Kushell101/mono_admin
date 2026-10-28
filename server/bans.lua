Admin = Admin or {}

local ActiveBans = {} -- [banId] = ban
local Index = {}      -- [identyfikator lub token] = banId
local loaded = false

local function IsActive(ban, now)
    return ban.expires_at == 0 or ban.expires_at > now
end

local function Rebuild()
    local now = os.time()

    Index = {}

    for banId, ban in pairs(ActiveBans) do
        if not IsActive(ban, now) then
            ActiveBans[banId] = nil
        else
            for _, value in ipairs(ban.identifiers) do
                Index[value] = banId
            end

            for _, value in ipairs(ban.tokens) do
                Index[value] = banId
            end
        end
    end
end

local function BuildBanMessage(ban)
    local expires = ban.expires_at == 0
        and 'nigdy (ban permanentny)'
        or os.date('%Y-%m-%d %H:%M', ban.expires_at)

    return ('Zostałeś zbanowany na tym serwerze.\n\nPowód: %s\nWygasa: %s\nID bana: #%s'):format(
        ban.reason,
        expires,
        ban.id
    )
end

function Admin.LoadBans()
    local ok, rows = Admin.DB(
        'query',
        [[
            SELECT id, license, identifiers, tokens, player_name, reason,
                   banned_by_name, created_at, expires_at
            FROM mono_bans
            WHERE revoked = 0 AND (expires_at = 0 OR expires_at > ?)
        ]],
        { os.time() }
    )

    if not ok then
        return false
    end

    ActiveBans = {}

    for _, row in ipairs(rows or {}) do
        row.id = tonumber(row.id)
        row.created_at = tonumber(row.created_at) or 0
        row.expires_at = tonumber(row.expires_at) or 0
        row.identifiers = json.decode(row.identifiers or '[]') or {}
        row.tokens = json.decode(row.tokens or '[]') or {}

        ActiveBans[row.id] = row
    end

    Rebuild()

    loaded = true

    local count = 0
    for _ in pairs(ActiveBans) do count = count + 1 end

    print(('[MONO_ADMIN] Zaladowano aktywne bany: %d'):format(count))

    return true
end

function Admin.WaitForBans(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 15000)

    while not loaded and GetGameTimer() < deadline do
        Wait(50)
    end

    return loaded
end

function Admin.FindBan(identifiers, tokens)
    local now = os.time()

    local function check(list)
        for _, value in ipairs(list) do
            local banId = Index[value]
            local ban = banId and ActiveBans[banId]

            if ban and IsActive(ban, now) then
                return ban
            end
        end
    end

    return check(identifiers) or check(tokens)
end

-- duration w sekundach, 0 = permanentny
function Admin.BanPlayer(adminSource, targetSource, reason, duration)
    local identifiers = Admin.GetIdentifiers(targetSource)
    local tokens = Config.Bans.UseTokens and Admin.GetTokens(targetSource) or {}
    local license = Admin.FindIdentifier(identifiers, 'license')

    if not license then
        return nil, 'license_not_found'
    end

    local admin = Admin.Actor(adminSource)
    local now = os.time()
    local expires = duration > 0 and (now + duration) or 0
    local name = GetPlayerName(targetSource) or 'unknown'

    local ok, banId = Admin.DB(
        'insert',
        [[
            INSERT INTO mono_bans
                (license, identifiers, tokens, player_name, reason,
                 banned_by_name, banned_by_license, created_at, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]],
        {
            license,
            json.encode(identifiers),
            json.encode(tokens),
            name,
            reason,
            admin.name,
            admin.license,
            now,
            expires
        }
    )

    banId = tonumber(banId)

    if not ok or not banId or banId < 1 then
        return nil, 'database_error'
    end

    local ban = {
        id = banId,
        license = license,
        identifiers = identifiers,
        tokens = tokens,
        player_name = name,
        reason = reason,
        banned_by_name = admin.name,
        created_at = now,
        expires_at = expires
    }

    ActiveBans[banId] = ban
    Rebuild()

    DropPlayer(targetSource, BuildBanMessage(ban))

    return banId
end

function Admin.Unban(adminSource, banId)
    local ban = ActiveBans[banId]

    if not ban then
        return nil, 'ban_not_found'
    end

    local admin = Admin.Actor(adminSource)

    local ok = Admin.DB(
        'update',
        'UPDATE mono_bans SET revoked = 1, revoked_by = ?, revoked_at = ? WHERE id = ? AND revoked = 0',
        { admin.name, os.time(), banId }
    )

    if not ok then
        return nil, 'database_error'
    end

    ActiveBans[banId] = nil
    Rebuild()

    return ban
end

function Admin.ListBans()
    local now = os.time()
    local list = {}

    for _, ban in pairs(ActiveBans) do
        if IsActive(ban, now) then
            list[#list + 1] = {
                id = ban.id,
                player_name = ban.player_name,
                license = ban.license,
                reason = ban.reason,
                banned_by_name = ban.banned_by_name,
                created_at = ban.created_at,
                expires_at = ban.expires_at
            }
        end
    end

    table.sort(list, function(a, b)
        return a.id > b.id
    end)

    -- Limit, zeby nie wysylac setek tysiecy rekordow przez net event.
    for index = #list, 301, -1 do
        list[index] = nil
    end

    return list
end

-- Blokada przy wejsciu na serwer.
AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source

    deferrals.defer()
    Wait(0)
    deferrals.update('Sprawdzanie blokad...')

    if not Admin.WaitForBans(15000) then
        return deferrals.done('Serwer jeszcze się uruchamia. Spróbuj ponownie za chwilę.')
    end

    local ban = Admin.FindBan(
        Admin.GetIdentifiers(src),
        Config.Bans.UseTokens and Admin.GetTokens(src) or {}
    )

    if ban then
        return deferrals.done(BuildBanMessage(ban))
    end

    deferrals.done()
end)

-- Odswiezanie cache'u (wygasniete bany) co minute.
CreateThread(function()
    Admin.WaitForDatabase()
    Admin.LoadBans()

    while true do
        Wait(60000)
        Rebuild()
    end
end)
