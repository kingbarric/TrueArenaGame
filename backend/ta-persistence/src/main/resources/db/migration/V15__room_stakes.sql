-- Match-stake escrow — coins only, never real money in or out (no purchase,
-- no cash-out anywhere in this app), which is why this stays outside any
-- gambling-law surface. A room optionally carries a fixed per-player stake;
-- every member escrows that amount on joining (see RoomService.create/join),
-- and the pot pays out to the winner(s) on finish (GameOrchestrator.
-- payoutStake) or refunds everyone if the room is abandoned before the game
-- starts (RoomService.abandon).

ALTER TABLE rooms ADD COLUMN stake_coins BIGINT NOT NULL DEFAULT 0 CHECK (stake_coins >= 0);
