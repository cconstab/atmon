import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:atmon_models/atmon_models.dart';

/// Wraps the set of `AtCollection<T>` the dashboard subscribes to. Emits a
/// single unified [FleetUpdate] stream so `FleetStore` can merge them
/// without caring which metric category produced the event.
///
/// Note: `CEvent` itself carries only `(owner, id)` — the updated payload is
/// fetched on demand via `AtCollection.get(id, owner)`, which is the API's
/// incremental-update contract.
class AtmonClient {
  final AtClient atClient;
  final _log = AtSignLogger('AtmonClient');

  late final AtCollection<CpuStats> cpu;
  late final AtCollection<MemStats> mem;
  late final AtCollection<DiskStats> disk;
  late final AtCollection<NetStats> net;
  late final AtCollection<ProcSnapshot> procs;
  late final AtCollection<HostInfo> host;
  late final AtCollection<AlertList> alerts;

  final _controller = StreamController<FleetUpdate>.broadcast();
  final List<StreamSubscription> _subs = [];

  AtmonClient({required this.atClient}) {
    registerAtmonFactories();
    // The dashboard has no local store. Every get/scan must go to the remote
    // server; otherwise AtCollection calls return empty against an empty local
    // hive database.
    atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;
    cpu = AtCollection<CpuStats>(
        atClient, AtmonCategory.cpu.namespace, const Duration(minutes: 2));
    mem = AtCollection<MemStats>(
        atClient, AtmonCategory.mem.namespace, const Duration(minutes: 2));
    disk = AtCollection<DiskStats>(
        atClient, AtmonCategory.disk.namespace, const Duration(minutes: 15));
    net = AtCollection<NetStats>(
        atClient, AtmonCategory.net.namespace, const Duration(minutes: 2));
    procs = AtCollection<ProcSnapshot>(
        atClient, AtmonCategory.procs.namespace, const Duration(minutes: 5));
    host = AtCollection<HostInfo>(
        atClient, AtmonCategory.host.namespace, const Duration(minutes: 15));
    alerts = AtCollection<AlertList>(
        atClient, AtmonCategory.alerts.namespace, const Duration(minutes: 15));
  }

  Stream<FleetUpdate> get updates => _controller.stream;

  /// Fetch everything the @ server already has, then watch for changes.
  Future<void> start() async {
    await _attach<CpuStats>(cpu, AtmonCategory.cpu);
    await _attach<MemStats>(mem, AtmonCategory.mem);
    await _attach<DiskStats>(disk, AtmonCategory.disk);
    await _attach<NetStats>(net, AtmonCategory.net);
    await _attach<ProcSnapshot>(procs, AtmonCategory.procs);
    await _attach<HostInfo>(host, AtmonCategory.host);
    await _attach<AlertList>(alerts, AtmonCategory.alerts);
  }

  Future<void> _attach<T>(AtCollection<T> col, AtmonCategory cat) async {
    try {
      final seeded = await col.getItemsList();
      for (final item in seeded) {
        _controller.add(FleetUpdate(
          category: cat,
          owner: item.owner,
          deviceId: item.id,
          value: item.obj,
          deleted: false,
          at: DateTime.now(),
        ));
      }
    } catch (e) {
      _log.warning('${cat.name} seed failed: $e');
    }
    _subs.add(col.events.listen((evt) async {
      try {
        if (evt is CItemUpdated) {
          final item = await col.get(evt.id, evt.owner);
          _controller.add(FleetUpdate(
            category: cat,
            owner: item.owner,
            deviceId: item.id,
            value: item.obj,
            deleted: false,
            at: DateTime.now(),
          ));
        } else if (evt is CItemDeleted) {
          _controller.add(FleetUpdate(
            category: cat,
            owner: evt.owner,
            deviceId: evt.id,
            value: null,
            deleted: true,
            at: DateTime.now(),
          ));
        }
      } catch (e) {
        _log.warning('${cat.name} event handling failed: $e');
      }
    }, onError: (e) => _log.warning('${cat.name} stream error: $e')));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _controller.close();
  }
}

/// A single mutation pushed from the @ server. `value` is null when deleted.
class FleetUpdate {
  final AtmonCategory category;
  final String owner;
  final String deviceId;
  final Object? value;
  final bool deleted;
  final DateTime at;
  FleetUpdate({
    required this.category,
    required this.owner,
    required this.deviceId,
    required this.value,
    required this.deleted,
    required this.at,
  });
}
