fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Monoskrypt'
description 'Admin panel for Monoskrypt RP'
version '0.1.0'

dependencies {
    'oxmysql',
    'mono_core',
    'mono_inventory'
}

shared_script 'shared/config.lua'

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

client_scripts {
    'client/main.lua',
    'client/actions.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/utils.lua',
    'server/logs.lua',
    'server/bans.lua',
    'server/warns.lua',
    'server/handlers.lua',
    'server/main.lua'
}
