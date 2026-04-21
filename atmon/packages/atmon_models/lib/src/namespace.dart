/// The application namespace for atmon. The fully-qualified namespace of a
/// metric collection is `<category>.<kAtmonNamespace>`, e.g.
/// `cpu.atmon.monitoring`.
const String kAtmonNamespace = 'atmon.monitoring';

/// The metric categories. The string value is the leaf of the collection
/// namespace AND the `type` string used in factory registration.
enum AtmonCategory {
  cpu,
  mem,
  disk,
  net,
  procs,
  host,
  alerts,
  config;

  String get namespace => '$name.$kAtmonNamespace';
  String get typeName => name;
}

/// Compose a full namespace from a category leaf, e.g. `cpu` ->
/// `cpu.atmon.monitoring`.
String atmonNamespace(AtmonCategory c) => c.namespace;
