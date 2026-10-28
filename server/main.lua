local lastCall = {} -- [src] = { [akcja] = czas }
local coordsEnabled = {} -- [src] = widocznosc lokalnego overlayu koordynatow

local function IsRateLimited(src, key)
    local calls = lastCall[src] or {}
    local now = GetGameTimer()

    lastCall[src] = calls

    if calls[key] and (now - calls[key]) < Config.NetCooldownMs then
        return true
    end

    calls[key] = now

    return false
end

-- Jedyny punkt wejscia z klienta. Klient NIGDY nie decyduje o uprawnieniach.
RegisterNetEvent('mono_admin:request', function(reqId, name, payload)
    local src = source

    if type(reqId) ~= 'number' or type(name) ~= 'string' then
        return
    end

    local function reply(result)
        TriggerClientEvent('mono_admin:response', src, reqId, result)
    end

    local handler = Admin.Handlers[name]

    if not handler then
        return reply({ ok = false, error = 'unknown_action' })
    end

    if not Admin.Can(src, handler.perm) then
        print(('[MONO_ADMIN] Odmowa dostepu: %s [%s] -> %s'):format(
            GetPlayerName(src) or 'unknown',
            src,
            name
        ))

        return reply({ ok = false, error = 'no_permission' })
    end

    if IsRateLimited(src, name) then
        return reply({ ok = false, error = 'rate_limited' })
    end

    if not Admin.WaitForDatabase(5000) then
        return reply({ ok = false, error = 'database_error' })
    end

    local ok, result, err = pcall(
        handler.fn,
        src,
        type(payload) == 'table' and payload or {}
    )

    if not ok then
        print(('[MONO_ADMIN] Blad handlera %s: %s'):format(name, tostring(result)))

        return reply({ ok = false, error = 'internal_error' })
    end

    if result == nil then
        return reply({ ok = false, error = err or 'unknown_error' })
    end

    reply({ ok = true, data = result })
end)

AddEventHandler('playerDropped', function()
    lastCall[source] = nil
    coordsEnabled[source] = nil
end)

RegisterNetEvent('mono_admin:coordsSync', function()
    local src = source
    local allowed = false

    pcall(function()
        allowed = Admin.Can(src, 'coords')
    end)

    if not allowed then
        coordsEnabled[src] = nil
        return TriggerClientEvent('mono_admin:coordsMode', src, false)
    end

    TriggerClientEvent('mono_admin:coordsMode', src, coordsEnabled[src] == true)
end)

-- Awaryjny unban z konsoli serwera: monounban <id_bana>
RegisterCommand('monounban', function(src, args)
    if src ~= 0 then
        return
    end

    local banId = Admin.ToInteger(args[1])

    if not banId then
        return print('[MONO_ADMIN] Uzycie: monounban [id_bana]')
    end

    Admin.WaitForBans(5000)

    local ban, err = Admin.Unban(0, banId)

    if not ban then
        return print(('[MONO_ADMIN] Nie udalo sie: %s'):format(tostring(err)))
    end

    Admin.Log(0, 'unban', { name = ban.player_name, license = ban.license }, ('ban #%d (konsola)'):format(banId))
end, true)

local function AdminCommandReply(src, ok, message)
    if src == 0 then
        return print(('[MONO_ADMIN] %s'):format(message))
    end

    TriggerClientEvent('mono_admin:commandResult', src, ok == true, message)
end

local function RunTargetCommand(rawSource, args, command, permission, handlerName, successMessage)
    local src = tonumber(rawSource) or 0

    local permissionOk, allowed = pcall(function()
        return Admin.Can(src, permission)
    end)

    if not permissionOk or not allowed then
        return AdminCommandReply(src, false, ('Nie masz uprawnień do komendy /%s.'):format(command))
    end

    local target = Admin.ToInteger(args and args[1])

    if not target or target < 1 then
        return AdminCommandReply(src, false, ('Użycie: /%s [ID gracza]'):format(command))
    end

    if not GetPlayerName(target) then
        return AdminCommandReply(src, false, ('Nie znaleziono gracza o ID %d.'):format(target))
    end

    if IsRateLimited(src, command .. '_command') then
        return AdminCommandReply(src, false, 'Odczekaj chwilę przed kolejnym użyciem komendy.')
    end

    if not Admin.WaitForDatabase(5000) then
        return AdminCommandReply(src, false, 'Baza danych nie jest gotowa; akcja nie została wykonana.')
    end

    local handler = Admin.Handlers[handlerName]
    local ok, result, err = pcall(handler.fn, src, { id = target })

    if not ok then
        print(('[MONO_ADMIN] Błąd komendy /%s: %s'):format(command, tostring(result)))
        return AdminCommandReply(src, false, ('Wystąpił błąd podczas /%s.'):format(command))
    end

    if not result then
        local messages = {
            player_not_found = ('Nie znaleziono gracza o ID %d.'):format(target),
            target_immune = 'Ten gracz jest chroniony przed akcjami administracyjnymi.',
            cannot_target_self = 'Nie możesz użyć tej komendy na sobie.'
        }

        return AdminCommandReply(src, false, messages[err] or ('Nie udało się wykonać /%s.'):format(command))
    end

    AdminCommandReply(src, true, ('%s (ID %d).'):format(successMessage, target))
end

-- Komendy korzystają z handlerów panelu, więc mają te same reguły i logowanie.
RegisterCommand('heal', function(src, args)
    RunTargetCommand(src, args, 'heal', 'heal', 'heal', 'Uleczono gracza')
end, false)

RegisterCommand('slay', function(src, args)
    RunTargetCommand(src, args, 'slay', 'slay', 'slay', 'Uśmiercono gracza')
end, false)

-- /coords przełącza lokalny overlay. Uprawnienie jest sprawdzane po stronie serwera.
RegisterCommand('coords', function(rawSource)
    local src = tonumber(rawSource) or 0

    if src == 0 then
        return AdminCommandReply(src, false, 'Komendy /coords można użyć tylko w grze.')
    end

    local permissionOk, allowed = pcall(function()
        return Admin.Can(src, 'coords')
    end)

    if not permissionOk or not allowed then
        return AdminCommandReply(src, false, 'Nie masz uprawnień do komendy /coords.')
    end

    if IsRateLimited(src, 'coords_command') then
        return AdminCommandReply(src, false, 'Odczekaj chwilę przed kolejnym użyciem /coords.')
    end

    coordsEnabled[src] = not coordsEnabled[src]
    TriggerClientEvent('mono_admin:coordsMode', src, coordsEnabled[src])

    AdminCommandReply(src, true, coordsEnabled[src]
        and 'Koordynaty włączone.'
        or 'Koordynaty wyłączone.')
end, false)
