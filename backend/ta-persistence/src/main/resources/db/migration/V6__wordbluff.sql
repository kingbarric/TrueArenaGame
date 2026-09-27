-- Word Bluff — second game type. Canonical schema reference: docs/DATABASE.md.

ALTER TABLE rooms ADD COLUMN game_type TEXT NOT NULL DEFAULT 'truearena';
ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check CHECK (game_type IN ('truearena', 'wordbluff'));

-- Word Bluff has no roles table entries, but game_results.winning_side and roles.role_type
-- were constrained to TrueArena's vocabulary. Widen winning_side for team-based games
-- ('A' / 'B'); roles stays TrueArena-only since Word Bluff never writes to it.
ALTER TABLE game_results DROP CONSTRAINT game_results_winning_side_check;
ALTER TABLE game_results ADD CONSTRAINT game_results_winning_side_check
    CHECK (winning_side IN ('faithful', 'traitors', 'A', 'B'));
