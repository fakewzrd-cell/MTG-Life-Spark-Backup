import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mgt_life_spark/core/game/scryfall_service.dart';

http.Response _json(Object body, [int status = 200]) {
  return http.Response(jsonEncode(body), status);
}

Map<String, Object?> _card({
  String name = 'Lightning Bolt',
  String id = 'bolt',
  List<String> keywords = const [],
  List<String> colors = const ['R'],
  bool twoFaced = false,
}) {
  if (twoFaced) {
    return {
      'id': id,
      'name': name,
      'keywords': keywords,
      'color_identity': colors,
      'card_faces': [
        {
          'oracle_text': 'Transform.',
          'mana_cost': '{1}{G}',
          'type_line': 'Creature - Human Werewolf',
          'image_uris': {'art_crop': 'https://img/face.jpg'},
        },
      ],
    };
  }
  return {
    'id': id,
    'name': name,
    'oracle_text': 'Deal 3 damage.',
    'mana_cost': '{R}',
    'type_line': 'Instant',
    'keywords': keywords,
    'color_identity': colors,
    'image_uris': {'art_crop': 'https://img/bolt.jpg'},
  };
}

void main() {
  test('color identity unions partners in WUBRG order', () {
    const primary = ScryfallCard(name: 'A', colorIdentity: ['G', 'W']);
    const partner = ScryfallCard(name: 'B', colorIdentity: ['U', 'W', 'X']);
    expect(
      ScryfallCard.unionColorIdentity(primary, partner),
      ['W', 'U', 'G'],
    );
  });

  test('blank searches and missing card ids do no network work', () async {
    final service = ScryfallService(
      client: MockClient((_) async => _json({})),
    );
    expect(await service.searchCards('   '), isEmpty);
    expect(await service.searchCommanders(''), isEmpty);
    expect(await service.fetchCardFuzzy('  '), isNull);
    expect(await service.fetchRulings(null), isEmpty);
    expect(await service.fetchRulings(''), isEmpty);
  });

  test('search parses a normal card, a double-faced card, and empty results',
      () async {
    final service = ScryfallService(
      client: MockClient((request) async {
        final q = Uri.decodeQueryComponent(request.url.query);
        if (q.contains('name:Missing')) return _json({}, 404);
        if (q.contains('name:Broken')) return _json({}, 500);
        return _json({
          'data': [
            _card(keywords: ['Partner']),
            _card(name: 'Huntmaster', id: 'wolf', twoFaced: true, colors: ['G', 'R']),
          ],
        });
      }),
    );

    final cards = await service.searchCards('Bolt');
    expect(cards, hasLength(2));
    expect(cards.first.imageUrl, 'https://img/bolt.jpg');
    expect(cards.first.isPartner, isTrue);
    expect(cards.first.manaCost, '{R}');
    expect(cards.last.oracleText, 'Transform.');
    expect(cards.last.imageUrl, 'https://img/face.jpg');
    expect(cards.last.colorIdentity, ['G', 'R']);

    expect(await service.searchCommanders('Missing'), isEmpty);
    await expectLater(service.searchCards('Broken'), throwsException);
  });

  test('fuzzy, exact, and rulings lookups handle success and failure', () async {
    final service = ScryfallService(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/rulings')) {
          if (path.contains('missing')) return _json({}, 404);
          if (path.contains('down')) return _json({}, 503);
          return _json({
            'data': [
              {
                'comment': '  It resolves. ',
                'published_at': '2020-01-01',
                'source': 'wotc',
              },
              {'comment': '   '},
            ],
          });
        }
        if (request.url.query.contains('fuzzy=Nope')) return _json({}, 404);
        if (request.url.query.contains('exact=Nope')) {
          throw Exception('offline');
        }
        return _json(_card(name: 'Bolt'));
      }),
    );

    final fuzzy = await service.fetchCardFuzzy('Bolt');
    expect(fuzzy!.name, 'Bolt');
    expect(await service.fetchCardFuzzy('Nope'), isNull);
    expect(await service.fetchCardByName('Bolt'), isNotNull);
    expect(await service.fetchCardByName('Nope'), isNull);

    final rulings = await service.fetchRulings('bolt');
    expect(rulings, hasLength(1));
    expect(rulings!.single.comment, 'It resolves.');
    expect(await service.fetchRulings('missing'), isEmpty);
    expect(await service.fetchRulings('down'), isNull);
  });

  test('variant decks follow the next page and stop on an error', () async {
    final service = ScryfallService(
      client: MockClient((request) async {
        final q = Uri.decodeQueryComponent(request.url.query);
        if (q.contains('type:plane')) {
          if (!q.contains('page=')) {
            return _json({
              'data': [_card(name: 'Tazeem')],
              'next_page':
                  'https://api.scryfall.com/cards/search?q=type%3Aplane&page=2',
            });
          }
          return _json({'data': [_card(name: 'Phenom')]});
        }
        if (q.contains('type:scheme')) return _json({}, 500);
        return _json({'data': [_card(name: 'Bounty')]});
      }),
    );

    final planes = await service.fetchPlanarDeck();
    expect(planes.map((c) => c.name), ['Tazeem', 'Phenom']);
    expect(await service.fetchSchemeDeck(), isEmpty);
    expect((await service.fetchBountyDeck()).single.name, 'Bounty');
  });
}
