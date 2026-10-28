Config = {}

-- Komenda i domyslny klawisz (gracz moze zmienic w ustawieniach FiveM).
Config.Command = 'monoadmin'
Config.DefaultKey = 'F10'

-- /admin = tryb szybkich skrotow (bez panelu). Klawisze mozna zmienic tez w ustawieniach FiveM.
Config.QuickCommand = 'admin'
Config.QuickKeys = {
    noclip = 'V',
    godmode = 'C'
}

-- true = panel otworzy sie tylko gdy gracz ma aktywna postac (jest w grze).
Config.RequireCharacter = true

-- Testy solo: pozwala uzywac kick/warn/ban/freeze na SOBIE. Na produkcji false.
Config.AllowSelfTarget = false

Config.RequestTimeoutMs = 10000
Config.NetCooldownMs = 250

Config.Reason = {
    Min = 3,
    Max = 200
}

Config.Bans = {
    -- Jakie identyfikatory zapisujemy w banie.
    Identifiers = { 'license', 'license2', 'discord', 'steam', 'fivem', 'live', 'xbl' },

    -- Tokeny sprzetowe (HWID-like) - utrudniaja obejscie bana nowym kontem.
    UseTokens = true,

    -- IP domyslnie wylaczone: wspoldzielone IP = banowanie niewinnych.
    UseIp = false,

    -- Maksymalny czas bana w sekundach (10 lat). 0 = permanentny jest zawsze dozwolony.
    MaxDuration = 10 * 365 * 24 * 3600
}

Config.Webhook = {
    Enabled = false,
    Url = '',
    Username = 'Mono Admin'
}

-- /giveweapon [model_broni] [amunicja] - dodaje bron i luzna amunicje do mono_inventory.
-- Wymaga ACE mono_admin.giveitem.
Config.GiveCommand = 'giveweapon'

Config.Weapons = {
    -- Amunicja przy /giveweapon bez 2. argumentu oraz przy "Dodaj wszystkie bronie".
    DefaultAmmo = 250,

    -- Gorny limit amunicji podawanej w /giveweapon.
    MaxAmmo = 9999,

    -- Mapowanie broni na typ amunicji mono_inventory.
    -- Bronie bez wpisu (np. noz, palka) nie dostaja przedmiotu amunicji.
    InventoryAmmoItems = {
        weapon_pistol = 'ammo_9mm',
        weapon_combatpistol = 'ammo_9mm',
        weapon_pumpshotgun = 'ammo_shotgun',
        weapon_carbinerifle = 'ammo_rifle'
    },

    -- Biala lista modeli: tylko te nazwy przyjmie /giveweapon, ta sama lista idzie do
    -- "Dodaj wszystkie bronie". Model, ktorego nie ma w danej wersji gry, klient pomija
    -- (IsWeaponValid), wiec lista moze byc "na zapas". Dodawaj/usuwaj wpisy wedle uznania.
    List = {
        -- bron biala
        'weapon_dagger', 'weapon_bat', 'weapon_bottle', 'weapon_crowbar', 'weapon_flashlight',
        'weapon_golfclub', 'weapon_hammer', 'weapon_hatchet', 'weapon_knuckle', 'weapon_knife',
        'weapon_machete', 'weapon_switchblade', 'weapon_nightstick', 'weapon_wrench',
        'weapon_battleaxe', 'weapon_poolcue', 'weapon_stone_hatchet', 'weapon_candycane',

        -- pistolety
        'weapon_pistol', 'weapon_pistol_mk2', 'weapon_combatpistol', 'weapon_appistol',
        'weapon_stungun', 'weapon_stungun_mp', 'weapon_pistol50', 'weapon_snspistol',
        'weapon_snspistol_mk2', 'weapon_heavypistol', 'weapon_vintagepistol', 'weapon_flaregun',
        'weapon_marksmanpistol', 'weapon_revolver', 'weapon_revolver_mk2', 'weapon_doubleaction',
        'weapon_raypistol', 'weapon_ceramicpistol', 'weapon_navyrevolver', 'weapon_gadgetpistol',
        'weapon_tecpistol', 'weapon_pistolxm3',

        -- pistolety maszynowe
        'weapon_microsmg', 'weapon_smg', 'weapon_smg_mk2', 'weapon_assaultsmg', 'weapon_combatpdw',
        'weapon_machinepistol', 'weapon_minismg', 'weapon_raycarbine',

        -- strzelby
        'weapon_pumpshotgun', 'weapon_pumpshotgun_mk2', 'weapon_sawnoffshotgun',
        'weapon_assaultshotgun', 'weapon_bullpupshotgun', 'weapon_musket', 'weapon_heavyshotgun',
        'weapon_dbshotgun', 'weapon_autoshotgun', 'weapon_combatshotgun',

        -- karabiny
        'weapon_assaultrifle', 'weapon_assaultrifle_mk2', 'weapon_carbinerifle',
        'weapon_carbinerifle_mk2', 'weapon_advancedrifle', 'weapon_specialcarbine',
        'weapon_specialcarbine_mk2', 'weapon_bullpuprifle', 'weapon_bullpuprifle_mk2',
        'weapon_compactrifle', 'weapon_militaryrifle', 'weapon_heavyrifle', 'weapon_tacticalrifle',

        -- karabiny maszynowe
        'weapon_mg', 'weapon_combatmg', 'weapon_combatmg_mk2', 'weapon_gusenberg',

        -- snajperki
        'weapon_sniperrifle', 'weapon_heavysniper', 'weapon_heavysniper_mk2',
        'weapon_marksmanrifle', 'weapon_marksmanrifle_mk2', 'weapon_precisionrifle',

        -- bron ciezka
        'weapon_rpg', 'weapon_grenadelauncher', 'weapon_grenadelauncher_smoke', 'weapon_minigun',
        'weapon_firework', 'weapon_railgun', 'weapon_railgunxm3', 'weapon_hominglauncher',
        'weapon_compactlauncher', 'weapon_rayminigun', 'weapon_emplauncher', 'weapon_snowlauncher',

        -- miotane
        'weapon_grenade', 'weapon_bzgas', 'weapon_molotov', 'weapon_stickybomb', 'weapon_proxmine',
        'weapon_pipebomb', 'weapon_smokegrenade', 'weapon_flare', 'weapon_snowball', 'weapon_ball',
        'weapon_acidpackage',

        -- pozostale
        'weapon_petrolcan', 'weapon_hazardcan', 'weapon_fertilizercan', 'weapon_fireextinguisher',
        'weapon_digiscanner', 'weapon_metaldetector', 'gadget_parachute'
    }
}

-- /dv - usuwa pojazd stojacy przy postaci (albo ten, w ktorym siedzisz).
-- /spawnv [model] - tworzy pojazd i sadza w nim admina.
-- Oba wymagaja ACE mono_admin.vehicle.
Config.DeleteVehicleCommand = 'dv'
Config.SpawnVehicleCommand = 'spawnv'

Config.Vehicles = {
    -- /dv: maksymalna odleglosc w metrach od POWIERZCHNI karoserii (nie od srodka pojazdu)
    -- do postaci. 2.0 = pojazd, przy ktorym stoisz, ale nie ten ulice dalej.
    DeleteRange = 2.0,

    -- /dv: serwer odrzuci usuniecie pojazdu dalej niz tyle metrow (srodek pojazdu - admin).
    -- To tylko zabezpieczenie przed podstawionym netId, wiec zapas jest duzy.
    ServerMaxDistance = 25.0
}
