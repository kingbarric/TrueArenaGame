-- Add Monopoly without removing game types introduced by parallel game branches.
DO $$
DECLARE prior text;
BEGIN
    SELECT pg_get_constraintdef(oid) INTO prior FROM pg_constraint
      WHERE conrelid = 'rooms'::regclass AND conname = 'rooms_game_type_check';
    IF prior IS NOT NULL THEN
      ALTER TABLE rooms DROP CONSTRAINT rooms_game_type_check;
      EXECUTE 'ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check CHECK ((' ||
        substring(prior FROM 7) || ') OR game_type = ''monopoly'')';
    END IF;
END $$;
