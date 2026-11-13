import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('l10n ARB files stay free of banned colloquialisms, AI-slop, and emojis',
      () {
    final zhMap = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
        as Map<String, dynamic>;
    final enMap = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;

    final zhKeys = zhMap.keys.where((k) => !k.startsWith('@')).toSet();
    final enKeys = enMap.keys.where((k) => !k.startsWith('@')).toSet();
    expect(enKeys, containsAll(zhKeys), reason: 'Every zh key must have en');

    const bannedSubstrings = [
      '你说了算',
      '悄悄',
      '什么都不坏',
      '折腾',
      '无缝衔接',
      '智能赋能',
      '高效之旅',
      '贴心守护',
      'seamlessly',
      'empower',
      'elevate',
      '!',
      '！',
    ];

    final emojiRegex = RegExp(
      r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
      unicode: true,
    );

    for (final entry in [...zhMap.entries, ...enMap.entries]) {
      if (entry.key.startsWith('@')) continue;
      final value = '${entry.value}';
      for (final banned in bannedSubstrings) {
        expect(
          value.toLowerCase().contains(banned.toLowerCase()),
          isFalse,
          reason: 'Found banned copy "$banned" in ${entry.key}: $value',
        );
      }
      expect(
        emojiRegex.hasMatch(value),
        isFalse,
        reason: 'Found decorative emoji in ${entry.key}: $value',
      );
    }
  });
}
