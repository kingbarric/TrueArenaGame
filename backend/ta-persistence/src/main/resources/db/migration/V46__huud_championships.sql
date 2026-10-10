-- Championships run inside a Huud. The Huud stays the social room (members,
-- chat, voice, mic rules); the championship is a temporary activity in it.
--
--   championships.huud_space_id       the Huud it runs in; NULL = a standalone
--                                     championship from before Huuds.
--   championships.round_timing        'simultaneous' = every match in a round
--                                     plays at once; 'sequential' = one at a
--                                     time. The final is always on its own.
--   championships.spectators_allowed  people in the Huud may watch the matches.
--   championships.grace_seconds       how long a disconnected player has to
--                                     come back before forfeiting.
--   huud_spaces.championship_id       the championship on in the Huud right
--                                     now (registration, running, or finished
--                                     and still showing its bracket). Cleared
--                                     when the Huud goes back to hanging out.

ALTER TABLE championships
    ADD COLUMN huud_space_id      UUID REFERENCES huud_spaces(id) ON DELETE SET NULL,
    ADD COLUMN round_timing       TEXT NOT NULL DEFAULT 'simultaneous'
        CHECK (round_timing IN ('simultaneous', 'sequential')),
    ADD COLUMN spectators_allowed BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN grace_seconds      INTEGER NOT NULL DEFAULT 180
        CHECK (grace_seconds BETWEEN 30 AND 900);

-- A host can call off a championship while players are still registering.
ALTER TABLE championships DROP CONSTRAINT championships_status_check;
ALTER TABLE championships ADD CONSTRAINT championships_status_check
    CHECK (status IN ('lobby', 'running', 'completed', 'cancelled'));

-- One championship at a time per Huud.
CREATE UNIQUE INDEX championships_one_open_per_huud ON championships (huud_space_id)
    WHERE huud_space_id IS NOT NULL AND status IN ('lobby', 'running');

ALTER TABLE huud_spaces ADD COLUMN championship_id UUID REFERENCES championships(id) ON DELETE SET NULL;
