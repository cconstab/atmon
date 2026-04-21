import 'dart:io';

import 'package:atmon_models/atmon_models.dart';

/// Common interface for a metric sampler. Implementations live under
/// `samplers/` and pick a Linux or macOS strategy at construction time.
abstract class Sampler<T> {
  Future<T?> sample();
}

/// Pick the right concrete sampler for the running platform. macOS support is
/// development-only; production targets Linux.
Sampler<T> samplerFor<T>(Sampler<T> linux, Sampler<T> macos) {
  if (Platform.isLinux) return linux;
  if (Platform.isMacOS) return macos;
  throw UnsupportedError('atmon_agent only runs on Linux or macOS');
}

/// Convenience: utc-now rounded to milliseconds for stable JSON output.
DateTime nowUtc() => DateTime.now().toUtc();

/// Run a process and return its stdout. Returns empty string on failure.
Future<String> runCmd(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args);
    if (r.exitCode != 0) return '';
    return r.stdout.toString();
  } catch (_) {
    return '';
  }
}

/// Read a file; returns empty string on failure.
Future<String> readFileSafe(String path) async {
  try {
    return await File(path).readAsString();
  } catch (_) {
    return '';
  }
}

/// Re-export so concrete samplers don't have to import the namespace file.
String fqNamespace(AtmonCategory c) => atmonNamespace(c);
