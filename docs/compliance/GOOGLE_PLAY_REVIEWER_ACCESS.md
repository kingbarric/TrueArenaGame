# Dedicated Google Play reviewer access

Status: deployed 16 October 2026 as a focused patch to the running production artifact.
API checks passed: code request, valid reusable login, wrong-code rejection, ordinary
non-guest account, and backend health. In-app installation and full feature checks
are pending Google Play first-use Terms acceptance in the emulator.

The deployed reviewer credentials remain private on the operator machine and server.
They have not been submitted to Google Play yet. Current configured expiry: 14 January
2027. Google's sign-in form asks for reusable credentials that do not expire, so resolve
that lifecycle requirement before submitting; do not claim non-expiring access.

Store contact: kingbarric@yahoo.com. Intended audience: adults aged 18+.
Guest access is restricted, so do not declare that every feature is available without login.

The existing email-code screen can sign in a dedicated, ordinary account using a reusable
six-digit reviewer code. This code only works for the configured reviewer email. It does
not grant administrative permissions or bypass paid features, moderation or game rules.

## Backend configuration

- `REVIEWER_EMAIL`: a new dedicated review identifier under a domain controlled by PlayHuud;
  never an existing user's address or the public support address.
- `REVIEWER_CODE_SHA256`: SHA-256 of the six-digit code, encoded as hexadecimal.
- `REVIEWER_EXPIRES_AT`: a future UTC instant in ISO-8601 form.

Generate the code securely at deployment. Store the clear code only in a private credential
store and Play Console's restricted reviewer instructions; never commit it or put it in
release notes. Set an expiry long enough to cover review, and renew for later reviews.
The email is reserved while configured, even after expiry. Removing the configuration
returns it to normal email verification, so never use a third-party mailbox as this identity.

Every reviewer-code verification counts against a shared limit of ten attempts per
15 minutes. Missing/invalid configuration, expiry and limiter failures cannot authenticate.
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
and Google approves the release. The adult target-audience form currently requires Ads
and Sign in details first. Adult targeting is not itself an in-app age check or IARC rating.
