# PlayHuud French cryptology declaration - draft

**Status:** French distribution deferred by the supplier on 2 October 2026. App Store Connect's build questionnaire now records standard encryption and **No** for distribution in France. Build 1.0.1 (2026100201) is **Testing** in the PlayHuud Internal TestFlight group. The French form remains unsigned and unfiled. Do not upload this draft as an ANSSI attestation or make the app available on the French App Store before completing the applicable French declaration.

## Why this is needed

PlayHuud iOS 1.0.1 (build 2026100201) was uploaded to App Store Connect on 2 October 2026. It initially showed **Missing Compliance** because the account holder planned French distribution. The supplier later chose to defer France; the export-compliance answers were updated, and the build entered internal TestFlight testing. The app still incorporates standard cryptography outside Apple's operating system. The French declaration package is retained for a future French release.

Apple's [export compliance reference](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/) says standard algorithms outside the Apple OS require a French declaration when the app is distributed in France. ANSSI publishes the [official form and filing instructions](https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/controle-reglementaire-cryptographie-formulaires/).

## Known app details for the ANSSI form

| Form area | Draft value |
| --- | --- |
| Product name / brand | PlayHuud |
| Product type | iOS mobile application (software) |
| Bundle ID | `app.truearena.truearena` |
| Version | 1.0.1, build 2026100201 |
| Purpose | Social multiplayer games (Draughts, Whot, Word Bluff), direct and group messaging, and voice calls. |
| Functional category | Communication software with security of user data; confirm ANSSI's form classification before filing. |
| Cryptographic functions | Confidentiality, integrity, and authentication for network transport; confidentiality and integrity for supported direct messages and one-to-one voice calls. |
| Protocols | HTTPS/TLS for API traffic; WebRTC DTLS-SRTP for voice transport; LiveKit media frame encryption for one-to-one calls where keys are available. |
| Algorithms | X25519 key agreement; AES-256-GCM for direct messages; AES-GCM for LiveKit one-to-one media frame encryption. WebRTC's standard DTLS-SRTP stack supplies additional transport cryptography. |
| Proprietary algorithms | No proprietary cryptographic algorithm was identified in the app code. The `e2e1:` message prefix is an envelope marker, not an algorithm. |

### Implementation details to disclose

- The app generates a static X25519 key pair on a device. The private key is stored through `flutter_secure_storage` (iOS Keychain); the public key is published to the PlayHuud server.
- For direct messages, two devices derive an X25519 shared secret and use it as the AES-256-GCM key. A message stores a random 12-byte nonce, ciphertext, and 16-byte authentication tag. The server stores ciphertext when both peers have keys.
- One-to-one LiveKit voice calls use the pair's shared secret as the SDK's media frame encryption key. LiveKit's Flutter SDK sets `EncryptionType.kGcm` for this option. Group calls use WebRTC DTLS-SRTP transport encryption; they do not use the app's end-to-end media encryption.
- If a peer public key is unavailable, direct messages and one-to-one calls can fall back to transport encryption without the app's end-to-end layer. Group chat is not end-to-end encrypted. There is no cross-device private key sync or out-of-band public-key verification.

The source of these statements is [`app/lib/core/e2e_crypto.dart`](../../app/lib/core/e2e_crypto.dart), [`app/lib/features/calls/call_screen.dart`](../../app/lib/features/calls/call_screen.dart), and the locked package versions in [`app/pubspec.lock`](../../app/pubspec.lock). The app uses `cryptography` 2.9.0, `livekit_client` 2.13.0, `flutter_webrtc` 1.6.2+hotfix.3, and WebRTC-SDK 150.7871.01.

## Information still needed from the legal supplier

The ANSSI XFA form asks for information that cannot be inferred safely from the app or Apple account:

- The account holder selected **natural person** as the supplier and supplied Nigerian nationality, a UK postal address including postcode, and a telephone number. The legal name and contact email came from the Apple developer account. The supplier reviewed and accepted these details on 2 October 2026. The personal details and a prefilled official XFA form are kept outside the Git repository.
- The supplier confirmed that their existing details may be reused for technical contact. The first public release date is undecided. The declaration-only filing choice and functional category in the working copy still require legal review before signing; Category 3 remains unchecked.
- Signature of the person authorized to attest to the filing. A company registration extract should not be assumed necessary for an individual; confirm the required supporting documents with ANSSI's instructions.

### Draft mapping to the official XFA form

| ANSSI section | Draft entry / action |
| --- | --- |
| A2 - Personne physique | Supplier selected as an individual. Legal name, nationality, postal address, postcode, telephone number and email confirmed by the supplier. Personal details are kept outside this repository. |
| B1 - Informations generales | Brand `PlayHuud`; product `PlayHuud iOS application`; version `1.0.1`; individual supplier entered as manufacturer in the working copy; first-market date remains undecided. |
| B2 - Description fonctionnelle | Software mobile games, messaging, voice communications, security of user data. Mark software; confirm the form's exact category choice. |
| B3 - Description cryptologie | Confidentiality, integrity, and authentication. Describe X25519, AES-256-GCM, LiveKit AES-GCM, TLS and DTLS-SRTP; record exact SDK cipher-suite detail if ANSSI asks. |
| C - Categorie 3 | Do not check without confirmation that the product meets the French classification criteria. |
| E - Pieces a joindre | This technical annex, product overview, user guide if available, and any additional evidence ANSSI requires. |
| F - Attestation | Supplier's legal name, capacity, date, and signature must be completed by the supplier. |

The technical annex at `output/pdf/PlayHuud_French_Encryption_Technical_Annex_DRAFT.pdf` can accompany the official form after review. A private working copy of ANSSI's official XFA PDF was prefilled with the confirmed identity and technical details. The embedded XFA data was verified after writing, and the filled pages were visually checked in Adobe Acrobat Reader. The private working form, field draft, unsent email draft, and a copy of the technical annex are stored in `/Users/ericbarima/Documents/PlayHuud ANSSI/` with restricted file permissions. The working copy selects declaration only and the information-transmission category as proposed choices; these should be reviewed before signing. The first marketing date remains blank because it is undecided, and the supplier's date and signature are outstanding. The form's attachments checklist has not yet been checked. ANSSI asks for the completed electronic form, a signed scan, and supporting documentation. ANSSI's published electronic filing address is `controle@ssi.gouv.fr`, with the required subject format described on its [form page](https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/controle-reglementaire-cryptographie-formulaires/). No filing has been sent.

Before adding France to App Store availability, complete the French filing and obtain the applicable ANSSI declaration documentation. Upload that official document under **PlayHuud > Distribution > App Information > App Encryption Documentation**, and revisit the export-compliance answers. Apple says its review of complete documentation is case by case. The current build is already assigned to the **PlayHuud Internal** TestFlight group; no French filing has been sent.
