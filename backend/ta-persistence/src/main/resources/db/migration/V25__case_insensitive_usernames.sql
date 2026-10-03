-- Keep the oldest spelling when pre-existing handles differ only by case.
-- Later duplicates receive a stable, short handle derived from their UUID.
WITH ranked AS (
    SELECT id, row_number() OVER (PARTITION BY lower(username) ORDER BY created_at, id) AS position
    FROM users
)
UPDATE users u
SET username = 'user_' || substr(replace(u.id::text, '-', ''), 1, 19)
FROM ranked r
WHERE u.id = r.id AND r.position > 1;

CREATE UNIQUE INDEX users_username_case_insensitive_key ON users (lower(username));
