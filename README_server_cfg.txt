# server.cfg - kolejnosc ma znaczenie
ensure oxmysql
ensure mono_core
ensure mono_admin

# Wymagane do teleportow/spectate (GetPlayerPed po stronie serwera):
set onesync on

# --- uprawnienia (ACE) ---
add_ace group.admin mono_admin.open      allow
add_ace group.admin mono_admin.warn      allow
add_ace group.admin mono_admin.kick      allow
add_ace group.admin mono_admin.ban       allow
add_ace group.admin mono_admin.unban     allow
add_ace group.admin mono_admin.teleport  allow
add_ace group.admin mono_admin.heal      allow
add_ace group.admin mono_admin.freeze    allow
add_ace group.admin mono_admin.spectate  allow
add_ace group.admin mono_admin.noclip    allow
add_ace group.admin mono_admin.godmode   allow
add_ace group.admin mono_admin.invisible allow
add_ace group.admin mono_admin.giveitem  allow   # /giveweapon oraz przycisk "Dodaj wszystkie bronie"
add_ace group.admin mono_admin.immune    allow   # chroni przed kick/ban/warn/freeze/bring od innych adminow

# przypisz siebie (twoj license: wpisz w konsoli serwera `status` albo zajrzyj do panelu -> Identyfikatory)
add_principal identifier.license:TWOJ_LICENSE group.admin
