Admin = Admin or {}

function Admin.CountWarns(license)
    local ok, count = Admin.DB(
        'scalar',
        'SELECT COUNT(*) FROM mono_warns WHERE license = ? AND revoked = 0',
        { license }
    )

    return ok and (tonumber(count) or 0) or 0
end

function Admin.GetWarns(license, limit)
    local ok, rows = Admin.DB(
        'query',
        [[
            SELECT id, reason, warned_by_name, created_at
            FROM mono_warns
            WHERE license = ? AND revoked = 0
            ORDER BY id DESC
            LIMIT ?
        ]],
        { license, limit or 20 }
    )

    if not ok then
        return {}
    end

    return rows or {}
end

function Admin.WarnPlayer(adminSource, targetSource, reason)
    local license = GetPlayerIdentifierByType(targetSource, 'license')

    if not license then
        return nil, 'license_not_found'
    end

    local admin = Admin.Actor(adminSource)

    local ok, warnId = Admin.DB(
        'insert',
        [[
            INSERT INTO mono_warns
                (license, player_name, reason, warned_by_name, warned_by_license, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        ]],
        {
            license,
            GetPlayerName(targetSource) or 'unknown',
            reason,
            admin.name,
            admin.license,
            os.time()
        }
    )

    if not ok or not warnId then
        return nil, 'database_error'
    end

    local count = Admin.CountWarns(license)

    TriggerClientEvent('mono_admin:warned', targetSource, {
        reason = reason,
        count = count
    })

    return { id = tonumber(warnId), count = count }
end
