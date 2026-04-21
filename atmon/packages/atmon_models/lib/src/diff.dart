import 'dart:math' as math;

/// Field-level change-detection helpers used by the agent's [Publisher] to
/// decide whether a freshly sampled metric is worth `put`-ing.
///
/// All helpers are pure (no I/O) and treat `null`/`prev` as "always changed".
class Diff {
  /// True if [a] and [b] differ by more than [epsilon] (absolute).
  static bool numChanged(num a, num b, {num epsilon = 0}) {
    return (a - b).abs() > epsilon;
  }

  /// True if any list element of [a] and [b] differs by more than [epsilon].
  /// Different lengths count as changed.
  static bool numListChanged(List<num> a, List<num> b, {num epsilon = 0}) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (numChanged(a[i], b[i], epsilon: epsilon)) return true;
    }
    return false;
  }

  /// Two ordered string lists are considered changed if their elements
  /// or order differ.
  static bool stringListChanged(List<String> a, List<String> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  /// Two unordered string sets are considered changed if their members
  /// differ (set equality).
  static bool stringSetChanged(Set<String> a, Set<String> b) {
    if (a.length != b.length) return true;
    return !a.containsAll(b);
  }

  /// True if any value in [a] differs from [b] by more than [epsilon] for
  /// the keys present in both maps, or if their key sets differ.
  static bool numMapChanged(
    Map<String, num> a,
    Map<String, num> b, {
    num epsilon = 0,
  }) {
    if (a.length != b.length) return true;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return true;
      if (numChanged(a[k]!, b[k]!, epsilon: epsilon)) return true;
    }
    return false;
  }

  /// Convenience: percent change between [prev] and [next] as 0..100. Returns
  /// 100 when [prev] is zero and [next] non-zero.
  static double percentChange(num prev, num next) {
    if (prev == 0) return next == 0 ? 0 : 100;
    return ((next - prev).abs() / prev.abs()) * 100;
  }

  /// True when at least one entry in [pairs] satisfies its predicate.
  /// Each entry is a `(prev, next, epsilon)` tuple-style record; this is
  /// here mainly to keep model `changedFrom` methods compact.
  static bool any(Iterable<bool> tests) => tests.any((t) => t);

  /// Round a double to [digits] decimal places. Used by samplers so identical
  /// rounded values are treated as equal by [numChanged].
  static double round(num v, {int digits = 1}) {
    final f = math.pow(10, digits);
    return (v * f).round() / f;
  }
}
