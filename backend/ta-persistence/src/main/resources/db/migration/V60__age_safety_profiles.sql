-- No date of birth, government ID, or public age field is stored.
CREATE TABLE age_safety_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    age_band TEXT NOT NULL CHECK (age_band IN ('UNDER_13','AGE_13_15','AGE_16_17','ADULT')),
    country_code CHAR(2) NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
    source TEXT NOT NULL DEFAULT 'self_declared' CHECK (source = 'self_declared'),
    notice_version TEXT NOT NULL,
    declared_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE age_safety_profiles IS 'Private self-declarations; not identity verification or parental consent. No public joins.';
