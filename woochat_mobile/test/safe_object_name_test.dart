import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/attachments_repository.dart';

void main() {
  group('safeObjectName', () {
    test('a macOS screenshot name, narrow no-break space and all', () {
      expect(
        safeObjectName('1789452167757_Screenshot 2026-09-15 at 10.46.59 AM.png'),
        '1789452167757_Screenshot_2026-09-15_at_10.46.59_AM.png',
      );
    });

    test('keeps a plain name exactly', () {
      expect(safeObjectName('invoice-2026_09.pdf'), 'invoice-2026_09.pdf');
    });

    test('non-ASCII, brackets and repeated separators', () {
      expect(safeObjectName('டீ ஷர்ட் (final)  copy.jpg'), 'final_copy.jpg');
      expect(safeObjectName('a  b   c.png'), 'a_b_c.png');
    });

    test('never returns an empty key', () {
      expect(safeObjectName('   '), 'file');
      expect(safeObjectName('___'), 'file');
    });
  });
}
