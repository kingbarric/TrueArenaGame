-- V37 is reserved for the concurrently developed SlayHuud game.
CREATE TABLE huud_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(6) NOT NULL UNIQUE,
    owner_id UUID NOT NULL REFERENCES users(id),
    name VARCHAR(80) NOT NULL,
    description VARCHAR(280) NOT NULL DEFAULT '',
    privacy TEXT NOT NULL DEFAULT 'public' CHECK (privacy IN ('public','friends','private')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','ended')),
    activity TEXT NOT NULL DEFAULT 'idle' CHECK (activity IN ('idle','waiting','playing','results')),
    game_type TEXT,
    game_config JSONB NOT NULL DEFAULT '{}',
    activity_version INTEGER NOT NULL DEFAULT 0,
    current_room_id UUID REFERENCES rooms(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    owner_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX huud_one_owned_active ON huud_sessions(owner_id) WHERE status='active';
CREATE INDEX huud_discovery ON huud_sessions(privacy,created_at DESC) WHERE status='active';
ALTER TABLE rooms ADD COLUMN huud_session_id UUID REFERENCES huud_sessions(id);
CREATE INDEX rooms_huud_session ON rooms(huud_session_id);
CREATE TABLE huud_members (
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    user_id UUID NOT NULL REFERENCES users(id),
    status TEXT NOT NULL CHECK (status IN ('participant','left','banned')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(huud_id,user_id)
);
CREATE TABLE huud_admission (
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    user_id UUID NOT NULL REFERENCES users(id),
    status TEXT NOT NULL CHECK (status IN ('invited','requested','accepted','rejected')),
    can_view BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(huud_id,user_id)
);
CREATE TABLE huud_viewers (
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    user_id UUID NOT NULL REFERENCES users(id),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(huud_id,user_id)
);
CREATE TABLE huud_game_requests (
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    activity_version INTEGER NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    status TEXT NOT NULL CHECK (status IN ('requested','selected','not_selected','closed')),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(huud_id,activity_version,user_id)
);
CREATE TABLE huud_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    user_id UUID NOT NULL REFERENCES users(id),
    text VARCHAR(1000) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX huud_chat_history ON huud_messages(huud_id,created_at DESC);
CREATE TABLE IF NOT EXISTS user_blocks (
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(blocker_id,blocked_id),
    CHECK(blocker_id <> blocked_id)
);
CREATE TABLE huud_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    reporter_id UUID NOT NULL REFERENCES users(id),
    reported_user_id UUID NOT NULL REFERENCES users(id),
    room_id UUID REFERENCES rooms(id),
    message_id UUID REFERENCES huud_messages(id),
    reason VARCHAR(1000) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Durable moderation context and product analytics; never contains private game state.
CREATE TABLE huud_events (
    id BIGSERIAL PRIMARY KEY,
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    actor_id UUID REFERENCES users(id),
    target_id UUID REFERENCES users(id),
    room_id UUID REFERENCES rooms(id),
    activity_version INTEGER NOT NULL,
    kind TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX huud_event_history ON huud_events(huud_id,created_at DESC);
CREATE INDEX huud_event_rate_limits ON huud_events(actor_id,kind,created_at DESC);
-- Audience at match completion, sampled again after 30 seconds for post-game retention.
CREATE TABLE huud_game_audience (
    room_id UUID NOT NULL REFERENCES rooms(id),
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    user_id UUID NOT NULL REFERENCES users(id),
    population TEXT NOT NULL CHECK(population IN ('participant','viewer')),
    finished_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    retained BOOLEAN,
    sampled_at TIMESTAMPTZ,
    PRIMARY KEY(room_id,user_id)
);
CREATE INDEX huud_retention_pending ON huud_game_audience(finished_at) WHERE sampled_at IS NULL;
-- Persist LiveKit removals when its control API is temporarily unavailable.
CREATE TABLE huud_voice_revocations (
    huud_id UUID NOT NULL REFERENCES huud_sessions(id),
    user_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(huud_id,user_id)
);
CREATE TABLE huud_removed_game_players (
    room_id UUID NOT NULL REFERENCES rooms(id),
    user_id UUID NOT NULL REFERENCES users(id),
    removed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(room_id,user_id)
);
