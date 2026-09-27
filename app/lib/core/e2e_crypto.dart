import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// DM end-to-end encryption — X25519 static Diffie-Hellman between two
/// known public keys, then AES-256-GCM over the shared secret. The private
/// key never leaves the device (kept in secure storage, not
/// SharedPreferences) and the server only ever sees a public key and
/// ciphertext — see `MeController.setPublicKey`, `ChatService`.
///
/// Deliberately scoped to DMs only (see the design conversation this
/// shipped from): group chat needs a per-member key-wrapping scheme, and
/// group *calls* need real key distribution to every participant — both
/// meaningfully harder follow-ups, not built here. A DM call reuses this
/// same shared secret as the LiveKit frame-encryption key (see
/// `CallScreen`), so one key exchange covers both chat and calls for a
/// given pair.
///
/// Known limitation, stated plainly rather than hidden: there's no
/// cross-device key sync. A fresh install/new device gets a fresh keypair,
/// so a peer's client has to notice the public key changed (it just re-
/// derives the shared secret from whatever's on the server) — messages
/// encrypted to a now-superseded key on either side won't decrypt. There's
/// also no out-of-band key verification (no safety-number/QR compare), so
/// this defends against a passive/compromised server reading content, not
/// a server that actively swaps in a fake public key for someone (an
/// active MITM at the key-distribution layer).
class E2eCrypto {
  E2eCrypto._();

  static const _storage = FlutterSecureStorage();
  static const _privateKeyStorageKey = 'ta_e2e_private_key';
  static final _algorithm = X25519();

  static SimpleKeyPair? _cachedKeyPair;

  /// Loads the device's keypair, generating and persisting a fresh one on
  /// first call. Returns the public key as base64 — upload this once via
  /// `POST /me/public-key` (see `AppState._ensurePublicKey`).
  static Future<String> ensureKeyPair() async {
    final pair = await _loadOrCreateKeyPair();
    final publicKey = await pair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  static Future<SimpleKeyPair> _loadOrCreateKeyPair() async {
    if (_cachedKeyPair != null) return _cachedKeyPair!;
    final stored = await _storage.read(key: _privateKeyStorageKey);
    if (stored != null) {
      final bytes = base64Decode(stored);
      _cachedKeyPair = await _algorithm.newKeyPairFromSeed(bytes);
      return _cachedKeyPair!;
    }
    final pair = await _algorithm.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    await _storage.write(key: _privateKeyStorageKey, value: base64Encode(seed));
    _cachedKeyPair = pair;
    return pair;
  }

  /// The static DH shared secret with a peer's public key (base64) — same
  /// result on both sides, used directly as the AES key for chat and as
  /// the LiveKit frame-encryption key for calls. Returns null if the peer
  /// has no public key yet (chat/calls fall back to unencrypted for that
  /// pair — see callers).
  static Future<SecretKey?> sharedSecretWith(String? peerPublicKeyBase64) async {
    if (peerPublicKeyBase64 == null || peerPublicKeyBase64.isEmpty) return null;
    try {
      final pair = await _loadOrCreateKeyPair();
      final peerKey = SimplePublicKey(base64Decode(peerPublicKeyBase64), type: KeyPairType.x25519);
      return await _algorithm.sharedSecretKey(keyPair: pair, remotePublicKey: peerKey);
    } catch (_) {
      return null; // malformed peer key — treat exactly like "no key yet"
    }
  }

  /// The shared secret's raw bytes, hex-encoded — what LiveKit's
  /// `E2EEOptions.sharedKey` wants (see `CallScreen`).
  static Future<String> sharedSecretHex(SecretKey secret) async {
    final bytes = await secret.extractBytes();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static const _prefix = 'e2e1:'; // marks a message as this scheme's ciphertext, never plaintext by coincidence
  static final _aes = AesGcm.with256bits();

  /// Encrypts [plaintext] with [secret], returning `"e2e1:<base64(nonce|ciphertext|mac)>"`.
  static Future<String> encrypt(SecretKey secret, String plaintext) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: secret, nonce: nonce);
    final combined = Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
    return '$_prefix${base64Encode(combined)}';
  }

  static bool isEncrypted(String text) => text.startsWith(_prefix);

  /// Decrypts an `encrypt()` envelope. Returns null on any failure (wrong
  /// key, corrupted frame, not actually an e2e1 envelope) — callers show a
  /// "couldn't decrypt" placeholder rather than crashing on a malformed or
  /// foreign-key message.
  static Future<String?> decrypt(SecretKey secret, String envelope) async {
    if (!isEncrypted(envelope)) return null;
    try {
      final combined = base64Decode(envelope.substring(_prefix.length));
      const nonceLength = 12; // AES-GCM's standard nonce size, what newNonce() produces
      const macLength = 16;
      if (combined.length < nonceLength + macLength) return null;
      final nonce = combined.sublist(0, nonceLength);
      final mac = combined.sublist(combined.length - macLength);
      final cipherText = combined.sublist(nonceLength, combined.length - macLength);
      final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
      final clear = await _aes.decrypt(box, secretKey: secret);
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }
}
