CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
    token TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Unique on token, not (user_id, platform): the same physical token can
-- legitimately move to a different user_id (sign-out, different account,
-- same device) — upserting on token means the previous owner stops getting
-- pushes for a token they no longer hold, for free. A user can hold several
-- rows (old phone + new phone) until the old one goes stale and gets pruned
-- by PushNotificationService on a delivery failure.
CREATE UNIQUE INDEX device_tokens_token_uq ON device_tokens (token);
CREATE INDEX device_tokens_user_id_idx ON device_tokens (user_id);

CREATE TABLE broadcast_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    created_by_admin TEXT,
    scheduled_for TIMESTAMPTZ, -- NULL = send on the next scheduler tick (i.e. "now")
    sent_at TIMESTAMPTZ,
    -- 'sending' is claimed-but-not-yet-resolved — see BroadcastSchedulerService,
    -- which flips pending -> sending atomically before actually sending, so two
    -- overlapping ticks can't both pick up and double-send the same row.
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sending', 'sent', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX broadcast_notifications_due_idx ON broadcast_notifications (status, scheduled_for);
