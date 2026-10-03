ALTER TABLE rooms DROP CONSTRAINT rooms_game_type_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check
    CHECK (game_type IN ('truearena', 'wordbluff', 'draughts', 'goosi', 'whot', 'ludo'));
