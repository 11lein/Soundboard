import 'package:flutter_test/flutter_test.dart';
import 'package:soundboard_remote/widgets/key_title.dart';

void main() {
  group('wrapKeyTitle', () {
    test('leaves a short single-word title on one line', () {
      expect(wrapKeyTitle('horn'), 'horn');
    });

    test('never produces a line longer than 12 characters', () {
      for (final s in [
        'AirHornLoudExtreme',
        'supercalifragilistic',
        'Bank Six Final Boss Tone',
        'ÄußerstLangerDeutscherTitel',
      ]) {
        for (final line in wrapKeyTitle(s).split('\n')) {
          expect(line.length, lessThanOrEqualTo(12), reason: 'line "$line" of "$s"');
        }
      }
    });

    test('never produces more than three lines', () {
      expect(
        wrapKeyTitle('OneTwoThreeFourFiveSixSevenEightNine').split('\n').length,
        lessThanOrEqualTo(3),
      );
    });

    test('truncates overflowing text with an ellipsis on the third line', () {
      // A long all-lowercase run fills three 12-char lines and then runs out.
      final out = wrapKeyTitle('a' * 60);
      final lines = out.split('\n');
      expect(lines.length, 3);
      expect(lines.last.endsWith('…'), isTrue);
    });

    test('breaks before a capital once the current line is long enough', () {
      // "Airhorn" (7 chars) is already past the ~6-char merge threshold, so the
      // next capital-led word starts a new line instead of merging.
      expect(wrapKeyTitle('AirhornBlast').split('\n'), ['Airhorn', 'Blast']);
    });
  });
}
