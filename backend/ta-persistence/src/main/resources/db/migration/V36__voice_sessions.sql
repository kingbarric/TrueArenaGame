-- Voice is a platform social session; a game may refer to it but never owns it.
CREATE TABLE voice_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('direct', 'group')),
    owner_id UUID NOT NULL REFERENCES users(id),
    created_by UUID NOT NULL REFERENCES users(id),
    privacy TEXT NOT NULL DEFAULT 'invite_only' CHECK (privacy IN ('public', 'friends', 'invite_only', 'private')),
    invite_permissions TEXT NOT NULL DEFAULT 'participants' CHECK (invite_permissions IN ('host', 'participants')),
    social_group_id UUID REFERENCES groups(id) ON DELETE SET NULL,
    active_game_session_id UUID REFERENCES game_sessions(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX voice_active_room ON voice_sessions(room_name) WHERE status = 'active';
CREATE TABLE voice_session_participants (
    voice_session_id UUID NOT NULL REFERENCES voice_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    muted BOOLEAN NOT NULL DEFAULT false,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at TIMESTAMPTZ,
    PRIMARY KEY(voice_session_id, user_id)
);
CREATE UNIQUE INDEX voice_one_active_session_per_user ON voice_session_participants(user_id) WHERE left_at IS NULL;
CREATE TABLE voice_session_invites (
    voice_session_id UUID NOT NULL REFERENCES voice_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('requested', 'invited', 'approved', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(voice_session_id, user_id)
);
ALTER TABLE rooms ADD COLUMN voice_session_id UUID REFERENCES voice_sessions(id) ON DELETE SET NULL;
CREATE INDEX rooms_host_pending ON rooms(host_id, game_type, created_at DESC) WHERE status = 'lobby';

ALTER TABLE game_sessions ADD COLUMN voice_session_id UUID REFERENCES voice_sessions(id) ON DELETE SET NULL;
