-- New Huuds start without a background photograph; Disco is now an explicit choice.
ALTER TABLE huud_spaces ALTER COLUMN background SET DEFAULT 'blank';
ALTER TABLE huud_spaces DROP CONSTRAINT huud_spaces_background_check;
ALTER TABLE huud_spaces ADD CONSTRAINT huud_spaces_background_check
    CHECK (background IS NULL OR background IN ('blank', 'disco', 'lounge', 'poolside', 'club'));
