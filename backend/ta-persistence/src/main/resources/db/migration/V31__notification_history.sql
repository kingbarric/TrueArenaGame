-- Per-user record of every push-worthy notification sent, so the app can
-- show a "Notifications" page — distinct from device_tokens (where to send)
-- and broadcast_notifications (the admin's one row per broadcast, not
-- per-recipient). Written by PushNotificationService alongside every
-- actual send attempt, regardless of whether the device push itself
-- succeeds — this is "you were notified of X", not "a device received X".
CREATE TABLE user_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ
);

CREATE INDEX user_notifications_user_id_created_at_idx
    ON user_notifications (user_id, created_at DESC);
