/// How claimed seats share the One View table.
///
/// The table menu picks one of [optionsFor] the current player count.
/// Seats in the top half face the other way via [oneViewSeatUpsideDown].
enum OneViewSeatLayout {
  full,
  stacked,
  sideBySide,
  oneOverTwo,
  twoOverOne,
  oneBesideTwo,
  twoBesideOne,
  grid2x2,
  oneOverThree,
  threeOverOne,
  twoOverThree,
  threeOverTwo,
  threeOverThree,
  threeRowsOfTwo;

  static OneViewSeatLayout defaultFor(int seatCount) {
    return switch (seatCount) {
      2 => stacked,
      3 => oneOverTwo,
      4 => grid2x2,
      5 => twoOverThree,
      6 => threeOverThree,
      _ => full,
    };
  }

  static List<OneViewSeatLayout> optionsFor(int seatCount) {
    return switch (seatCount) {
      1 => const [full],
      2 => const [stacked, sideBySide],
      3 => const [oneOverTwo, twoOverOne, oneBesideTwo, twoBesideOne],
      4 => const [grid2x2, oneOverThree, threeOverOne],
      5 => const [twoOverThree, threeOverTwo],
      6 => const [threeOverThree, threeRowsOfTwo],
      _ => const [full],
    };
  }

  bool fits(int seatCount) => optionsFor(seatCount).contains(this);

  /// Row and column tree. Leaves are seat indexes, all upright.
  SeatSplit get split => switch (this) {
    full => const SeatLeaf(0),
    stacked => const SeatCol([SeatLeaf(0), SeatLeaf(1)]),
    sideBySide => const SeatRow([SeatLeaf(0), SeatLeaf(1)]),
    oneOverTwo => const SeatCol([
      SeatLeaf(0),
      SeatRow([SeatLeaf(1), SeatLeaf(2)]),
    ]),
    twoOverOne => const SeatCol([
      SeatRow([SeatLeaf(0), SeatLeaf(1)]),
      SeatLeaf(2),
    ]),
    oneBesideTwo => const SeatRow([
      SeatLeaf(0),
      SeatCol([SeatLeaf(1), SeatLeaf(2)]),
    ]),
    twoBesideOne => const SeatRow([
      SeatCol([SeatLeaf(0), SeatLeaf(1)]),
      SeatLeaf(2),
    ]),
    grid2x2 => const SeatCol([
      SeatRow([SeatLeaf(0), SeatLeaf(1)]),
      SeatRow([SeatLeaf(2), SeatLeaf(3)]),
    ]),
    oneOverThree => const SeatCol([
      SeatLeaf(0),
      SeatRow([SeatLeaf(1), SeatLeaf(2), SeatLeaf(3)]),
    ]),
    threeOverOne => const SeatCol([
      SeatRow([SeatLeaf(0), SeatLeaf(1), SeatLeaf(2)]),
      SeatLeaf(3),
    ]),
    twoOverThree => const SeatCol([
      SeatRow([SeatLeaf(0), SeatLeaf(1)]),
      SeatRow([SeatLeaf(2), SeatLeaf(3), SeatLeaf(4)]),
    ]),
    threeOverTwo => const SeatCol([
      SeatRow([SeatLeaf(0), SeatLeaf(1), SeatLeaf(2)]),
      SeatRow([SeatLeaf(3), SeatLeaf(4)]),
    ]),
    threeOverThree => const SeatCol([
      SeatRow([SeatLeaf(0), SeatLeaf(1), SeatLeaf(2)]),
      SeatRow([SeatLeaf(3), SeatLeaf(4), SeatLeaf(5)]),
    ]),
    threeRowsOfTwo => const SeatCol([
      SeatRow([SeatLeaf(0), SeatLeaf(1)]),
      SeatRow([SeatLeaf(2), SeatLeaf(3)]),
      SeatRow([SeatLeaf(4), SeatLeaf(5)]),
    ]),
  };
}

/// One node in a sitting layout. Leaves are seats; rows and columns share space.
sealed class SeatSplit {
  const SeatSplit();
}

class SeatLeaf extends SeatSplit {
  const SeatLeaf(this.index);

  final int index;
}

class SeatRow extends SeatSplit {
  const SeatRow(this.children);

  final List<SeatSplit> children;
}

class SeatCol extends SeatSplit {
  const SeatCol(this.children);

  final List<SeatSplit> children;
}

/// True when [seatIndex] sits in the top half, so that player faces the far edge.
bool oneViewSeatUpsideDown(SeatSplit split, int seatIndex) {
  final band = _seatBand(split, seatIndex, 0, 1);
  if (band == null) return false;
  return oneViewBandUpsideDown(band.$1, band.$2);
}

/// A band is the far side when its midpoint is above the middle of the table.
bool oneViewBandUpsideDown(double start, double end) => (start + end) / 2 < 0.5;

(double, double)? _seatBand(
  SeatSplit split,
  int seatIndex,
  double start,
  double end,
) {
  switch (split) {
    case SeatLeaf(:final index):
      if (index == seatIndex) return (start, end);
      return null;
    case SeatRow(:final children):
      for (final child in children) {
        final band = _seatBand(child, seatIndex, start, end);
        if (band != null) return band;
      }
      return null;
    case SeatCol(:final children):
      final count = children.length;
      if (count == 0) return null;
      for (var i = 0; i < count; i++) {
        final band = _seatBand(
          children[i],
          seatIndex,
          start + (end - start) * i / count,
          start + (end - start) * (i + 1) / count,
        );
        if (band != null) return band;
      }
      return null;
  }
}

/// Seat indexes in reading order. Used to check a layout covers every seat.
List<int> oneViewLayoutIndexes(SeatSplit split) {
  return switch (split) {
    SeatLeaf(:final index) => [index],
    SeatRow(:final children) => [
      for (final child in children) ...oneViewLayoutIndexes(child),
    ],
    SeatCol(:final children) => [
      for (final child in children) ...oneViewLayoutIndexes(child),
    ],
  };
}
