Admin = Admin or {}

local allowedPrefixes = {}

for _, prefix in ipairs(Config.Bans.Identifiers) do
    allowedPrefixes[prefix] = true
end

if Config.Bans.UseIp then
    allowedPrefixes.ip = true
end

-- "2", "2.0", 2 -> 2 | "abc", 1.5, nil -> nil
function Admin.ToInteger(value)
    local number = tonumber(value)

    return number and math.tointeger(number)
end

-- Kontrola uprawnien przez ACE (mono_core). np. Admin.Can(src, 'ban')
function Admin.Can(source, permission)
    return exports.mono_core:HasPermission(source, 'mono_admin.' .. permission)
end

function Admin.GetIdentifiers(source)
    local identifiers = {}

    for index = 0, GetNumPlayerIdentifiers(source) - 1 do
        local identifier = GetPlayerIdentifier(source, index)
        local prefix = identifier and identifier:match('^(%w+):')

        if prefix and allowedPrefixes[prefix] then
            identifiers[#identifiers + 1] = identifier
        end
    end

    return identifiers
end

function Admin.GetTokens(source)
    local tokens = {}

    for index = 0, GetNumPlayerTokens(source) - 1 do
        local token = GetPlayerToken(source, index)

        if token then
            tokens[#tokens + 1] = token
        end
    end

    return tokens
end

function Admin.FindIdentifier(identifiers, prefix)
    local start = prefix .. ':'

    for _, identifier in ipairs(identifiers) do
        if identifier:sub(1, #start) == start then
            return identifier
        end
    end

    return nil
end

-- Opis osoby do logow/DB. source 0 = konsola serwera.
function Admin.Actor(source)
    if not source or source == 0 then
        return { name = 'Konsola', license = nil }
    end

    return {
        name = GetPlayerName(source) or 'unknown',
        license = GetPlayerIdentifierByType(source, 'license')
    }
end

function Admin.GetCharacter(source)
    local ok, character = pcall(function()
        return exports.mono_core:GetActiveCharacter(source)
    end)

    return ok and character or nil
end

-- Zwraca oczyszczony powod albo nil, gdy jest nieprawidlowy.
function Admin.CleanReason(value)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:gsub('%c', ' '):match('^%s*(.-)%s*$')

    local length = utf8.len(value)

    if not length
        or length < Config.Reason.Min
        or length > Config.Reason.Max
    then
        return nil
    end

    return value
end

function Admin.FormatDuration(seconds)
    if seconds <= 0 then
        return 'permanentnie'
    end

    local days = seconds // 86400
    local hours = (seconds % 86400) // 3600
    local minutes = (seconds % 3600) // 60

    local parts = {}

    if days > 0 then parts[#parts + 1] = ('%d d'):format(days) end
    if hours > 0 then parts[#parts + 1] = ('%d h'):format(hours) end
    if minutes > 0 then parts[#parts + 1] = ('%d min'):format(minutes) end

    if #parts == 0 then
        return '<1 min'
    end

    return table.concat(parts, ' ')
end
