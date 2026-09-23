import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/bluetooth/ble_message.dart';
import 'package:mgt_life_spark/core/bluetooth/ble_protocol.dart';
import 'package:mgt_life_spark/core/bluetooth/ble_service.dart';
import 'package:mgt_life_spark/core/network/ws_host_service.dart';

void main() {
  group('host Wi-Fi rules', () {
    late WsHostService host;

    setUp(() async {
      host = WsHostService(
        hostPlayerId: 'host',
        hostUsername: 'Host',
        joinToken: 'table-token',
        reconnectGrace: const Duration(milliseconds: 200),
      );
      await host.initialize();
    });

    tearDown(() async {
      await host.dispose();
    });

    test('a wrong app version and a ping are handled before anyone sits down',
        () async {
      final socket = await _connect(host);
      addTearDown(socket.close);

      final replies = _replies(socket);
      socket.add(jsonEncode(BleMessage.hello(1, joinToken: 'table-token')
          .toJson()
        ..['p'] = {'version': '0.1', 'token': 'table-token'}));

      final reject = await replies.next();
      expect(reject.type, BleMessageType.reject);
      expect(reject.payload['reason'], 'versionMismatch');
    });

    test('the host echoes a ping and ignores junk or an unverified life change',
        () async {
      final socket = await _connect(host);
      addTearDown(socket.close);
      final replies = _replies(socket);

      socket.add('{not json');
      socket.add(
        jsonEncode(
          BleMessage(
            type: BleMessageType.stateDelta,
            payload: {'pid': 'guest', 'field': 'life', 'val': 1},
            seqNum: 1,
          ).toJson(),
        ),
      );
      socket.add(
        jsonEncode(
          BleMessage(
            type: BleMessageType.sessionPing,
            payload: const {},
            seqNum: 2,
          ).toJson(),
        ),
      );

      final ping = await replies.next();
      expect(ping.type, BleMessageType.sessionPing);
      expect(host.connectedPlayerIds, isEmpty);
    });

    test('a seated player cannot send another seat life change', () async {
      final guest = await _sit(host, 'guest');
      addTearDown(guest.socket.close);

      final seen = <BleMessage>[];
      final sub = host.messageStream.listen(seen.add);

      guest.socket.add(
        jsonEncode(
          BleMessage(
            type: BleMessageType.stateDelta,
            payload: {'pid': 'someone-else', 'field': 'life', 'val': 10},
            seqNum: 4,
          ).toJson(),
        ),
      );
      guest.socket.add(
        jsonEncode(
          BleMessage(
            type: BleMessageType.stateDelta,
            payload: {
              'pid': 'guest',
              'origin': 'guest',
              'field': 'life',
              'val': 39,
            },
            seqNum: 5,
          ).toJson(),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(seen.where((m) => m.type == BleMessageType.stateDelta), hasLength(1));
      expect(seen.last.payload['val'], 39);
      await sub.cancel();
    });

    test('a drop stays reconnecting, then the host is told they are gone',
        () async {
      final guest = await _sit(host, 'guest');
      final events = <BleConnectionStatus>[];
      final sub = host.connectionStream.listen((e) {
        if (e.playerId == 'guest') events.add(e.status);
      });

      await guest.socket.close();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        events,
        containsAllInOrder([
          BleConnectionStatus.reconnecting,
          BleConnectionStatus.disconnected,
        ]),
      );
      await sub.cancel();
    });

    test('coming back during the wait tells the rest of the table', () async {
      final other = await _sit(host, 'other');
      addTearDown(other.socket.close);

      final guest = await _sit(host, 'guest');
      final dropped = Completer<void>();
      final sub = host.connectionStream.listen((e) {
        if (e.playerId == 'guest' &&
            e.status == BleConnectionStatus.reconnecting &&
            !dropped.isCompleted) {
          dropped.complete();
        }
      });
      await guest.socket.close();
      await dropped.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      final again = await _sit(host, 'guest');
      addTearDown(again.socket.close);

      final notice = await other.replies.nextWhere(
        (m) =>
            m.type == BleMessageType.playerReconnecting &&
            m.payload['done'] == true,
      );
      expect(notice.payload['pid'], 'guest');
      expect(host.connectedPlayerIds, containsAll(['other', 'guest']));
    });

    test('the host can keep waiting or stop waiting for a dropped seat',
        () async {
      final guest = await _sit(host, 'guest');
      final events = <BleConnectionStatus>[];
      final reconnecting = Completer<void>();
      final sub = host.connectionStream.listen((e) {
        if (e.playerId != 'guest') return;
        events.add(e.status);
        if (e.status == BleConnectionStatus.reconnecting &&
            !reconnecting.isCompleted) {
          reconnecting.complete();
        }
      });
      await guest.socket.close();
      await reconnecting.future.timeout(const Duration(seconds: 2));

      host.cancelReconnectGrace('guest');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(events, isNot(contains(BleConnectionStatus.disconnected)));

      host.extendReconnectGrace('guest');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(events, contains(BleConnectionStatus.disconnected));
      await sub.cancel();
    });

    test('a message aimed at one player does not reach the other', () async {
      final alice = await _sit(host, 'alice');
      final bob = await _sit(host, 'bob');
      addTearDown(alice.socket.close);
      addTearDown(bob.socket.close);

      await host.send(
        BleMessage(
          type: BleMessageType.stateSnapshot,
          payload: const {'for': 'alice'},
          seqNum: 9,
        ),
        targetPlayerId: 'alice',
      );

      final snapshot = await alice.replies.next();
      expect(snapshot.type, BleMessageType.stateSnapshot);
      expect(snapshot.payload['for'], 'alice');

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(bob.replies.pending, 0);
    });
  });
}

Future<WebSocket> _connect(WsHostService host) {
  return WebSocket.connect('ws://127.0.0.1:${host.port}');
}

class _Seat {
  _Seat(this.socket, this.replies);
  final WebSocket socket;
  final _ReplyQueue replies;
}

Future<_Seat> _sit(WsHostService host, String playerId) async {
  final socket = await _connect(host);
  final replies = _replies(socket);
  final joined = host.messageStream.firstWhere(
    (m) =>
        m.type == BleMessageType.lobbyPlayerJoined &&
        m.payload['pid'] == playerId,
  );
  socket.add(
    jsonEncode(
      BleMessage.hello(1, joinToken: host.joinToken).toJson(),
    ),
  );
  final hello = await replies.next();
  expect(hello.type, BleMessageType.hello);
  socket.add(
    jsonEncode(
      BleMessage(
        type: BleMessageType.lobbyPlayerJoined,
        payload: {'pid': playerId, 'username': playerId},
        seqNum: 2,
      ).toJson(),
    ),
  );
  await joined.timeout(const Duration(seconds: 2));
  return _Seat(socket, replies);
}

class _ReplyQueue {
  _ReplyQueue(WebSocket socket) {
    _sub = socket.listen((data) {
      if (data is! String) return;
      final message = BleMessage.fromJson(
        jsonDecode(data) as Map<String, dynamic>,
      );
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(message);
      } else {
        _buffered.add(message);
      }
    });
  }

  final _buffered = <BleMessage>[];
  int get pending => _buffered.length;
  final _waiters = <Completer<BleMessage>>[];
  late final StreamSubscription<dynamic> _sub;

  Future<BleMessage> next() {
    if (_buffered.isNotEmpty) return Future.value(_buffered.removeAt(0));
    final waiter = Completer<BleMessage>();
    _waiters.add(waiter);
    return waiter.future.timeout(const Duration(seconds: 2));
  }

  Future<BleMessage> nextWhere(bool Function(BleMessage) test) async {
    while (true) {
      final message = await next();
      if (test(message)) return message;
    }
  }

  Future<void> cancel() => _sub.cancel();
}

_ReplyQueue _replies(WebSocket socket) => _ReplyQueue(socket);
