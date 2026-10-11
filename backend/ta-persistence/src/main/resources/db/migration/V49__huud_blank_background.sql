-- Blank is an explicit backdrop choice; NULL remains the default Disco.
ALTER TABLE huud_spaces DROP CONSTRAINT huud_spaces_background_check;
ALTER TABLE huud_spaces ADD CONSTRAINT huud_spaces_background_check
    CHECK (background IS NULL OR background IN ('blank', 'lounge', 'poolside', 'club'));
