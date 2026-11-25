import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/one_view/one_view_layout.dart';

void main() {
  test('each player count only offers layouts that cover those seats', () {
    for (var count = 1; count <= 6; count++) {
      final options = OneViewSeatLayout.optionsFor(count);
      expect(options, isNotEmpty);
      expect(options, contains(OneViewSeatLayout.defaultFor(count)));
      for (final layout in options) {
        expect(layout.fits(count), isTrue);
        final indexes = oneViewLayoutIndexes(layout.split)..sort();
        expect(indexes, List<int>.generate(count, (i) => i));
      }
    }
  });

  test('the far side faces the other way', () {
    expect(oneViewSeatUpsideDown(OneViewSeatLayout.full.split, 0), isFalse);
    expect(oneViewSeatUpsideDown(OneViewSeatLayout.stacked.split, 0), isTrue);
    expect(oneViewSeatUpsideDown(OneViewSeatLayout.stacked.split, 1), isFalse);
    expect(
      oneViewSeatUpsideDown(OneViewSeatLayout.sideBySide.split, 0),
      isFalse,
    );
    expect(
      oneViewSeatUpsideDown(OneViewSeatLayout.sideBySide.split, 1),
      isFalse,
    );
    expect(oneViewSeatUpsideDown(OneViewSeatLayout.grid2x2.split, 0), isTrue);
    expect(oneViewSeatUpsideDown(OneViewSeatLayout.grid2x2.split, 1), isTrue);
    expect(oneViewSeatUpsideDown(OneViewSeatLayout.grid2x2.split, 2), isFalse);
    expect(oneViewSeatUpsideDown(OneViewSeatLayout.grid2x2.split, 3), isFalse);
    expect(
      oneViewSeatUpsideDown(OneViewSeatLayout.oneBesideTwo.split, 0),
      isFalse,
    );
    expect(
      oneViewSeatUpsideDown(OneViewSeatLayout.oneBesideTwo.split, 1),
      isTrue,
    );
    expect(
      oneViewSeatUpsideDown(OneViewSeatLayout.oneBesideTwo.split, 2),
      isFalse,
    );
    expect(
      oneViewSeatUpsideDown(OneViewSeatLayout.threeRowsOfTwo.split, 0),
      isTrue,
    );
    expect(
      oneViewSeatUpsideDown(OneViewSeatLayout.threeRowsOfTwo.split, 2),
      isFalse,
    );
    expect(
      oneViewSeatUpsideDown(OneViewSeatLayout.threeRowsOfTwo.split, 4),
      isFalse,
    );
  });

  test('a layout for one count does not fit another', () {
    expect(OneViewSeatLayout.sideBySide.fits(2), isTrue);
    expect(OneViewSeatLayout.sideBySide.fits(3), isFalse);
    expect(OneViewSeatLayout.grid2x2.fits(4), isTrue);
    expect(OneViewSeatLayout.grid2x2.fits(5), isFalse);
  });
}
