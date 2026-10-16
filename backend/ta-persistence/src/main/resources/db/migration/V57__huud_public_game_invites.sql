-- Public discovery is scoped to one game and host, without changing Huud privacy.
ALTER TABLE huud_spaces
  ADD COLUMN public_invite_room_id uuid REFERENCES rooms(id) ON DELETE SET NULL,
  ADD COLUMN public_invite_host_id uuid REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN public_invite_seats integer,
  ADD COLUMN public_invite_at timestamptz;
