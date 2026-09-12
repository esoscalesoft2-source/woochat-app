import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';

void main() {
  group('spliceEmoji', () {
    test('appends when the field was never focused', () {
      final (text, caret) = spliceEmoji('Hi', const TextSelection.collapsed(offset: -1), '😀');

      expect(text, 'Hi😀');
      expect(caret, 'Hi'.length + '😀'.length);
    });

    test('inserts at the caret rather than the end', () {
      final (text, caret) =
          spliceEmoji('Hello world', const TextSelection.collapsed(offset: 5), '😀');

      expect(text, 'Hello😀 world');
      expect(caret, 5 + '😀'.length);
    });

    test('replaces the selected range', () {
      final (text, caret) = spliceEmoji(
        'Hello world',
        const TextSelection(baseOffset: 0, extentOffset: 5),
        '👋',
      );

      expect(text, '👋 world');
      expect(caret, '👋'.length);
    });

    test('works on an empty field', () {
      final (text, caret) =
          spliceEmoji('', const TextSelection.collapsed(offset: 0), '🎉');

      expect(text, '🎉');
      expect(caret, '🎉'.length);
    });

    test('a multi-code-unit emoji advances the caret past all of it', () {
      // Skin-tone and ZWJ sequences are several code units long.
      const family = '👩‍💻';
      final (text, caret) =
          spliceEmoji('a', const TextSelection.collapsed(offset: 1), family);

      expect(text, 'a$family');
      expect(caret, 1 + family.length);
      expect(family.length, greaterThan(2));
    });
  });
}
