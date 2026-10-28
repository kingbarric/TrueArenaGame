# Dedicated Google Play reviewer access

Status: non-expiring reviewer access deployed 17 October 2026 as a focused backend update.
API checks passed: code request, valid reusable login, wrong-code rejection, ordinary
non-guest account, and backend health. Fresh email-code login through Android build 1.0.1 (6) passed on 18 October 2026. Profile, friends and deletion-requirements API access passed too. The original code and permanent lifetime were preserved. The reviewer account was not deleted.

The deployed reviewer credentials remain private on the operator machine and server.
They were added to Google Play Console Sign in details with explicit user approval on 18 October 2026; the declaration is saved pending app review. The dedicated store-review account now uses explicit non-expiring access
(`TRUEARENA_AUTH_REVIEWER_EXPIRES_AT=never`) in production. Its existing identifier
and code hash were preserved. Other accounts still use ordinary one-time verification.

Store contact: kingbarric@yahoo.com. Google Play audience: ages 13–15, 16–17 and 18+, selected by the user on 18 October 2026.
Guest access is restricted, so do not declare that every feature is available without login.

The existing email-code screen can sign in a dedicated, ordinary account using a reusable
six-digit reviewer code. This code only works for the configured reviewer email. It does
not grant administrative permissions or bypass paid features, moderation or game rules.

## Backend configuration

- `REVIEWER_EMAIL`: a new dedicated review identifier under a domain controlled by PlayHuud;
  never an existing user's address or the public support address.
- `REVIEWER_CODE_SHA256`: SHA-256 of the six-digit code, encoded as hexadecimal.
- `REVIEWER_EXPIRES_AT`: `never` for permanent store-review access, or a future UTC instant in ISO-8601 form for temporary access. Blank or malformed values disable verification.

The current private `reviewer.env` uses the equivalent Spring environment names
`TRUEARENA_AUTH_REVIEWER_EMAIL`, `TRUEARENA_AUTH_REVIEWER_CODE_SHA256` and
`TRUEARENA_AUTH_REVIEWER_EXPIRES_AT`; these take precedence over application YAML defaults.

Generate the code securely at deployment. Store the clear code only in a private credential
store and Play Console's restricted reviewer instructions; never commit it or put it in
release notes. Use the explicit `never` setting for store reviewers so future reviews are not blocked by an expiry.
The email is reserved while configured, even after expiry. Removing the configuration
returns it to normal email verification, so never use a third-party mailbox as this identity.

Every reviewer-code verification counts against a shared limit of ten attempts per
15 minutes. Missing/invalid configuration, expired temporary access and limiter failures cannot authenticate.
The permanent setting changes only the dedicated account's access lifetime; the code hash,
account scope, ordinary-user verification and shared attempt limit remain enforced.
Ordinary users continue using the existing OTP flow. Test-profile allowlists still apply.

## Before submitting to Google

1. Deploy the backend and set the three values above. No Android rebuild is needed.
2. From a clean app session, choose email sign-in, enter the dedicated identifier,
   request a code, and enter the reusable reviewer code.
3. Verify this creates a normal account with no administrator privileges. Finish profile
   setup, then verify hosting a Huud/game and friends features. Add a second ordinary test
   account if a feature needs another participant.
4. Enter the verified email and code in Play Console's app-access instructions. Explain
   that this review account uses the supplied code and requires no mailbox access or 2FA.
5. Never select unrestricted access: general users still require an account for hosting
   and friends features.

Closed testing remains blocked until all required store assets and declarations are complete
and Google approves the release. The target-audience form requires Ads and Sign in details first; both prerequisites and the user-selected 13+ audience are now saved. Audience targeting is not itself an in-app age check or an IARC rating.

## Permanent access verification — 17 October 2026

Twelve targeted OTP/reviewer tests passed, covering the explicit permanent setting,
Spring environment-variable names used by the private reviewer file, wrong codes,
account scope, expired/blank/malformed settings, attempt exhaustion and Redis failure.
The backend was built from an isolated checkout based on the running production
revision, so unfinished app and game changes were excluded. The existing runtime
and private configuration were backed up; only the backend image and reviewer
expiry were changed. Production health returned UP. Live invalid-code checks returned
401 for the reviewer and an ordinary identifier. No codes were requested or messages
sent. No mobile rebuild is needed. The reusable code remains private; it was not
regenerated or published. A successful real-code login was not repeated in this run.

## Independent Apple reviewer access — 28 October 2026

The optional `truearena.auth.apple-reviewer-email`, `apple-reviewer-code-sha256`
and `apple-reviewer-expires-at` settings provide a second, independently scoped
reviewer account. Production supplies the corresponding
`TRUEARENA_AUTH_APPLE_REVIEWER_*` variables through its private reviewer.env.
Missing settings disable this account; an explicit `never` retains review access.
The existing Google Play reviewer configuration and account remain unchanged.

Both accounts use the same constant-time hash verification and per-identifier
Redis attempt limit. A code cannot authenticate the other reviewer or an
ordinary account, and neither slot bypasses the test environment allowlist.
The plaintext Apple code stays in private operator credentials and Apple's
restricted review instructions, never source or the user database.
