import 'package:atmon_models/atmon_models.dart';
import 'package:flutter/foundation.dart';

import 'atmon_client.dart';

/// Identifier for a single host: owner atSign that produced the data plus
/// the `deviceId` used for `CItem.id`. An agent atSign that runs multiple
/// devices will appear multiple times with the same owner.
@immutable
class HostKey {
  final String owner;
  final String deviceId;
  const HostKey(this.owner, this.deviceId);
  @override
  bool operator ==(Object other) =>
      other is HostKey && other.owner == owner && other.deviceId == deviceId;
  @override
  int get hashCode => Object.hash(owner, deviceId);
  @override
  String toString() => '$owner/$deviceId';
}

/// Roll-up view for a single host. Each metric is swapped in place by
/// `FleetStore.apply` when a new sample arrives, so the UI only rebuilds the
/// tiles that actually changed.
class HostState {
  final HostKey key;
  CpuStats? cpu;
  MemStats? mem;
  DiskStats? disk;
  NetStats? net;
  ProcSnapshot? procs;
  HostInfo? host;
  AlertList? alerts;
  DateTime lastUpdateAt;

  HostState({required this.key}) : lastUpdateAt = DateTime.now();

  /// Derive a simple status from the most recent alert set. `offline` is
  /// recognized by `FleetStore` via time since [lastSampledAt].
  Severity get status =>
      alerts?.worstSeverity ?? (cpu == null ? Severity.info : Severity.info);

  /// The most recent `sampledAt` we have seen from any metric. Used to flag
  /// offline hosts when the TTL on self-keys lets data age out but the
  /// publisher has stopped refreshing.
  DateTime? get lastSampledAt {
    DateTime? newest;
    void consider(DateTime? d) {
      if (d == null) return;
      if (newest == null || d.isAfter(newest!)) newest = d;
    }

    consider(cpu?.sampledAt);
    consider(mem?.sampledAt);
    consider(disk?.sampledAt);
    consider(net?.sampledAt);
    consider(procs?.sampledAt);
    consider(host?.sampledAt);
    consider(alerts?.sampledAt);
    return newest;
  }

  /// Returns true when the freshest metric is older than [offlineAfter].
  bool isOffline({Duration offlineAfter = const Duration(minutes: 2)}) {
    final s = lastSampledAt;
    if (s == null) return true;
    return DateTime.now().toUtc().difference(s.toUtc()) > offlineAfter;
  }
}

/// Merges [FleetUpdate]s into a map of [HostKey] → [HostState]. Listeners
/// (the Flutter UI) rebuild when any host is added, removed, or mutated.
class FleetStore extends ChangeNotifier {
  final Map<HostKey, HostState> _hosts = {};
  Map<HostKey, HostState> get hosts => Map.unmodifiable(_hosts);

  HostState? hostBy(HostKey k) => _hosts[k];

  void apply(FleetUpdate u) {
    final key = HostKey(u.owner, u.deviceId);
    if (u.deleted) {
      // Only fully remove the host if HostInfo/cpu go away — losing a single
      // metric leaves the tile in place but marks it stale via lastSampledAt.
      final existing = _hosts[key];
      if (existing == null) return;
      switch (u.category) {
        case AtmonCategory.cpu:
          existing.cpu = null;
        case AtmonCategory.mem:
          existing.mem = null;
        case AtmonCategory.disk:
          existing.disk = null;
        case AtmonCategory.net:
          existing.net = null;
        case AtmonCategory.procs:
          existing.procs = null;
        case AtmonCategory.host:
          _hosts.remove(key);
        case AtmonCategory.alerts:
          existing.alerts = null;
        case AtmonCategory.config:
          break;
      }
      existing.lastUpdateAt = u.at;
      notifyListeners();
      return;
    }

    final state = _hosts.putIfAbsent(key, () => HostState(key: key));
    switch (u.category) {
      case AtmonCategory.cpu:
        state.cpu = u.value as CpuStats;
      case AtmonCategory.mem:
        state.mem = u.value as MemStats;
      case AtmonCategory.disk:
        state.disk = u.value as DiskStats;
      case AtmonCategory.net:
        state.net = u.value as NetStats;
      case AtmonCategory.procs:
        state.procs = u.value as ProcSnapshot;
      case AtmonCategory.host:
        state.host = u.value as HostInfo;
      case AtmonCategory.alerts:
        state.alerts = u.value as AlertList;
      case AtmonCategory.config:
        break;
    }
    state.lastUpdateAt = u.at;
    notifyListeners();
  }
}
