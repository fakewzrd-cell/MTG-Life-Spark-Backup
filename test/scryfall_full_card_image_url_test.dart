import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/scryfall_service.dart';

void main() {
  test('swaps Scryfall art_crop path to the full card', () {
    expect(
      scryfallFullCardImageUrl(
        'https://cards.scryfall.io/art_crop/front/a/b/uuid.jpg?1',
      ),
      'https://cards.scryfall.io/normal/front/a/b/uuid.jpg?1',
    );
  });

  test('leaves full-card and non-Scryfall URLs unchanged', () {
    const normal = 'https://cards.scryfall.io/normal/front/a/b/uuid.jpg';
    const other = 'https://example.com/krenko.jpg';
    expect(scryfallFullCardImageUrl(normal), normal);
    expect(scryfallFullCardImageUrl(other), other);
  });

  test('passes through empty values', () {
    expect(scryfallFullCardImageUrl(null), isNull);
    expect(scryfallFullCardImageUrl(''), '');
    expect(scryfallFullCardImageUrl('   '), '   ');
  });

  test('listing URL prefers the full card face', () {
    const card = ScryfallCard(
      name: 'Sol Ring',
      imageUrl: 'https://cards.scryfall.io/art_crop/front/a/b/uuid.jpg',
      cardFaceUrl: 'https://cards.scryfall.io/normal/front/a/b/uuid.jpg',
    );
    expect(scryfallDisplayCardUrl(card), card.cardFaceUrl);
    expect(
      scryfallDisplayCardUrl(
        const ScryfallCard(
          name: 'Bolt',
          imageUrl: 'https://cards.scryfall.io/art_crop/front/a/b/bolt.jpg',
        ),
      ),
      'https://cards.scryfall.io/normal/front/a/b/bolt.jpg',
    );
  });
}
