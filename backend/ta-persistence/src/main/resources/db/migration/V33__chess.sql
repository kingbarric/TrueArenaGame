-- Chess joins the room game types. Numbered V33 rather than V32 because V32
-- is taken by concurrent work on main; Flyway applies them in order.
ALTER TABLE rooms DROP CONSTRAINT rooms_game_type_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check
    CHECK (game_type IN ('truearena', 'wordbluff', 'draughts', 'goosi', 'whot', 'ludo', 'chess'));
