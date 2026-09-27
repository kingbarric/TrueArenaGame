-- Per-room game options, chosen by the host when the room is made.
--
-- Draughts is the first game to need one: whether captures are mandatory is
-- a house rule some players want off, and it has to be settled before the
-- first move rather than argued about mid-game. Kept as JSON rather than a
-- column per option because each game type has its own settings and they'll
-- keep arriving — the alternative is a widening table most rows don't use.
--
-- Null means "whatever the game's defaults are", which is what every room
-- created before this column existed gets.

ALTER TABLE rooms ADD COLUMN game_config TEXT;
