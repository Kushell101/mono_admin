-- =====================================================================
-- mono_admin | server/handlers.lua
-- Kazda akcja panelu = wpis w tabeli Handlers:
--   perm = 'kick'  ->  wymaga ACE mono_admin.kick
--   fn(src, data)  ->  zwraca dane (tabela) ALBO nil, 'kod_bledu'
-- Uprawnienia, rate limit i pcall robi dispatcher w main.lua.
-- =====================================================================

Admin = Admin or {}
Admin.Handlers = {}

local H = Admin.Handlers

-- Uprawnienia, ktore UI musi znac, zeby pokazac/ukryc przyciski.
local UI_PERMISSIONS = {
    'kick', 'warn', 'ban', 'unban',
    'teleport', 'heal', 'freeze', 'spectate',
    'noclip', 'godmode', 'invisible',
    'giveitem'
}

local FEATURES = { noclip = true, godmode = true, invisible = true }

-- Wspolna walidacja celu akcji (gracz online).
-- opts.allowSelf    - akcja dozwolona na sobie (np. heal)
-- opts.ignoreImmune - akcja nieszkodliwa (heal, goto, spectate) - immune nie blokuje
local function ResolveTarget(src, data, opts)
    opts = opts or {}

    local target = Admin.ToInteger(data.id)

    if not target or not GetPlayerName(target) then
        return nil, 'player_not_found'
    end

    if target == src then
        if opts.allowSelf or Config.AllowSelfTarget then
            return target
        end

        return nil, 'cannot_target_self'
    end

    if not opts.ignoreImmune and Admin.Can(target, 'immune') then
        return nil, 'target_immune'
    end

    return target
end

local function GetPedCoords(source)
    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then
        return nil
    end

    return GetEntityCoords(ped)
end

local function IsFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function FeatureState(source)
    local state = Player(source).state

    return {
        noclip = state.mono_admin_noclip == true,
        godmode = state.mono_admin_godmode == true,
        invisible = state.mono_admin_invisible == true
    }
end

H.open = {
    perm = 'open',
    fn = function(src)
        if Config.RequireCharacter and not Admin.GetCharacter(src) then
            return nil, 'not_in_game'
        end

        local allowed = {}

        for _, permission in ipairs(UI_PERMISSIONS) do
            if Admin.Can(src, permission) then
                allowed[#allowed + 1] = permission
            end
        end

        return {
            id = src,
            admin = GetPlayerName(src),
            permissions = allowed,
            self = FeatureState(src)
        }
    end
}

-- /admin (tryb skrotow): serwer potwierdza, ze admin ma prawo do noclipa / godmode'a.
H.quickMode = {
    perm = 'open',
    fn = function(src)
        if Config.RequireCharacter and not Admin.GetCharacter(src) then
            return nil, 'not_in_game'
        end

        local noclip = Admin.Can(src, 'noclip')
        local godmode = Admin.Can(src, 'godmode')

        if not noclip and not godmode then
            return nil, 'no_permission'
        end

        return { noclip = noclip, godmode = godmode }
    end
}

H.getPlayers = {
    perm = 'open',
    fn = function()
        local list = {}

        for _, value in ipairs(GetPlayers()) do
            local id = tonumber(value)
            local character = Admin.GetCharacter(id)

            list[#list + 1] = {
                id = id,
                name = GetPlayerName(id) or 'unknown',
                character = character
                    and ('%s %s'):format(character.first_name, character.last_name)
                    or nil,
                ping = GetPlayerPing(id)
            }
        end

        table.sort(list, function(a, b)
            return a.id < b.id
        end)

        return list
    end
}

H.getPlayerDetails = {
    perm = 'open',
    fn = function(_, data)
        local target = Admin.ToInteger(data.id)

        if not target or not GetPlayerName(target) then
            return nil, 'player_not_found'
        end

        local character = Admin.GetCharacter(target)
        local license = GetPlayerIdentifierByType(target, 'license')

        return {
            id = target,
            name = GetPlayerName(target),
            ping = GetPlayerPing(target),
            character = character and {
                first_name = character.first_name,
                last_name = character.last_name,
                date_of_birth = character.date_of_birth,
                gender = character.gender
            } or nil,
            identifiers = Admin.GetIdentifiers(target),
            warnCount = license and Admin.CountWarns(license) or 0,
            warns = license and Admin.GetWarns(license, 10) or {}
        }
    end
}

H.kick = {
    perm = 'kick',
    fn = function(src, data)
        local target, err = ResolveTarget(src, data)

        if not target then
            return nil, err
        end

        local reason = Admin.CleanReason(data.reason)

        if not reason then
            return nil, 'invalid_reason'
        end

        local targetInfo = Admin.Actor(target)

        Admin.Log(src, 'kick', targetInfo, reason)

        DropPlayer(target, ('Zostałeś wyrzucony z serwera.\nPowód: %s'):format(reason))

        return { name = targetInfo.name }
    end
}

H.warn = {
    perm = 'warn',
    fn = function(src, data)
        local target, err = ResolveTarget(src, data)

        if not target then
            return nil, err
        end

        local reason = Admin.CleanReason(data.reason)

        if not reason then
            return nil, 'invalid_reason'
        end

        local result, warnErr = Admin.WarnPlayer(src, target, reason)

        if not result then
            return nil, warnErr
        end

        local targetInfo = Admin.Actor(target)

        Admin.Log(src, 'warn', targetInfo, ('%s | aktywne ostrzezenia: %d'):format(reason, result.count))

        return { name = targetInfo.name, count = result.count }
    end
}

H.ban = {
    perm = 'ban',
    fn = function(src, data)
        local target, err = ResolveTarget(src, data)

        if not target then
            return nil, err
        end

        local reason = Admin.CleanReason(data.reason)

        if not reason then
            return nil, 'invalid_reason'
        end

        local duration = Admin.ToInteger(data.duration)

        if not duration or duration < 0 or duration > Config.Bans.MaxDuration then
            return nil, 'invalid_duration'
        end

        local targetInfo = Admin.Actor(target)

        local banId, banErr = Admin.BanPlayer(src, target, reason, duration)

        if not banId then
            return nil, banErr
        end

        Admin.Log(src, 'ban', targetInfo, ('%s | %s | ban #%d'):format(
            reason,
            Admin.FormatDuration(duration),
            banId
        ))

        return { id = banId, name = targetInfo.name }
    end
}

H.getBans = {
    perm = 'ban',
    fn = function()
        return Admin.ListBans()
    end
}

H.unban = {
    perm = 'unban',
    fn = function(src, data)
        local banId = Admin.ToInteger(data.id)

        if not banId then
            return nil, 'ban_not_found'
        end

        local ban, err = Admin.Unban(src, banId)

        if not ban then
            return nil, err
        end

        Admin.Log(
            src,
            'unban',
            { name = ban.player_name, license = ban.license },
            ('ban #%d'):format(banId)
        )

        return { id = banId, name = ban.player_name }
    end
}

-- ---------------------------------------------------------------------
-- Etap 2: narzedzia (ja)
-- ---------------------------------------------------------------------

-- Przelaczniki: noclip / godmode / invisible. Stan trzymamy w state bagu gracza
-- (inne zasoby moga go odczytac, np. anty-cheat nie flaguje admina w noclipie).
H.toggleFeature = {
    perm = 'open',
    fn = function(src, data)
        local feature = data.feature

        if type(feature) ~= 'string' or not FEATURES[feature] then
            return nil, 'unknown_feature'
        end

        if not Admin.Can(src, feature) then
            return nil, 'no_permission'
        end

        local key = 'mono_admin_' .. feature
        local state = Player(src).state
        local enabled = state[key] ~= true

        state:set(key, enabled, true)

        TriggerClientEvent('mono_admin:feature', src, feature, enabled)

        Admin.Log(src, feature, nil, enabled and 'on' or 'off')

        return { feature = feature, enabled = enabled }
    end
}

H.teleportWaypoint = {
    perm = 'teleport',
    fn = function(src)
        TriggerClientEvent('mono_admin:teleportWaypoint', src)

        Admin.Log(src, 'tp_waypoint')

        return {}
    end
}

H.teleportCoords = {
    perm = 'teleport',
    fn = function(src, data)
        local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)

        if not (IsFiniteNumber(x) and IsFiniteNumber(y) and IsFiniteNumber(z))
            or math.abs(x) > 10000.0
            or math.abs(y) > 10000.0
            or z < -500.0
            or z > 2500.0
        then
            return nil, 'invalid_coords'
        end

        TriggerClientEvent('mono_admin:teleport', src, x + 0.0, y + 0.0, z + 0.0)

        Admin.Log(src, 'tp_coords', nil, ('%.1f, %.1f, %.1f'):format(x, y, z))

        return {}
    end
}

-- ---------------------------------------------------------------------
-- Etap 2: akcje na graczach
-- ---------------------------------------------------------------------

H.heal = {
    perm = 'heal',
    fn = function(src, data)
        local target, err = ResolveTarget(src, data, { allowSelf = true, ignoreImmune = true })

        if not target then
            return nil, err
        end

        TriggerClientEvent('mono_admin:heal', target)
        TriggerClientEvent('mono_bw:revivedByAdmin', target)

        local info = Admin.Actor(target)

        Admin.Log(src, 'heal', info)

        return { name = info.name }
    end
}

H.slay = {
    perm = 'slay',
    fn = function(src, data)
        -- Slay jest akcją szkodliwą: nie pozwalamy celować w siebie ani w immune.
        local target, err = ResolveTarget(src, data)

        if not target then
            return nil, err
        end

        TriggerClientEvent('mono_admin:slay', target)

        local info = Admin.Actor(target)

        Admin.Log(src, 'slay', info)

        return { name = info.name }
    end
}

-- Admin -> do gracza
H.teleportToPlayer = {
    perm = 'teleport',
    fn = function(src, data)
        local target, err = ResolveTarget(src, data, { ignoreImmune = true })

        if not target then
            return nil, err
        end

        local coords = GetPedCoords(target)

        if not coords then
            return nil, 'no_ped'
        end

        TriggerClientEvent('mono_admin:teleport', src, coords.x, coords.y, coords.z)

        local info = Admin.Actor(target)

        Admin.Log(src, 'goto', info)

        return { name = info.name }
    end
}

-- Gracz -> do admina
H.bringPlayer = {
    perm = 'teleport',
    fn = function(src, data)
        local target, err = ResolveTarget(src, data)

        if not target then
            return nil, err
        end

        local coords = GetPedCoords(src)

        if not coords then
            return nil, 'no_ped'
        end

        TriggerClientEvent('mono_admin:teleport', target, coords.x, coords.y, coords.z)

        local info = Admin.Actor(target)

        Admin.Log(src, 'bring', info)

        return { name = info.name }
    end
}

-- Admin -> gracz na JEGO waypoint (np. przy bugu mapy u gracza).
-- Waypoint zna tylko klient gracza, wiec serwer wysyla mu event z tokenem i czeka
-- na krotkie potwierdzenie: 'started' | 'no_waypoint' | 'out_of_map' | 'busy'.
-- Sam teleport (szukanie podloza) trwa dalej po stronie gracza i nie blokuje odpowiedzi.
local WAYPOINT_ACK_TIMEOUT_MS = 5000

-- Whitelista: z klienta nie przepuszczamy dowolnych kodow bledu do UI.
local WAYPOINT_ACK_ERRORS = {
    no_waypoint = 'target_no_waypoint',
    out_of_map = 'target_waypoint_out_of_map',
    busy = 'target_busy'
}

local waypointRequests = {} -- [token] = { target = serverId, promise = promise }
local nextWaypointToken = 0

local function FinishWaypointRequest(token, status)
    local request = waypointRequests[token]

    if not request then
        return
    end

    waypointRequests[token] = nil
    request.promise:resolve(status)
end

RegisterNetEvent('mono_admin:waypointAck', function(token, status)
    local src = source

    if type(token) ~= 'number' or type(status) ~= 'string' then
        return
    end

    local request = waypointRequests[token]

    -- Odpowiedz przyjmujemy wylacznie od gracza, ktoremu wyslalismy ten token.
    if not request or request.target ~= src then
        return
    end

    FinishWaypointRequest(token, status)
end)

AddEventHandler('playerDropped', function()
    local src = source

    for token, request in pairs(waypointRequests) do
        if request.target == src then
            FinishWaypointRequest(token, 'dropped')
        end
    end
end)

H.teleportPlayerToWaypoint = {
    perm = 'teleport',
    fn = function(src, data)
        -- Jak "Przyciagnij": gracz jest przemieszczany, wiec immune go chroni.
        local target, err = ResolveTarget(src, data)

        if not target then
            return nil, err
        end

        local info = Admin.Actor(target)

        nextWaypointToken = nextWaypointToken + 1

        local token = nextWaypointToken
        local answer = promise.new()

        waypointRequests[token] = { target = target, promise = answer }

        SetTimeout(WAYPOINT_ACK_TIMEOUT_MS, function()
            FinishWaypointRequest(token, 'no_response')
        end)

        TriggerClientEvent('mono_admin:teleportWaypoint', target, token)

        local status = Citizen.Await(answer)

        if status == 'dropped' then
            return nil, 'player_not_found'
        end

        if status ~= 'started' then
            return nil, WAYPOINT_ACK_ERRORS[status] or 'target_no_response'
        end

        Admin.Log(src, 'tp_player_waypoint', info)

        return { name = info.name }
    end
}

H.freeze = {
    perm = 'freeze',
    fn = function(src, data)
        local target, err = ResolveTarget(src, data)

        if not target then
            return nil, err
        end

        local state = Player(target).state
        local enabled = state.mono_admin_frozen ~= true

        state:set('mono_admin_frozen', enabled, true)

        TriggerClientEvent('mono_admin:freeze', target, enabled)

        local info = Admin.Actor(target)

        Admin.Log(src, enabled and 'freeze' or 'unfreeze', info)

        return { name = info.name, enabled = enabled }
    end
}

H.spectate = {
    perm = 'spectate',
    fn = function(src, data)
        local target, err = ResolveTarget(src, data, { ignoreImmune = true })

        if not target or target == src then
            return nil, err or 'cannot_target_self'
        end

        local coords = GetPedCoords(target)

        if not coords then
            return nil, 'no_ped'
        end

        TriggerClientEvent('mono_admin:spectate', src, target, coords.x, coords.y, coords.z)

        local info = Admin.Actor(target)

        Admin.Log(src, 'spectate', info)

        return { name = info.name }
    end
}

-- ---------------------------------------------------------------------
-- Etap 3: bronie (kolko wyboru broni GTA, do czasu wlasnego ekwipunku)
-- Serwer sprawdza uprawnienie i biala liste modeli, a bron dodaje klient admina.
-- ---------------------------------------------------------------------

local WEAPON_PREFIXES = { '', 'weapon_', 'gadget_' }
local weaponLookup = {}

for _, name in ipairs(Config.Weapons.List) do
    weaponLookup[name] = true
end

-- "WEAPON_PISTOL", "weapon_pistol", "pistol" -> 'weapon_pistol' | nil (spoza bialej listy)
local function ResolveWeaponName(value)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:lower():match('^%s*(.-)%s*$')

    for _, prefix in ipairs(WEAPON_PREFIXES) do
        local candidate = prefix .. value

        if weaponLookup[candidate] then
            return candidate
        end
    end

    return nil
end

local function IsInGame(src)
    return not Config.RequireCharacter or Admin.GetCharacter(src) ~= nil
end

-- /giveweapon [model_broni] [amunicja]
H.giveWeapon = {
    perm = 'giveitem',
    fn = function(src, data)
        if not IsInGame(src) then
            return nil, 'not_in_game'
        end

        local weapon = ResolveWeaponName(data.weapon)

        if not weapon then
            return nil, 'unknown_weapon'
        end

        local ammo = Config.Weapons.DefaultAmmo

        if data.ammo ~= nil then
            ammo = Admin.ToInteger(data.ammo)
        end

        if not ammo or ammo < 0 or ammo > Config.Weapons.MaxAmmo then
            return nil, 'invalid_ammo'
        end

        local added = exports['mono_inventory']:AddItem(src, weapon, 1)
        if added ~= 1 then
            return nil, 'inventory_add_failed'
        end

        local ammoItem = Config.Weapons.InventoryAmmoItems[weapon]
        local ammoAdded = 0

        if ammoItem and ammo > 0 then
            ammoAdded = exports['mono_inventory']:AddItem(src, ammoItem, ammo)
        end

        Admin.Log(src, 'giveitem', nil, ('%s | amunicja: %d/%d%s'):format(
            weapon,
            ammoAdded,
            ammo,
            ammoItem and (' | przedmiot: ' .. ammoItem) or ' | brak amunicji dla tej broni'
        ))

        return {
            weapon = weapon,
            ammoItem = ammoItem,
            ammoRequested = ammo,
            ammoAdded = ammoAdded
        }
    end
}

-- Przycisk "Dodaj wszystkie bronie" w panelu.
H.giveAllWeapons = {
    perm = 'giveitem',
    fn = function(src)
        if not IsInGame(src) then
            return nil, 'not_in_game'
        end

        TriggerClientEvent('mono_admin:giveAllWeapons', src, Config.Weapons.DefaultAmmo)

        Admin.Log(src, 'giveallweapons', nil, ('%d modeli | amunicja: %d'):format(
            #Config.Weapons.List,
            Config.Weapons.DefaultAmmo
        ))

        return {}
    end
}

-- ---------------------------------------------------------------------
-- Etap 4: pojazdy (/dv, /spawnv) - uprawnienie mono_admin.vehicle
-- ---------------------------------------------------------------------

-- /dv: klient znajduje pojazd przy postaci i podaje jego netId, a serwer sprawdza
-- uprawnienie, typ encji i odleglosc, po czym usuwa pojazd (dziala tez na pojazdy
-- kontrolowane przez innych graczy / ruch uliczny).
H.deleteVehicle = {
    perm = 'vehicle',
    fn = function(src, data)
        if not IsInGame(src) then
            return nil, 'not_in_game'
        end

        local netId = Admin.ToInteger(data.netId)

        if not netId or netId <= 0 then
            return nil, 'vehicle_not_found'
        end

        local vehicle = NetworkGetEntityFromNetworkId(netId)

        -- GetEntityType: 2 = pojazd
        if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
            return nil, 'vehicle_not_found'
        end

        local adminCoords = GetPedCoords(src)

        if not adminCoords or #(adminCoords - GetEntityCoords(vehicle)) > Config.Vehicles.ServerMaxDistance then
            return nil, 'vehicle_too_far'
        end

        -- Nazwa modelu pochodzi z klienta - tylko do logu, wiec czyscimy ja i skracamy.
        local model = type(data.model) == 'string' and data.model:gsub('[^%w_ %-]', ''):sub(1, 40) or '?'

        local plateOk, plate = pcall(GetVehicleNumberPlateText, vehicle)

        DeleteEntity(vehicle)

        Admin.Log(src, 'dv', nil, ('%s | tablica: %s'):format(
            model,
            plateOk and plate and plate:match('^%s*(.-)%s*$') or '?'
        ))

        return {}
    end
}

-- /spawnv [model]: serwer sprawdza uprawnienie i format nazwy, a pojazd tworzy klient
-- admina (tam sprawdzamy tez, czy model istnieje w grze).
H.spawnVehicle = {
    perm = 'vehicle',
    fn = function(src, data)
        if not IsInGame(src) then
            return nil, 'not_in_game'
        end

        local model = type(data.model) == 'string' and data.model:lower():match('^%s*(.-)%s*$')

        if not model or model == '' or #model > 40 or not model:match('^[%w_]+$') then
            return nil, 'invalid_model'
        end

        TriggerClientEvent('mono_admin:spawnVehicle', src, model)

        Admin.Log(src, 'spawnv', nil, model)

        return { model = model }
    end
}
