-- =====================================================================
-- mono_admin | client/actions.lua
-- Efekty po stronie klienta: noclip, god mode, niewidzialnosc, teleporty,
-- heal, freeze, spectate. Zdarzenia wysyla WYLACZNIE serwer (po sprawdzeniu ACE).
-- =====================================================================

local features = {
    noclip = false,
    godmode = false,
    invisible = false,
    frozen = false
}

local spectate = {
    active = false,
    origin = nil,
    heading = 0.0
}

local teleporting = false

-- 4 poziomy predkosci noclipa (m/s). Zmiana: scroll myszy albo klawisze 1-4.
local NOCLIP_LEVELS = {
    { label = 'Wolne',          speed = 1.5 },
    { label = 'Szybkie',        speed = 8.0 },
    { label = 'Bardzo szybkie', speed = 30.0 },
    { label = 'TeslaMODE',      speed = 120.0 }
}

local NOCLIP_LEVEL_KEYS = { 157, 158, 160, 164 } -- klawisze 1, 2, 3, 4
local noclipLevel = 2 -- domyslnie "Szybkie"

-- Przezroczystosc postaci widoczna tylko dla nas (0-255).
local GHOST_ALPHA = 110

local function SendNoclipHud(visible)
    local labels = {}

    for index, level in ipairs(NOCLIP_LEVELS) do
        labels[index] = level.label
    end

    SendNUIMessage({
        action = 'noclipHud',
        visible = visible,
        level = noclipLevel,
        levels = labels
    })
end

local function SetNoclipLevel(level)
    level = math.max(1, math.min(#NOCLIP_LEVELS, level))

    if level == noclipLevel then
        return
    end

    noclipLevel = level

    SendNoclipHud(true)
end

local function Notify(text)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, true)
end

-- Pojazd, jesli gracz jest kierowca; w przeciwnym razie ped.
local function GetControlledEntity()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        return vehicle
    end

    return ped
end

local function FadeOut(ms)
    DoScreenFadeOut(ms)

    local deadline = GetGameTimer() + 2000

    while not IsScreenFadedOut() and GetGameTimer() < deadline do
        Wait(10)
    end
end

local function FadeIn(ms)
    DoScreenFadeIn(ms)
end

local function ShouldStayFrozen()
    return features.frozen or features.noclip
end

-- ---------------------------------------------------------------------
-- "Duch": niewidoczny dla innych graczy, ale polprzezroczysty u nas.
-- Aktywny gdy wlaczony jest noclip LUB niewidzialnosc.
-- SetEntityVisible(false) jest replikowane do innych graczy (OneSync),
-- a SetEntityLocallyVisible co klatke przywraca widocznosc tylko u nas.
-- ---------------------------------------------------------------------

local function IsGhost()
    return features.invisible or features.noclip
end

local ghostRunning = false

local function SetGhostState(entity, enabled)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return
    end

    if enabled then
        SetEntityVisible(entity, false, false)
        SetEntityLocallyVisible(entity)
        SetEntityAlpha(entity, GHOST_ALPHA, false)
    else
        ResetEntityAlpha(entity)
        SetEntityVisible(entity, true, false)
    end
end

local function StartGhost()
    if ghostRunning then
        return
    end

    ghostRunning = true

    CreateThread(function()
        local lastVehicle = 0

        while IsGhost() do
            if not spectate.active then
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)

                if lastVehicle ~= 0 and lastVehicle ~= vehicle then
                    SetGhostState(lastVehicle, false)
                end

                SetGhostState(ped, true)
                SetGhostState(vehicle, true)

                lastVehicle = vehicle
            end

            Wait(0)
        end

        ghostRunning = false

        if not spectate.active then
            local ped = PlayerPedId()

            SetGhostState(ped, false)
            SetGhostState(lastVehicle, false)
            SetGhostState(GetVehiclePedIsIn(ped, false), false)
        end
    end)
end

-- ---------------------------------------------------------------------
-- Teleport
-- ---------------------------------------------------------------------

local function WaitForCollision(entity, x, y, z)
    local deadline = GetGameTimer() + 5000

    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        Wait(50)
    end
end

local function TeleportTo(x, y, z)
    if teleporting then
        return
    end

    teleporting = true

    local entity = GetControlledEntity()

    FadeOut(250)

    FreezeEntityPosition(entity, true)
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)

    WaitForCollision(entity, x, y, z)

    if not ShouldStayFrozen() then
        FreezeEntityPosition(entity, false)
    end

    FadeIn(300)

    teleporting = false
end

-- Granice mapy GTA V (razem z Cayo Perico). Waypoint poza nimi jest odrzucany.
local MAP_BOUNDS = {
    minX = -4500.0,
    maxX = 6000.0,
    minY = -6000.0,
    maxY = 9000.0
}

local GROUND_SEARCH = {
    top = 1000.0,           -- zaczynamy szukac z tej wysokosci
    bottom = -100.0,        -- i schodzimy do tej
    step = 25.0,
    timeoutMs = 12000,      -- twardy limit calego wyszukiwania
    minValidGround = -60.0, -- podloze nizej = pod mapa -> odrzucamy
    spawnOffset = 1.0       -- ile nad podlozem / woda stawiamy postac
}

local WAYPOINT_ERROR = {
    no_ground = 'Nie znaleziono podłoża pod waypointem (teren nie załadował się). Teleport anulowany.',
    under_map = 'Pod waypointem nie ma bezpiecznego podłoża. Teleport anulowany.',
    error = 'Błąd podczas teleportu. Wróciłeś na poprzednie miejsce.'
}

local function IsInsideMap(x, y)
    return x >= MAP_BOUNDS.minX and x <= MAP_BOUNDS.maxX
        and y >= MAP_BOUNDS.minY and y <= MAP_BOUNDS.maxY
end

-- Stawia encje w punkcie i czeka na kolizje. true = kolizja zaladowana (bezpiecznie puscic).
local function PlaceAndLoad(entity, x, y, z)
    SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)
    WaitForCollision(entity, x, y, z)

    return HasCollisionLoadedAroundEntity(entity)
end

-- Szuka podloza pod (x, y): schodzi z duzej wysokosci, przy kazdym kroku czeka na kolizje.
-- GetGroundZFor_3dCoord zwraca najwyzsza powierzchnie ponizej z (dach budynku, nie jego wnetrze).
local function FindGroundZ(entity, x, y)
    local deadline = GetGameTimer() + GROUND_SEARCH.timeoutMs

    for z = GROUND_SEARCH.top, GROUND_SEARCH.bottom, -GROUND_SEARCH.step do
        if GetGameTimer() > deadline then
            break
        end

        SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)
        RequestCollisionAtCoord(x, y, z)

        local collisionDeadline = GetGameTimer() + 400

        while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < collisionDeadline do
            RequestCollisionAtCoord(x, y, z)
            Wait(10)
        end

        Wait(20)

        local found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)

        if found then
            return groundZ
        end
    end

    return nil
end

-- Zwraca bezpieczne Z (i 'water' gdy stawiamy na powierzchni wody) albo nil + powod.
local function ResolveSafeZ(entity, x, y)
    local groundZ = FindGroundZ(entity, x, y)
    local hasWater, waterZ = GetWaterHeight(x, y, groundZ or 0.0)

    if hasWater and (not groundZ or waterZ > groundZ) then
        return waterZ + GROUND_SEARCH.spawnOffset, 'water'
    end

    if not groundZ then
        return nil, 'no_ground'
    end

    if groundZ < GROUND_SEARCH.minValidGround then
        return nil, 'under_map'
    end

    return groundZ + GROUND_SEARCH.spawnOffset
end

-- Waypoint LOKALNEGO gracza -> vector3 albo nil + kod bledu ('no_waypoint' | 'out_of_map').
local function GetWaypointCoords()
    if not IsWaypointActive() then
        return nil, 'no_waypoint'
    end

    local blip = GetFirstBlipInfoId(8)

    if not DoesBlipExist(blip) then
        return nil, 'no_waypoint'
    end

    local coords = GetBlipInfoIdCoord(blip)

    if not IsInsideMap(coords.x, coords.y) then
        return nil, 'out_of_map'
    end

    return coords
end

-- Komunikaty, gdy teleport wywolal sam gracz/admin na sobie (panel -> "Ja").
local WAYPOINT_PRECHECK_TEXT = {
    no_waypoint = 'Ustaw waypoint na mapie.',
    out_of_map = 'Waypoint jest poza mapą.'
}

-- Komunikaty dla gracza, ktorego teleportuje administrator.
local WAYPOINT_PRECHECK_TEXT_BY_ADMIN = {
    no_waypoint = 'Administrator chciał przenieść Cię na waypoint, ale żaden nie jest ustawiony. Zaznacz punkt na mapie.',
    out_of_map = 'Administrator chciał przenieść Cię na waypoint, ale leży on poza mapą.'
}

-- token == nil    -> teleport na wlasny waypoint (admin na sobie, jak dotychczas),
-- token == liczba -> teleport zlecony przez admina z panelu (gracz -> jego waypoint).
--                    Wynik wstepnej walidacji wraca do serwera, a stamtad do admina.
local function TeleportToWaypoint(token)
    local byAdmin = type(token) == 'number'

    local function ack(status)
        if byAdmin then
            TriggerServerEvent('mono_admin:waypointAck', token, status)
        end
    end

    if teleporting then
        return ack('busy')
    end

    local target, precheckError = GetWaypointCoords()

    if not target then
        ack(precheckError)

        return Notify(
            (byAdmin and WAYPOINT_PRECHECK_TEXT_BY_ADMIN or WAYPOINT_PRECHECK_TEXT)[precheckError]
        )
    end

    -- Odpowiadamy ZANIM zaczniemy szukac podloza (to moze trwac kilkanascie sekund).
    ack('started')

    if byAdmin then
        Notify('Administrator przenosi Cię na Twój waypoint.')
    end

    teleporting = true

    local entity = GetControlledEntity()
    local origin = GetEntityCoords(entity)

    FadeOut(250)
    FreezeEntityPosition(entity, true)

    -- pcall: niezaleznie od bledu ekran sie odslania, a flaga teleporting zostaje zwolniona.
    local ok, z, reason = pcall(ResolveSafeZ, entity, target.x, target.y)

    if not ok then
        print(('[MONO_ADMIN] Blad teleportu na waypoint: %s'):format(tostring(z)))

        z, reason = nil, 'error'
    end

    local placed = false

    if z then
        placed = PlaceAndLoad(entity, target.x, target.y, z)

        if not placed then
            reason = 'no_ground'
        end
    end

    if placed then
        if reason == 'water' then
            Notify('Waypoint jest na wodzie - ustawiono na jej powierzchni.')
        elseif IsEntityAVehicle(entity) then
            SetVehicleOnGroundProperly(entity)
        end
    else
        -- Nic nie jest bezpieczne - wracamy tam, skad wystartowalismy.
        PlaceAndLoad(entity, origin.x, origin.y, origin.z)

        Notify(WAYPOINT_ERROR[reason] or WAYPOINT_ERROR.error)
    end

    SetEntityVelocity(entity, 0.0, 0.0, 0.0)

    if not ShouldStayFrozen() then
        FreezeEntityPosition(entity, false)
    end

    FadeIn(300)

    teleporting = false
end

RegisterNetEvent('mono_admin:teleport', function(x, y, z)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then
        return
    end

    TeleportTo(x + 0.0, y + 0.0, z + 0.0)
end)

-- Serwer wysyla ten event w dwoch przypadkach:
--   bez argumentow  -> admin teleportuje SIEBIE na swoj waypoint,
--   z tokenem       -> admin teleportuje TEGO gracza na JEGO waypoint (patrz TeleportToWaypoint).
RegisterNetEvent('mono_admin:teleportWaypoint', TeleportToWaypoint)

-- ---------------------------------------------------------------------
-- Heal / revive
-- ---------------------------------------------------------------------

RegisterNetEvent('mono_admin:heal', function()
    local ped = PlayerPedId()

    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
        local coords = GetEntityCoords(ped)

        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)

        ped = PlayerPedId()

        ClearPedTasksImmediately(ped)
    end

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)

    Notify('Zostałeś uleczony przez administrację.')
end)

RegisterNetEvent('mono_admin:slay', function()
    local ped = PlayerPedId()

    if not ped or ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then
        return
    end

    SetEntityHealth(ped, 0)
end)

-- ---------------------------------------------------------------------
-- Freeze
-- ---------------------------------------------------------------------

RegisterNetEvent('mono_admin:freeze', function(enabled)
    features.frozen = enabled == true

    if not features.frozen then
        Notify('Zostałeś odmrożony.')

        return
    end

    Notify('Zostałeś zamrożony przez administrację.')

    CreateThread(function()
        while features.frozen do
            FreezeEntityPosition(PlayerPedId(), true)
            FreezeEntityPosition(GetControlledEntity(), true)

            Wait(250)
        end

        if not features.noclip then
            FreezeEntityPosition(PlayerPedId(), false)
            FreezeEntityPosition(GetControlledEntity(), false)
        end
    end)
end)

-- ---------------------------------------------------------------------
-- God mode / niewidzialnosc
-- ---------------------------------------------------------------------

local function StartGodmode()
    CreateThread(function()
        while features.godmode do
            SetPlayerInvincible(PlayerId(), true)

            Wait(250)
        end

        SetPlayerInvincible(PlayerId(), false)
    end)
end

local function StartInvisible()
    StartGhost()
end

-- ---------------------------------------------------------------------
-- Noclip
-- WASD - ruch, Spacja / Ctrl - gora / dol, scroll lub 1-4 - predkosc.
-- ---------------------------------------------------------------------

local function StartNoclip()
    CreateThread(function()
        local entity = GetControlledEntity()

        SetEntityCollision(entity, false, false)
        FreezeEntityPosition(entity, true)
        SetEntityInvincible(entity, true)

        SendNoclipHud(true)

        while features.noclip do
            DisableAllControlActions(0)

            -- Rozglądanie, czat, push-to-talk zostaja aktywne.
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 245, true)
            EnableControlAction(0, 249, true)

            local rot = GetGameplayCamRot(2)
            local pitch = math.rad(rot.x)
            local yaw = math.rad(rot.z)

            local forwardX = -math.sin(yaw) * math.cos(pitch)
            local forwardY = math.cos(yaw) * math.cos(pitch)
            local forwardZ = math.sin(pitch)

            local rightX = math.cos(yaw)
            local rightY = math.sin(yaw)

            if IsDisabledControlJustPressed(0, 241) then -- scroll w gore
                SetNoclipLevel(noclipLevel + 1)
            elseif IsDisabledControlJustPressed(0, 242) then -- scroll w dol
                SetNoclipLevel(noclipLevel - 1)
            end

            for level, control in ipairs(NOCLIP_LEVEL_KEYS) do
                if IsDisabledControlJustPressed(0, control) then
                    SetNoclipLevel(level)
                end
            end

            local speed = NOCLIP_LEVELS[noclipLevel].speed

            local dx, dy, dz = 0.0, 0.0, 0.0

            if IsDisabledControlPressed(0, 32) then -- W
                dx, dy, dz = dx + forwardX, dy + forwardY, dz + forwardZ
            end

            if IsDisabledControlPressed(0, 33) then -- S
                dx, dy, dz = dx - forwardX, dy - forwardY, dz - forwardZ
            end

            if IsDisabledControlPressed(0, 35) then -- D
                dx, dy = dx + rightX, dy + rightY
            end

            if IsDisabledControlPressed(0, 34) then -- A
                dx, dy = dx - rightX, dy - rightY
            end

            if IsDisabledControlPressed(0, 22) then -- Spacja
                dz = dz + 1.0
            end

            if IsDisabledControlPressed(0, 36) then -- Ctrl
                dz = dz - 1.0
            end

            local step = speed * GetFrameTime()
            local position = GetEntityCoords(entity)

            SetEntityCoordsNoOffset(
                entity,
                position.x + dx * step,
                position.y + dy * step,
                position.z + dz * step,
                true, true, true
            )

            SetEntityHeading(entity, rot.z)

            Wait(0)
        end

        SendNoclipHud(false)

        SetEntityCollision(entity, true, true)
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
        FreezeEntityPosition(entity, features.frozen)

        if not features.godmode then
            SetEntityInvincible(entity, false)
        end
    end)
end

RegisterNetEvent('mono_admin:feature', function(feature, enabled)
    if features[feature] == nil or feature == 'frozen' then
        return
    end

    enabled = enabled == true

    if features[feature] == enabled then
        return
    end

    features[feature] = enabled

    if not enabled then
        return
    end

    if feature == 'noclip' then
        StartNoclip()
        StartGhost()
    elseif feature == 'godmode' then
        StartGodmode()
    elseif feature == 'invisible' then
        StartInvisible()
    end
end)

-- ---------------------------------------------------------------------
-- Spectate
-- ---------------------------------------------------------------------

local function EndSpectate()
    if not spectate.active then
        return
    end

    spectate.active = false

    local ped = PlayerPedId()

    FadeOut(250)

    NetworkSetInSpectatorMode(false, ped)
    ClearFocus()

    if spectate.origin then
        SetEntityCoordsNoOffset(ped, spectate.origin.x, spectate.origin.y, spectate.origin.z, false, false, false)
        SetEntityHeading(ped, spectate.heading)
    end

    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, ShouldStayFrozen())
    SetEntityInvincible(ped, features.godmode)

    if not IsGhost() then
        ResetEntityAlpha(ped)
        SetEntityVisible(ped, true, false)
    end

    FadeIn(300)
end

RegisterNetEvent('mono_admin:spectate', function(targetServerId, x, y, z)
    if spectate.active or type(targetServerId) ~= 'number' then
        return
    end

    local ped = PlayerPedId()

    spectate.active = true
    spectate.origin = GetEntityCoords(ped)
    spectate.heading = GetEntityHeading(ped)

    FadeOut(300)

    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)

    -- Ped docelowy musi byc "streamowany" - podchodzimy pod niego (pod ziemia, niewidzialni).
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, (z + 0.0) - 15.0, false, false, false)

    local targetPed = 0
    local deadline = GetGameTimer() + 8000

    while GetGameTimer() < deadline do
        local player = GetPlayerFromServerId(targetServerId)

        if player ~= -1 then
            local candidate = GetPlayerPed(player)

            if candidate ~= 0 and candidate ~= ped and DoesEntityExist(candidate) then
                targetPed = candidate

                break
            end
        end

        Wait(100)
    end

    if targetPed == 0 then
        EndSpectate()

        return Notify('Nie udało się załadować obserwowanego gracza.')
    end

    NetworkSetInSpectatorMode(true, targetPed)
    FadeIn(300)

    while spectate.active do
        local player = GetPlayerFromServerId(targetServerId)

        if player == -1 or not DoesEntityExist(GetPlayerPed(player)) then
            Notify('Obserwowany gracz opuścił serwer.')

            break
        end

        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName('Podgląd gracza — ~INPUT_CELLPHONE_CANCEL~ aby zakończyć')
        EndTextCommandDisplayHelp(0, false, false, -1)

        if IsControlJustPressed(0, 177) then
            break
        end

        Wait(0)
    end

    EndSpectate()
end)

-- ---------------------------------------------------------------------
-- Bronie (kolko wyboru broni GTA - do czasu wlasnego ekwipunku)
-- Zdarzenia wysyla WYLACZNIE serwer, po sprawdzeniu ACE i bialej listy modeli.
-- ---------------------------------------------------------------------

-- true = bron dodana, false = modelu nie ma w tej wersji gry.
local function GrantWeapon(ped, name, ammo)
    local hash = GetHashKey(name)

    if not IsWeaponValid(hash) then
        return false
    end

    GiveWeaponToPed(ped, hash, ammo, false, false)

    return true
end

RegisterNetEvent('mono_admin:giveWeapon', function(name, ammo)
    if type(name) ~= 'string' or type(ammo) ~= 'number' then
        return
    end

    ammo = math.floor(ammo)

    if GrantWeapon(PlayerPedId(), name, ammo) then
        Notify(('Dodano broń: ~b~%s~s~ (amunicja: %d).'):format(name, ammo))
    else
        Notify(('Broń ~r~%s~s~ nie jest dostępna w tej wersji gry.'):format(name))
    end
end)

RegisterNetEvent('mono_admin:giveAllWeapons', function(ammo)
    if type(ammo) ~= 'number' then
        return
    end

    ammo = math.floor(ammo)

    local ped = PlayerPedId()
    local added = 0

    for _, name in ipairs(Config.Weapons.List) do
        if GrantWeapon(ped, name, ammo) then
            added = added + 1
        end
    end

    Notify(('Dodano ~g~%d~s~ broni do kółka wyboru.'):format(added))
end)

-- ---------------------------------------------------------------------
-- Pojazdy (/spawnv). Zdarzenie wysyla WYLACZNIE serwer, po sprawdzeniu ACE.
-- ---------------------------------------------------------------------

local spawningVehicle = false

local function LoadVehicleModel(hash)
    if HasModelLoaded(hash) then
        return true
    end

    RequestModel(hash)

    local deadline = GetGameTimer() + 5000

    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(0)
    end

    return HasModelLoaded(hash)
end

RegisterNetEvent('mono_admin:spawnVehicle', function(name)
    if type(name) ~= 'string' or spawningVehicle then
        return
    end

    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        return Notify('Najpierw wysiądź z pojazdu (albo użyj /dv).')
    end

    local hash = GetHashKey(name)

    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return Notify(('Nieznany pojazd: ~r~%s~s~.'):format(name))
    end

    spawningVehicle = true

    if not LoadVehicleModel(hash) then
        spawningVehicle = false

        return Notify('Nie udało się załadować modelu pojazdu.')
    end

    local coords = GetEntityCoords(ped)
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)

    SetModelAsNoLongerNeeded(hash)

    spawningVehicle = false

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return Notify('Nie udało się stworzyć pojazdu.')
    end

    -- Mission entity: pojazd nie zniknie sam, gdy odejdziesz (czyszczenie ruchu ulicznego).
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetPedIntoVehicle(ped, vehicle, -1)

    Notify(('Stworzono pojazd: ~b~%s~s~.'):format(name))
end)

-- ---------------------------------------------------------------------
-- Sprzatanie / odtwarzanie stanu
-- ---------------------------------------------------------------------

-- Po restarcie zasobu state bag przezywa, a watki klienta nie - odtwarzamy.
CreateThread(function()
    Wait(1000)

    local state = LocalPlayer.state

    if state.mono_admin_godmode then
        features.godmode = true
        StartGodmode()
    end

    if state.mono_admin_invisible then
        features.invisible = true
        StartInvisible()
    end

    if state.mono_admin_frozen then
        TriggerEvent('mono_admin:freeze', true)
    end

    -- Noclip celowo NIE jest odtwarzany po restarcie - wyczysc stan.
    if state.mono_admin_noclip then
        TriggerServerEvent('mono_admin:request', 0, 'toggleFeature', { feature = 'noclip' })
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    features.noclip = false
    features.godmode = false
    features.invisible = false
    features.frozen = false

    local ped = PlayerPedId()

    if spectate.active then
        spectate.active = false
        NetworkSetInSpectatorMode(false, ped)
        ClearFocus()
    end

    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)
    ResetEntityAlpha(ped)
    SetEntityVisible(ped, true, false)
    SendNoclipHud(false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
end)
