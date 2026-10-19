# Apple resubmission: free matches and earned coins

The release keeps the App Store minimum age at 18+. It includes the private age-declaration foundation; teen access remains disabled. The broader teen privacy/communication rollout remains gated as documented in safety/TEEN_ROLLOUT_CHECKLIST.md.

All match entry is free. Old clients sending a nonzero stake receive HTTP 400; a database constraint prevents positive room stakes. No escrow, winner-takes-pot payout or entry refund runs in game services. Existing balances and historical ledger entries are preserved, as requested.

New accounts receive 100 free coins. Normal completed human matches earn 50 coins for a win, 15 for a tie and 10 for completion/loss. Losing never deducts coins. Wins lasting at least 60 seconds may earn 10, 20 or 30 extra coins using server-recorded duration; resignations, forfeits, disconnections and timeouts do not receive a speed bonus. Practice against Cyber Agents keeps its existing no-reward policy.

The speed benchmark is 300 seconds for chess/draughts, 120 for Whot, 180 for Ludo/Macala, and 600 for other games. Bonus = 10 × max(0, 3 − floor(duration / benchmark)); wins shorter than 60 seconds receive the base reward only. The maximum normal match reward is 80 coins.

Reward receipts, balance updates and ledger entries commit in one database statement under a user lock. Repeated/concurrent completion or result-screen requests return the same receipt. Each player can fetch only their own reward. Victory screens read persisted receipts, including after reconnecting.

Gifts transfer three existing coins from sender to recipient atomically; gifts do not mint coins or increase earned lifetime tiers. Existing SlayHuud progress rewards and wardrobe purchases remain ordinary in-game progression. Coins cannot be purchased with money or redeemed for money/value.

Before resubmission: verify tests and production deployment, upload the new iOS build, replace the selected build, accurately mark simulated gambling absent after auditing all shipped features, retain 18+ override, and explain the removed mechanics to App Review. Do not assert that the full teen-safety programme is complete.
