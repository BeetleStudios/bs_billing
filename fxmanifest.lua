fx_version 'cerulean'
game 'gta5'

author 'Beetle Studios'
description 'Simple cross-framework billing system'
version '2.0.2'

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/banking.lua',
    'server/bills.lua',
    'server/main.lua'
}

client_scripts {
    'client/nui.lua',
    'client/main.lua'
}

ui_page 'ui/dist/index.html'

files {
    'locales/*.json',
    'ui/dist/index.html',
    'ui/dist/**/*',
}

dependencies {
    'ox_lib',
    'oxmysql'
}

escrow_ignore {
    'config.lua',
    'locales/*.json',
    'server/*.lua',
    'client/*.lua'
}

lua54 'yes'
