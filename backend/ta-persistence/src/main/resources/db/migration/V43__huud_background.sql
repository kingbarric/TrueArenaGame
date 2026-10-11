-- The host's choice of backdrop for the Huud (shown faded behind it).
-- NULL is the default: no picture.
ALTER TABLE huud_spaces
    ADD COLUMN background TEXT CHECK (background IS NULL OR background IN ('lounge', 'poolside', 'club'));
