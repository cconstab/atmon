import 'package:at_client/at_client.dart';

import 'models/alert.dart';
import 'models/config.dart';
import 'models/cpu.dart';
import 'models/disk.dart';
import 'models/host.dart';
import 'models/mem.dart';
import 'models/net.dart';
import 'models/proc.dart';
import 'namespace.dart';

bool _registered = false;

/// Register a factory with [AtCollection] for every atmon CItem payload type.
/// Must be called before constructing any `AtCollection<T>` so that
/// `AtCollection.get*` can decode incoming JSON. Idempotent.
void registerAtmonFactories() {
  if (_registered) return;
  AtCollection.registerFactory(
      type: AtmonCategory.cpu.typeName, factory: CpuStats.fromJson);
  AtCollection.registerFactory(
      type: AtmonCategory.mem.typeName, factory: MemStats.fromJson);
  AtCollection.registerFactory(
      type: AtmonCategory.disk.typeName, factory: DiskStats.fromJson);
  AtCollection.registerFactory(
      type: AtmonCategory.net.typeName, factory: NetStats.fromJson);
  AtCollection.registerFactory(
      type: AtmonCategory.procs.typeName, factory: ProcSnapshot.fromJson);
  AtCollection.registerFactory(
      type: AtmonCategory.host.typeName, factory: HostInfo.fromJson);
  AtCollection.registerFactory(
      type: AtmonCategory.alerts.typeName, factory: AlertList.fromJson);
  AtCollection.registerFactory(
      type: AtmonCategory.config.typeName, factory: MonitorConfig.fromJson);
  _registered = true;
}
