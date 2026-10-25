-- One invitation per recipient per Huud every five minutes, across all senders.
CREATE TABLE huud_member_nudges (
    huud_space_id UUID NOT NULL REFERENCES huud_spaces(id) ON DELETE CASCADE,
    target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sent_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (huud_space_id, target_user_id),
    CHECK (target_user_id <> sent_by)
);
