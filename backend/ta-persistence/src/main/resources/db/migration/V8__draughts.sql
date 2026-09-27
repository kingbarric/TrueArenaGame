-- Draughts — the third game type. Canonical schema reference: docs/DATABASE.md.

ALTER TABLE rooms DROP CONSTRAINT rooms_game_type_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check
    CHECK (game_type IN ('truearena', 'wordbluff', 'draughts'));

-- game_results.winning_side already allows 'A'/'B' (added for Word Bluff in
-- V6) — Draughts reuses that same team-side vocabulary, no further change needed.
