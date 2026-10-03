/// Google Sign-In needs real OAuth client IDs before it will work at all —
/// there is no way to fake this locally the way the phone/email OTP
/// dev-bypass works. See docs/DEV_REFERENCE.md §2a for the exact Google Cloud
/// Console steps (OAuth consent screen, Web/iOS/Android client IDs, iOS URL
/// scheme, Android SHA-1).
///
/// The Web application OAuth client ID is the ID token audience for both the
/// app and backend. Override with GOOGLE_WEB_CLIENT_ID for another environment.
const String kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '26187322342-o2squi475tmt3ubs8k9rh2d2b7pfivgf.apps.googleusercontent.com',
);

/// The **iOS** OAuth client ID — passed as `clientId` (iOS/macOS only; Android
/// ignores this and relies on the registered SHA-1 instead). Without this,
/// sign-in fails on iOS even with the URL scheme in Info.plist set correctly.
const String kGoogleIosClientId = '26187322342-l8ts2r7ve596qvc9ditdv0l1g09gk8tg.apps.googleusercontent.com';

bool get isGoogleSignInConfigured => kGoogleWebClientId.endsWith('.apps.googleusercontent.com');
