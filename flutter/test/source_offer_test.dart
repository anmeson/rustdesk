// The AGPL notices are a legal deliverable, so they get a test: a silent
// regression here is not a cosmetic bug, it is a distribution that no longer
// tells its users where the source is.
//
// `source_offer.dart` imports nothing, so this runs as a plain unit test.
//
// The commit-stamp half only means anything when the define is set, which is
// how a release is built:
//
//   flutter test test/source_offer_test.dart \
//     --dart-define=ANMESON_SOURCE_COMMIT=deadbeef --dart-define=ANMESON_SOURCE_DATE=2026-09-15
//
// Undefined, the two stamped tests are skipped rather than asserting the
// fallback -- a green run here must not be read as "the release build is
// stamped". docs/LICENSING.md is where that gate lives.

import 'package:flutter_hbb/common/widgets/source_offer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AGPL §5(a) modification notice', () {
    test('says it is modified, and by whom', () {
      expect(modificationNotice, contains('modified version of RustDesk'));
      expect(modificationNotice, contains(kModifierName));
    });

    test('disclaims upstream', () {
      expect(modificationNotice, contains('not distributed by'));
    });
  });

  group('offer of corresponding source', () {
    test('names the licence', () {
      expect(sourceOfferNotice, contains('AGPL-3.0'));
      expect(sourceOfferNotice,
          contains('GNU Affero General Public License, version 3'));
    });

    test('names both repositories -- client and the server it talks to', () {
      expect(sourceOfferNotice, contains(kClientSourceUrl));
      expect(sourceOfferNotice, contains(kServerSourceUrl));
    });

    test('the URLs are public https, not ssh or a placeholder', () {
      for (final url in [kClientSourceUrl, kServerSourceUrl]) {
        expect(url, startsWith('https://github.com/anmeson/'));
        expect(url, isNot(contains('example')));
      }
    });
  });

  group('build stamp', () {
    test('an unstamped build says so instead of naming a commit', () {
      if (kSourceCommit.isNotEmpty) return;
      expect(sourceOfferNotice, contains('unreleased local build'));
    });

    test('a stamped build carries the commit', () {
      if (kSourceCommit.isEmpty) {
        markTestSkipped('ANMESON_SOURCE_COMMIT not defined');
        return;
      }
      expect(sourceOfferNotice, contains(kSourceCommit));
      expect(sourceOfferNotice, isNot(contains('unreleased local build')));
    });

    test('a stamped date reaches the modification notice', () {
      if (kSourceDate.isEmpty) {
        markTestSkipped('ANMESON_SOURCE_DATE not defined');
        return;
      }
      expect(modificationNotice, contains(kSourceDate));
    });
  });
}
