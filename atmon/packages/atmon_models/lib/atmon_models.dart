/// Shared payload models for the atmon agent + dashboard.
///
/// Every model implements [toJson]/[fromJson] and is registered with
/// [AtCollection.registerFactory] via [registerAtmonFactories]. The
/// `type` string of each model **must** match the leaf of the
/// collection's namespace so that on decode the right factory fires.
library;

export 'src/factories.dart';
export 'src/diff.dart';
export 'src/namespace.dart';
export 'src/models/cpu.dart';
export 'src/models/mem.dart';
export 'src/models/disk.dart';
export 'src/models/net.dart';
export 'src/models/proc.dart';
export 'src/models/host.dart';
export 'src/models/alert.dart';
export 'src/models/config.dart';
