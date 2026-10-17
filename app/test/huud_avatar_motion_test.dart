import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/huudspace/huud_avatar_motion.dart';

void main() {
  test(
      'movement changes only the authenticated sender, ignoring claimed identities and invalid poses',
      () {
    final state = HuudAvatarMotion();
    addTearDown(state.dispose);
    state.receive('ava', {'userId': 'host', 'mode': 'walk'});
    expect(state.mode('ava'), 'walk');
    expect(state.mode('host'), 'sit');
    state.receive('ava', {'mode': 'invalid'});
    state.receive('', {'mode': 'stand'});
    expect(state.mode('ava'), 'walk');
    expect(state.modes, {'ava': 'walk'});
  });
  test(
      'local movement remains usable without a voice connection and does not notify on duplicates',
      () {
    final state = HuudAvatarMotion();
    addTearDown(state.dispose);
    int updates = 0;
    state.addListener(() => updates++);
    state.move('me', 'stand');
    state.move('me', 'stand');
    state.move('me', 'sit');
    expect(updates, 2);
    expect(state.mode('me'), 'sit');
  });
}
