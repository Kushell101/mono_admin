# Monoskrypt Admin 0.2.0
Zrób kopię zapasową obecnego zasobu, a następnie zastąp jego pliki zawartością tego ZIP-a. Zachowaj nazwę folderu `mono_admin`.
Jeśli jeszcze tego nie zrobiłeś, zaimportuj `sql/schema.sql` z paczki Core 0.1.0.
W `server.cfg` pozostaw `ensure oxmysql` przed `ensure mono_admin`. Potrzebne ACE: `mono_admin.open` i `mono_admin.players.view`.
Następnie wykonaj `restart mono_admin` w konsoli.
Dostępne: /admin, F10, NUI, Escape, pulpit i lista aktywnych sesji pobierana z serwera. Funkcje moderacji nie są jeszcze zaimplementowane.
