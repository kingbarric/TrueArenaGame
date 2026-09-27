-- Whot — the fifth game type. Canonical schema reference: docs/DATABASE.md.
--
-- Goosi stays in the list: it's shelved in the app rather than removed, and
-- existing goosi rooms still have to satisfy this constraint.

ALTER TABLE rooms DROP CONSTRAINT rooms_game_type_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check
    CHECK (game_type IN ('truearena', 'wordbluff', 'draughts', 'goosi', 'whot'));
