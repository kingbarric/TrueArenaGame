package app.truearena.engine;

import java.util.Collections;
import java.util.List;
import java.util.Random;

/** Deterministic randomness. The seed is stored on the session so a game is replayable. */
public interface RandomSource {

    long seed();

    int nextInt(int bound);

    <T> void shuffle(List<T> list);

    static RandomSource seeded(long seed) {
        return new Seeded(seed);
    }

    final class Seeded implements RandomSource {
        private final long seed;
        private final Random random;

        Seeded(long seed) {
            this.seed = seed;
            this.random = new Random(seed);
        }

        @Override
        public long seed() {
            return seed;
        }

        @Override
        public int nextInt(int bound) {
            return random.nextInt(bound);
        }

        @Override
        public <T> void shuffle(List<T> list) {
            Collections.shuffle(list, random);
        }
    }
}
