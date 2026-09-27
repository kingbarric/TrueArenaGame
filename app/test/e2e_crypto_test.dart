import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/core/e2e_crypto.dart';

/// Correctness proofs for the DM encryption primitives. The keypair-storage
/// path (secure storage) is exercised live on a device instead — these
/// cover the parts that must be right for the ciphertext to be worth
/// anything: a real round-trip, and a *wrong* key genuinely failing rather
/// than silently returning garbage.
void main() {
  final x25519 = X25519();

  test('a DM round-trips through encrypt/decrypt with the shared secret', () async {
    final alice = await x25519.newKeyPair();
    final bob = await x25519.newKeyPair();

    // Both sides derive the same static DH secret independently.
    final aliceSecret = await x25519.sharedSecretKey(
        keyPair: alice, remotePublicKey: await bob.extractPublicKey());
    final bobSecret = await x25519.sharedSecretKey(
        keyPair: bob, remotePublicKey: await alice.extractPublicKey());
    expect(await aliceSecret.extractBytes(), await bobSecret.extractBytes(),
        reason: 'X25519 must agree on the same secret from either side');

    final envelope = await E2eCrypto.encrypt(aliceSecret, 'meet me at the round table 🕵️');
    expect(E2eCrypto.isEncrypted(envelope), isTrue);
    expect(envelope.contains('round table'), isFalse, reason: 'the plaintext must not survive in the envelope');

    final decrypted = await E2eCrypto.decrypt(bobSecret, envelope);
    expect(decrypted, 'meet me at the round table 🕵️');
  });

  test('a third party with a different key cannot decrypt', () async {
    final alice = await x25519.newKeyPair();
    final bob = await x25519.newKeyPair();
    final eve = await x25519.newKeyPair();

    final aliceToBob = await x25519.sharedSecretKey(
        keyPair: alice, remotePublicKey: await bob.extractPublicKey());
    final eveToAlice = await x25519.sharedSecretKey(
        keyPair: eve, remotePublicKey: await alice.extractPublicKey());

    final envelope = await E2eCrypto.encrypt(aliceToBob, 'the traitors are Sam and Ada');
    expect(await E2eCrypto.decrypt(eveToAlice, envelope), isNull,
        reason: 'a wrong key must fail closed (null), never return garbage plaintext');
  });

  test('a tampered envelope fails authentication instead of decrypting', () async {
    final alice = await x25519.newKeyPair();
    final bob = await x25519.newKeyPair();
    final secret = await x25519.sharedSecretKey(
        keyPair: alice, remotePublicKey: await bob.extractPublicKey());

    final envelope = await E2eCrypto.encrypt(secret, 'transfer 500 coins');
    // flip a character in the base64 body — GCM's MAC must catch it
    final body = envelope.substring('e2e1:'.length);
    final tamperedChar = body[10] == 'A' ? 'B' : 'A';
    final tampered = 'e2e1:${body.substring(0, 10)}$tamperedChar${body.substring(11)}';

    expect(await E2eCrypto.decrypt(secret, tampered), isNull);
  });

  test('plaintext (a legacy or group message) is recognised as not encrypted', () async {
    expect(E2eCrypto.isEncrypted('hey, just a normal message'), isFalse);

    final alice = await x25519.newKeyPair();
    final bob = await x25519.newKeyPair();
    final secret = await x25519.sharedSecretKey(
        keyPair: alice, remotePublicKey: await bob.extractPublicKey());
    expect(await E2eCrypto.decrypt(secret, 'hey, just a normal message'), isNull,
        reason: 'decrypt must decline anything that is not an e2e1 envelope');
  });

  test('sharedSecretWith returns null for a peer with no key yet', () async {
    expect(await E2eCrypto.sharedSecretWith(null), isNull);
    expect(await E2eCrypto.sharedSecretWith(''), isNull);
  });
}
