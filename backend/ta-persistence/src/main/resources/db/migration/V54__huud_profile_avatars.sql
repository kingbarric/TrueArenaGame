CREATE TABLE user_huud_avatars (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    avatar_id VARCHAR(32) NOT NULL CHECK (avatar_id IN ('ella','beverly','girl02','male','indian-male')),
    outfit_id VARCHAR(32) NOT NULL CHECK (outfit_id IN ('everyday','weekend','city','relaxed','sport','sunshine','evening','street','warm','fresh')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
