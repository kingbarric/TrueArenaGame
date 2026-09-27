/// Google Sign-In needs real OAuth client IDs before it will work at all —
/// there is no way to fake this locally the way the phone/email OTP
/// dev-bypass works. See docs/DEV_REFERENCE.md §2a for the exact Google Cloud
/// Console steps (OAuth consent screen, Web/iOS/Android client IDs, iOS URL
/// scheme, Android SHA-1).
///
/// Supply GOOGLE_WEB_CLIENT_ID with --dart-define when building the app.
/// This one MUST be the **Web application** client ID, not the iOS or Android
/// one — it's passed as `serverClientId`, which is what makes the ID token's
/// `aud` match what the backend's `truearena.auth.google-client-id` checks.
const String kGoogleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// The **iOS** OAuth client ID — passed as `clientId` (iOS/macOS only; Android
/// ignores this and relies on the registered SHA-1 instead). Without this,
/// sign-in fails on iOS even with the URL scheme in Info.plist set correctly.
const String kGoogleIosClientId = '26187322342-l8ts2r7ve596qvc9ditdv0l1g09gk8tg.apps.googleusercontent.com';

bool get isGoogleSignInConfigured => kGoogleWebClientId.endsWith('.apps.googleusercontent.com');
