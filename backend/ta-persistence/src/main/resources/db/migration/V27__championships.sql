CREATE TABLE championships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    game_type TEXT NOT NULL,
    size INTEGER NOT NULL CHECK (size IN (4, 8, 16, 32)),
    visibility TEXT NOT NULL CHECK (visibility IN ('public', 'private')),
    scheduled_at TIMESTAMPTZ NOT NULL,
    creator_id UUID NOT NULL REFERENCES users(id),
    status TEXT NOT NULL DEFAULT 'lobby' CHECK (status IN ('lobby', 'running', 'completed')),
    current_round INTEGER NOT NULL DEFAULT 0,
    champion_id UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);
CREATE INDEX championships_discovery_idx ON championships (status, scheduled_at) WHERE visibility = 'public';

CREATE TABLE championship_participants (
    championship_id UUID NOT NULL REFERENCES championships(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    slot INTEGER NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (championship_id, user_id),
    UNIQUE (championship_id, slot)
);

CREATE TABLE championship_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    championship_id UUID NOT NULL REFERENCES championships(id) ON DELETE CASCADE,
    round INTEGER NOT NULL,
    position INTEGER NOT NULL,
    player_a UUID REFERENCES users(id),
    player_b UUID REFERENCES users(id),
    winner_id UUID REFERENCES users(id),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'completed', 'bye', 'no_winner')),
    room_id UUID UNIQUE REFERENCES rooms(id),
    game_number INTEGER NOT NULL DEFAULT 1,
    a_remaining_ms BIGINT NOT NULL DEFAULT 180000,
    b_remaining_ms BIGINT NOT NULL DEFAULT 180000,
    a_absent_since TIMESTAMPTZ,
    b_absent_since TIMESTAMPTZ,
    clock_phase TEXT,
    clock_remaining_ms BIGINT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    UNIQUE (championship_id, round, position),
    CHECK (winner_id IS NULL OR winner_id = player_a OR winner_id = player_b)
);
CREATE INDEX championship_matches_round_idx ON championship_matches(championship_id, round);

CREATE TABLE championship_games (
    game_session_id UUID PRIMARY KEY REFERENCES game_sessions(id),
    match_id UUID NOT NULL REFERENCES championship_matches(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES rooms(id),
    game_number INTEGER NOT NULL,
    outcome TEXT NOT NULL CHECK (outcome IN ('win', 'draw', 'forfeit')),
    winner_id UUID REFERENCES users(id),
    completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (match_id, game_number)
);

-- A match room can be rebuilt after a server restart by replaying validated inputs.
CREATE TABLE championship_actions (
    sequence BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    game_session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    action_id TEXT NOT NULL,
    actor_id UUID,
    action_type TEXT NOT NULL,
    payload TEXT NOT NULL,
    UNIQUE(game_session_id, action_id)
);
CREATE INDEX championship_actions_session_idx ON championship_actions(game_session_id, sequence);

CREATE TABLE championship_badges (
    championship_id UUID NOT NULL REFERENCES championships(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    awarded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (championship_id, user_id)
);
