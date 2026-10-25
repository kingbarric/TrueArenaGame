import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import 'huud_kit.dart';

Future<Map<String, dynamic>?> askWhotSettings(
        BuildContext context, String mode) =>
    showHuudSheet<Map<String, dynamic>>(context,
        builder: (_) => WhotSettingsSheet(mode: mode));

/// Rules only. Creating, seating and starting the game stay in the Huud.
class WhotSettingsSheet extends StatefulWidget {
  const WhotSettingsSheet({super.key, required this.mode});
  final String mode;
  @override
  State<WhotSettingsSheet> createState() => _WhotSettingsSheetState();
}

class _WhotSettingsSheetState extends State<WhotSettingsSheet> {
  final _rules = <String, dynamic>{
    'turnSeconds': 60,
    'startingHand': 5,
    'includeWhot': false,
    'pickTwo': true,
    'pickTwoStacking': true,
    'generalMarket': true,
    'holdOn': true,
    'suspension': true,
    'tellRule': 'either',
    'tellMinCards': 3,
  };
  static const _labels = {
    'includeWhot': '20 · Whot wild cards',
    'pickTwo': '2 · Pick two',
    'pickTwoStacking': 'Stack pick twos',
    'generalMarket': '14 · General market',
    'holdOn': '1 · Hold on',
    'suspension': '8 · Skip a turn',
  };
  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    Widget number(String key, String title, List<int> choices, String unit) =>
        DropdownButtonFormField<int>(
          key: ValueKey('whot-setting-$key'),
          initialValue: _rules[key] as int,
          isExpanded: true,
          decoration: InputDecoration(labelText: title),
          items: [
            for (final v in choices)
              DropdownMenuItem(value: v, child: Text('$v $unit'))
          ],
          onChanged: (value) => setState(() => _rules[key] = value),
        );
    return SafeArea(
        child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .76,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text('Whot settings',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: n.ink))),
                IconButton(
                    tooltip: 'Close settings',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded)),
              ]),
              Text(
                  widget.mode == 'tell'
                      ? 'The Tell · Choose your house rules'
                      : 'Classic · Choose your house rules',
                  style: TextStyle(fontSize: 14, color: n.mid)),
              const SizedBox(height: 12),
              Expanded(
                  child: ListView(children: [
                number('startingHand', 'Cards per player',
                    [for (var i = 3; i <= 12; i++) i], 'cards'),
                const SizedBox(height: 12),
                number('turnSeconds', 'Turn time', const [60, 90], 'seconds'),
                const SizedBox(height: 14),
                for (final rule in _labels.entries)
                  SwitchListTile(
                    key: ValueKey('whot-rule-${rule.key}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(rule.value),
                    value: _rules[rule.key] as bool,
                    onChanged: (v) => setState(() => _rules[rule.key] = v),
                  ),
                if (widget.mode == 'tell') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('whot-setting-tellRule'),
                    initialValue: _rules['tellRule'] as String,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tell match'),
                    items: const [
                      DropdownMenuItem(
                          value: 'either', child: Text('Same value or shape')),
                      DropdownMenuItem(
                          value: 'value', child: Text('Same value')),
                      DropdownMenuItem(
                          value: 'shape', child: Text('Same shape'))
                    ],
                    onChanged: (v) => setState(() => _rules['tellRule'] = v),
                  ),
                  const SizedBox(height: 12),
                  number('tellMinCards', 'Minimum Tell',
                      [for (var i = 2; i <= 12; i++) i], 'cards'),
                ],
              ])),
              const SizedBox(height: 12),
              HuudButton(
                  key: const ValueKey('whot-settings-continue'),
                  label: 'Continue',
                  icon: Icons.arrow_forward_rounded,
                  expand: true,
                  onPressed: () => Navigator.pop(
                      context, Map<String, dynamic>.from(_rules))),
            ],
          )),
    ));
  }
}
