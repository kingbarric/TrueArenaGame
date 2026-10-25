# Player strength and competitive rating

Cards and `/rankings/all-time` use `StrengthService`; clients never submit a score.

- Competitive rating is the existing Glicko-2 rating, without a 100-point cap. Wins, losses, opponent ratings and rating uncertainty determine it. Standard Chess and Official Draughts in a Huud request rated play; bot/guest games and repeated-opponent farming remain ineligible. Casual and Seizure Draughts retain their rules.
- Strength is a PlayHuud presentation on 0–100, not an official Glicko scale. For rated records it maps the conservative rating `r - 2*RD` through `100 / (1 + exp((1500 - r + 2*RD)/400))`, multiplied by `1 - exp(-ratedGames/15)`. This keeps a small sample cautious. Results can decrease strength; this is not an activity counter.
- Games without a competitive rating show **Estimate**: the 95% Wilson lower bound for human win/draw results, with a draw worth half a win. This is an early performance estimate, not a claim to opponent-adjusted skill. Bot/guest matches do not contribute. Only the first five matches against the same set of opponents per UTC day count.
- Ten qualifying matches are required for a public rank. Geographic positions are scoped comparisons of the same score; adding a location never awards strength. Country uses its ISO code. State is preferred, otherwise an opted-in public city is used.
- Overall strength is an average of the played-game scores, weighted by qualifying samples capped at 30 per game. It describes a record across games; it is not a universal competitive rating.
- The board orders the unrounded score, then qualifying sample count. Display rounding does not erase distinctions. Cards and boards share that exact query. Historic activity totals without match evidence do not create skill.

The Glicko-2 rating/uncertainty model is documented by its author: https://www.glicko.net/glicko/glicko2.pdf. These display mappings are PlayHuud choices and should be calibrated against future predictive accuracy before being described as an external standard.
