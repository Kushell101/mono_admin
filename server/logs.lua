Admin = Admin or {}

local PREFIX = '[MONO_ADMIN]'

local function SendWebhook(actor, action, target, details)
    local cfg = Config.Webhook

    if not cfg.Enabled or not cfg.Url or cfg.Url == '' then
        return
    end

    local lines = { ('**Admin:** %s'):format(actor.name) }

    if target.name then
        lines[#lines + 1] = ('**Cel:** %s'):format(target.name)
    end

    if details ~= '' then
        lines[#lines + 1] = ('**Szczegoly:** %s'):format(details)
    end

    PerformHttpRequest(
        cfg.Url,
        function() end,
        'POST',
        json.encode({
            username = cfg.Username,
            -- Nazwy graczy sa kontrolowane przez graczy - blokujemy @everyone itp.
            allowed_mentions = { parse = {} },
            embeds = {
                {
                    title = action:upper(),
                    description = table.concat(lines, '\n'),
                    color = 14067791,
                    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
                }
            }
        }),
        { ['Content-Type'] = 'application/json' }
    )
end

-- target: { name = ..., license = ... } albo nil
function Admin.Log(actorSource, action, target, details)
    local actor = Admin.Actor(actorSource)

    target = target or {}
    details = details or ''

    print(('%s [%s] %s -> %s | %s'):format(
        PREFIX,
        action:upper(),
        actor.name,
        target.name or '-',
        details
    ))

    MySQL.insert(
        [[
            INSERT INTO mono_admin_logs
                (admin_name, admin_license, action, target_name, target_license, details, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]],
        {
            actor.name,
            actor.license,
            action,
            target.name,
            target.license,
            details,
            os.time()
        }
    )

    SendWebhook(actor, action, target, details)
end
