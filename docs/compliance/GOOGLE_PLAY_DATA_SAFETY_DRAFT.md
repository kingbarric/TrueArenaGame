# Google Play Data safety — saved declarations, 18 October 2026

Supersedes the 2 October draft. These answers are saved in Play Console pending review; saving is not publication or Google approval. Reassess when behavior or SDKs change.

## Collection

All listed types are declared collected, encrypted in transit, and not shared under Google’s definitions. Hosting, Firebase messaging and OS speech providers are service providers; user-directed communications use the applicable sharing exemption. This does not mean no outside processor handles data.

| Type | Optional? | Ephemeral? | Purposes |
| --- | --- | --- | --- |
| Name | Yes | No | App functionality, account management |
| Email address | Yes | No | App functionality, account management |
| User IDs | No | No | App functionality, account management, analytics, fraud prevention/security/compliance |
| Phone number | Yes | No | App functionality, account management |
| Approximate location | Yes | No | App functionality, personalization |
| Other in-app messages | Yes | No | App functionality |
| Photos | Yes | No | App functionality, account management |
| Voice or sound recordings | Yes | No | App functionality |
| Contacts | Yes | Yes | App functionality |
| Diagnostics | No | No | App functionality, analytics, fraud prevention/security/compliance |
| App interactions | No | No | App functionality, analytics |
| In-app search history | Yes | Yes | App functionality |
| Other user-generated content | Yes | No | App functionality |
| Device or other IDs | No | No | App functionality, account management |

Approximate location means user-selected country/region/city for rankings, not GPS. Contact matching sends numbers over TLS without retaining the submitted list; do not describe it as hashed matching. Search queries are not persisted. Diagnostics include our operational/authentication failure records, not a claim that Crashlytics or Sentry is integrated. App interactions include game actions/results. Firebase push and guest installation identities are covered by device/other IDs.

Group and pre-key-exchange chat can be stored in plaintext on the server. Keyed direct messages and 1:1 calls have end-to-end encryption; do not claim universal E2E. Group voice uses self-hosted LiveKit with transport encryption and no configured recording. Word Bluff uses the OS speech recognizer with onDevice defaulting false: it may process audio through the OS provider. The voice declaration conservatively does not claim all processing is ephemeral.

No precise location, advertising ID, financial information, health data, videos, music files, installed-app inventory, calendar, web browsing history or separate crash-log type was declared. Coins are earned-only with no real-money purchase or cash-out. Optional virtual-coin wagers are separately declared in the IARC questionnaire.

## Accounts and deletion

Creation methods declared: username/other authentication (one-time codes), OAuth and guest identity. No password signup is claimed.

- Privacy: https://playhuud.com/privacy/
- Outside-app deletion request: https://playhuud.com/delete-account/
- In-app deletion: Settings → Delete account, including the account-specific confirmation flow.
- Separate partial-data deletion without deleting the account: No; no general independent flow was verified.

The outside-app page offers a manual email request route with identity verification. It does not introduce an automated deletion API. The user is not asked to send passwords or sign-in codes. No independent security-review badge was claimed.

## Evidence and upkeep

Reviewed client account/profile/chat/contacts/speech/upload code, backend persistence/authentication/game/diagnostic handlers, Firebase configuration and the merged release manifest. The release manifest has no AD_ID permission. Current Console questions and official definitions govern these answers:

- https://support.google.com/googleplay/android-developer/answer/10787469
- https://firebase.google.com/docs/android/play-data-disclosure

Local screenshots and the signed build record are in output/google-play/ in the primary workspace. No credentials belong in this document.
