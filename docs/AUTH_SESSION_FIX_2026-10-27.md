# Guest recovery and returning-account sign-in

Based on `origin/main` at `806a9ea`, in isolated branch `codex/fix-auth-session`.

## Findings

- Guest upgrades retained `users.device_id`. `/auth/guest` recovered that row without checking `is_guest`, allowing guest entry to restore a registered account and its name.
- Welcome and Save Session forced Apple/Google logins into onboarding whenever the caller was a guest, even when the returned account already existed. Username setup prefilled the returned account's username. This confirms a code path matching the reported Apple behavior, not a forensic verification of a particular phone session.
- Email/phone verification from a guest tried to upgrade the guest before looking up the verified contact's existing account, resulting in a conflict for returning users.
- Sign-out could silently return while voice remained active or abort on notification cleanup failure. A pending token refresh could also restore the old identity afterward.

## Changes

Guest recovery accepts guest rows only and detaches legacy device links from registered accounts before making a new guest. New upgrades release the device link. Sign-out clears profile/avatar/session data and rotates guest device identity even if voice/push cleanup fails. Stale refresh and initial profile responses are ignored after session changes.

All sign-in screens use the server's `newAccount` flag. First-time guest upgrades set it to true; existing Apple/Google/email/phone accounts set it to false and retain their usernames. Existing-account login switches accounts; it does not merge the guest's history into the existing account.

## Validation

- 9 new backend session tests plus the existing Apple verification test passed.
- 10 Flutter session, deletion, and resume tests passed.
- Targeted analyzer: no errors or warnings; two existing const-constructor hints in Welcome.
- No device installation or backend deployment performed for this fix.
