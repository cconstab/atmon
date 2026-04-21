import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';

/// `Publisher<T>` wraps a single `AtCollection<T>` and is responsible for
/// turning a stream of fresh samples into the smallest possible number of
/// `AtCollection.put` calls.
///
/// Strategy:
///   * If [shouldPublish] returns true, write a CItem.
///   * Otherwise, write a CItem only if we are past the heartbeat window
///     ([heartbeatInterval]), so the dashboard always has a recent
///     `sampledAt` to detect liveness.
///
/// The publisher owns its `CItem`'s id ([itemId], usually the deviceId), the
/// list of recipient atSigns, and the last-published value. It is platform
/// agnostic and entirely pure-Dart, so it is straightforward to test with a
/// fake `AtCollection`.
class Publisher<T> {
  final AtCollection<T> collection;
  final String typeName;
  final String itemId;
  final List<String> shareWith;
  final Duration heartbeatInterval;
  final bool Function(T? prev, T next) shouldPublish;

  /// Optional minimum interval between two `put` calls regardless of
  /// [shouldPublish]. Protects the @ server when samples come in fast.
  final Duration minPutInterval;

  T? _lastPublished;
  DateTime _lastPutAt = DateTime.fromMillisecondsSinceEpoch(0);
  final AtSignLogger _log;

  Publisher({
    required this.collection,
    required this.typeName,
    required this.itemId,
    required this.shareWith,
    required this.shouldPublish,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.minPutInterval = const Duration(milliseconds: 250),
  }) : _log = AtSignLogger('Publisher<$T> $itemId');

  /// Last value we put on the wire (or null until first put). Exposed mainly
  /// for the alert engine.
  T? get lastPublished => _lastPublished;

  /// Consider [sample] for publication. Returns true when something was
  /// actually written to the @ server.
  Future<bool> consider(T sample) async {
    final now = DateTime.now();
    final dueForHeartbeat = now.difference(_lastPutAt) >= heartbeatInterval;
    final tooSoon = now.difference(_lastPutAt) < minPutInterval;
    final changed = shouldPublish(_lastPublished, sample);

    if (!changed && !dueForHeartbeat) return false;
    if (tooSoon && !dueForHeartbeat) return false;

    try {
      final item = collection.create(
        type: typeName,
        id: itemId,
        obj: sample,
        sharedWith: shareWith.map((s) => s.toAtsign()).toSet(),
      );
      // Force the recipient set to match shareWith (drop dropped monitors).
      final results = await collection.put(item, unshareWithOthers: true);
      _lastPublished = sample;
      _lastPutAt = now;
      _log.info('put $itemId — ${changed ? "changed" : "heartbeat"} '
          '(${results.length} ops)');
      return true;
    } catch (e, st) {
      _log.severe('put failed: $e\n$st');
      return false;
    }
  }
}
