local isOpen = false
local pending = {}
local nextRequestId = 0
local coordsVisible = false

local function Notify(text)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, true)
end

local function SetOpen(state)
    isOpen = state
    SetNuiFocus(state, state)
end

-- callback(result) zawsze zostanie wywolany dokladnie raz (odpowiedz albo timeout).
local function Request(name, payload, callback)
    nextRequestId = nextRequestId + 1

    local id = nextRequestId

    pending[id] = callback

    TriggerServerEvent('mono_admin:request', id, name, payload or {})

    SetTimeout(Config.RequestTimeoutMs, function()
        local cb = pending[id]

        if cb then
            pending[id] = nil
            cb({ ok = false, error = 'timeout' })
        end
    end)
end

RegisterNetEvent('mono_admin:response', function(id, result)
    local callback = pending[id]

    if not callback then
        return
    end

    pending[id] = nil
    callback(result)
end)

RegisterNetEvent('mono_admin:commandResult', function(ok, message)
    if type(message) ~= 'string' then
        return
    end

    Notify((ok == true and '~g~' or '~r~') .. message)
end)

RegisterNetEvent('mono_admin:coordsMode', function(enabled)
    coordsVisible = enabled == true
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        TriggerServerEvent('mono_admin:coordsSync')
    end
end)

CreateThread(function()
    while true do
        if coordsVisible then
            if not IsPauseMenuActive() then
                local ped = PlayerPedId()

                if ped ~= 0 and DoesEntityExist(ped) then
                    local coords = GetEntityCoords(ped)
                    local heading = GetEntityHeading(ped)
                    local text = ('X: %.3f\nY: %.3f\nZ: %.3f\nH: %.1f'):format(
                        coords.x, coords.y, coords.z, heading
                    )

                    SetTextFont(4)
                    SetTextScale(0.36, 0.36)
                    SetTextColour(255, 255, 255, 240)
                    SetTextOutline()
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(text)
                    EndTextCommandDisplayText(0.018, 0.20)
                end
            end

            Wait(0)
        else
            Wait(250)
        end
    end
end)

local ERROR_TEXT = {
    no_permission = 'Brak uprawnień.',
    not_in_game = 'Najpierw wybierz postać.',
    timeout = 'Serwer nie odpowiedział.',
    rate_limited = 'Zwolnij trochę.',
    database_error = 'Baza danych nie jest gotowa.',
    unknown_weapon = 'Nieznany model broni. Przykład: weapon_pistol.',
    invalid_ammo = ('Nieprawidłowa amunicja (0–%d).'):format(Config.Weapons.MaxAmmo),
    inventory_add_failed = 'Nie dodano broni: brak miejsca, aktywnego ekwipunku albo definicji przedmiotu.',
    vehicle_not_found = 'Nie znaleziono pojazdu (mógł już zniknąć).',
    vehicle_too_far = 'Pojazd jest zbyt daleko.',
    invalid_model = 'Nieprawidłowa nazwa modelu pojazdu.'
}

local function OpenPanel()
    if isOpen then
        return
    end

    Request('open', {}, function(result)
        if not result or not result.ok then
            return Notify(ERROR_TEXT[result and result.error] or 'Nie można otworzyć panelu.')
        end

        SetOpen(true)

        SendNUIMessage({
            action = 'open',
            id = result.data.id,
            admin = result.data.admin,
            permissions = result.data.permissions,
            self = result.data.self
        })
    end)
end

RegisterCommand(Config.Command, OpenPanel, false)

RegisterKeyMapping(Config.Command, 'Mono Admin: otwórz panel', 'keyboard', Config.DefaultKey)

-- ---------------------------------------------------------------------
-- Tryb szybkich skrotow: /admin wlacza/wylacza klawisze V (noclip) i C (godmode)
-- bez otwierania panelu. Uprawnienia sprawdza serwer przy KAZDYM przelaczeniu.
-- ---------------------------------------------------------------------

local quickMode = false

local QUICK_LABEL = {
    noclip = 'Noclip',
    godmode = 'God mode'
}

local function QuickToggle(feature)
    if not quickMode or isOpen then
        return
    end

    Request('toggleFeature', { feature = feature }, function(result)
        if not result or not result.ok then
            return Notify(ERROR_TEXT[result and result.error] or 'Nie można zmienić trybu.')
        end

        Notify(('%s: %s'):format(
            QUICK_LABEL[feature],
            result.data.enabled and '~g~włączony' or '~r~wyłączony'
        ))
    end)
end

RegisterCommand(Config.QuickCommand, function()
    if quickMode then
        quickMode = false

        return Notify('Skróty administratora: ~r~wyłączone~s~.')
    end

    Request('quickMode', {}, function(result)
        if not result or not result.ok then
            return Notify(ERROR_TEXT[result and result.error] or 'Brak uprawnień.')
        end

        quickMode = true

        Notify(('Skróty administratora: ~g~włączone~s~.\n%s'):format(
            ('Noclip: ~b~%s~s~  |  God mode: ~b~%s~s~'):format(Config.QuickKeys.noclip, Config.QuickKeys.godmode)
        ))
    end)
end, false)

RegisterCommand('mono_admin_quick_noclip', function()
    QuickToggle('noclip')
end, false)

RegisterCommand('mono_admin_quick_godmode', function()
    QuickToggle('godmode')
end, false)

RegisterKeyMapping('mono_admin_quick_noclip', 'Mono Admin: noclip (tryb /admin)', 'keyboard', Config.QuickKeys.noclip)
RegisterKeyMapping('mono_admin_quick_godmode', 'Mono Admin: god mode (tryb /admin)', 'keyboard', Config.QuickKeys.godmode)

-- V (zmiana kamery) i C (spojrzenie za siebie) nie moga odpalac sie razem ze skrotami.
CreateThread(function()
    while true do
        if quickMode and not isOpen then
            DisableControlAction(0, 0, true)
            DisableControlAction(0, 26, true)

            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ---------------------------------------------------------------------
-- /giveweapon [model_broni] [amunicja] - dodaje bron i amunicje do mono_inventory.
-- Uprawnienie (mono_admin.giveitem) i biala liste modeli sprawdza serwer.
-- ---------------------------------------------------------------------

RegisterCommand(Config.GiveCommand, function(_, args)
    if not args[1] then
        return Notify(('Użycie: /%s [model_broni] [amunicja], np. /%s weapon_pistol'):format(
            Config.GiveCommand,
            Config.GiveCommand
        ))
    end

    Request('giveWeapon', { weapon = args[1], ammo = args[2] }, function(result)
        if not result or not result.ok then
            Notify(ERROR_TEXT[result and result.error] or 'Nie można dodać broni.')
            return
        end

        local data = result.data or {}
        if data.ammoItem then
            Notify(('Dodano %s do EQ. Amunicja: %d/%d.'):format(
                data.weapon or args[1],
                tonumber(data.ammoAdded) or 0,
                tonumber(data.ammoRequested) or 0
            ))
        else
            Notify(('Dodano %s do EQ. Ta broń nie ma skonfigurowanej amunicji.'):format(data.weapon or args[1]))
        end
    end)
end, false)

-- ---------------------------------------------------------------------
-- /dv - usuwa pojazd stojacy przy postaci, /spawnv [model] - tworzy pojazd.
-- Uprawnienie (mono_admin.vehicle) sprawdza serwer. Samo szukanie pojazdu
-- dzieje sie tutaj (tylko klient zna pozycje i wymiary pojazdow wokol gracza),
-- a serwer usuwa pojazd (client/actions.lua tworzy pojazd po /spawnv).
-- ---------------------------------------------------------------------

-- Pojazdy dalsze (srodek pojazdu - postac) niz DeleteRange + ten zapas pomijamy
-- bez liczenia wymiarow. Musi byc wiekszy niz polowa najdluzszego pojazdu.
local VEHICLE_SEARCH_MARGIN = 15.0

-- Odleglosc punktu od POWIERZCHNI karoserii (0 = punkt jest wewnatrz bryly pojazdu).
-- Mierzymy do prostopadloscianu wymiarow modelu, a nie do srodka pojazdu - inaczej
-- postac stojaca przy zderzaku (ok. 2.5 m od srodka) nie "lapalaby" pojazdu.
local function DistanceToVehicleSurface(vehicle, point)
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, point.x, point.y, point.z)

    local dx = math.max(minDim.x - offset.x, 0.0, offset.x - maxDim.x)
    local dy = math.max(minDim.y - offset.y, 0.0, offset.y - maxDim.y)
    local dz = math.max(minDim.z - offset.z, 0.0, offset.z - maxDim.z)

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Pojazd, w ktorym siedzi postac, albo najblizszy w zasiegu `range` metrow od powierzchni.
-- Pomijamy pojazdy nieobecne w sieci (serwer nie moglby ich usunac).
local function FindVehicleInRange(ped, range)
    local current = GetVehiclePedIsIn(ped, false)

    if current ~= 0 then
        return current
    end

    local pedCoords = GetEntityCoords(ped)
    local nearest, nearestDistance

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle)
            and NetworkGetEntityIsNetworked(vehicle)
            and #(pedCoords - GetEntityCoords(vehicle)) <= range + VEHICLE_SEARCH_MARGIN
        then
            local distance = DistanceToVehicleSurface(vehicle, pedCoords)

            if distance <= range and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = vehicle, distance
            end
        end
    end

    return nearest
end

RegisterCommand(Config.DeleteVehicleCommand, function()
    local vehicle = FindVehicleInRange(PlayerPedId(), Config.Vehicles.DeleteRange)

    if not vehicle then
        return Notify(('Brak pojazdu w zasięgu (%.1f m). Podejdź bliżej.'):format(Config.Vehicles.DeleteRange))
    end

    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(model)

    Request(
        'deleteVehicle',
        { netId = NetworkGetNetworkIdFromEntity(vehicle), model = model },
        function(result)
            if not result or not result.ok then
                return Notify(ERROR_TEXT[result and result.error] or 'Nie można usunąć pojazdu.')
            end

            Notify(('Usunięto pojazd: ~b~%s~s~.'):format(label ~= 'NULL' and label or model))
        end
    )
end, false)

RegisterCommand(Config.SpawnVehicleCommand, function(_, args)
    if not args[1] then
        return Notify(('Użycie: /%s [model], np. /%s adder'):format(
            Config.SpawnVehicleCommand,
            Config.SpawnVehicleCommand
        ))
    end

    -- Sukces potwierdza zdarzenie mono_admin:spawnVehicle, bledy pokazujemy tutaj.
    Request('spawnVehicle', { model = args[1] }, function(result)
        if not result or not result.ok then
            Notify(ERROR_TEXT[result and result.error] or 'Nie można stworzyć pojazdu.')
        end
    end)
end, false)

RegisterNUICallback('request', function(data, cb)
    if not isOpen or type(data) ~= 'table' or type(data.name) ~= 'string' then
        return cb({ ok = false, error = 'invalid_request' })
    end

    Request(data.name, data.payload, cb)
end)

-- UI pyta o aktualny waypoint (pokazuje x/y i blokuje przycisk, gdy go brak).
RegisterNUICallback('getWaypoint', function(_, cb)
    if not isOpen or not IsWaypointActive() then
        return cb({ active = false })
    end

    local blip = GetFirstBlipInfoId(8)

    if not DoesBlipExist(blip) then
        return cb({ active = false })
    end

    local coords = GetBlipInfoIdCoord(blip)

    cb({ active = true, x = coords.x, y = coords.y })
end)

RegisterNUICallback('close', function(_, cb)
    SetOpen(false)

    cb({ success = true })
end)

RegisterNetEvent('mono_admin:warned', function(data)
    if type(data) ~= 'table' then
        return
    end

    TriggerEvent('chat:addMessage', {
        color = { 240, 165, 58 },
        multiline = true,
        args = {
            'OSTRZEŻENIE',
            ('Otrzymałeś ostrzeżenie od administracji: %s (aktywne: %s)'):format(
                tostring(data.reason),
                tostring(data.count)
            )
        }
    })

    Notify(('~o~Ostrzeżenie:~s~ %s'):format(tostring(data.reason)))
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if isOpen then
        SetNuiFocus(false, false)
    end
end)
