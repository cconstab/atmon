import 'dart:convert';

import 'package:atmon_models/atmon_models.dart';
import 'package:test/test.dart';

void main() {
  group('Diff', () {
    test('numChanged respects epsilon', () {
      expect(Diff.numChanged(10, 10.5, epsilon: 1), isFalse);
      expect(Diff.numChanged(10, 12, epsilon: 1), isTrue);
    });
    test('numListChanged on length / element', () {
      expect(Diff.numListChanged([1.0, 2.0], [1.0, 2.0]), isFalse);
      expect(Diff.numListChanged([1.0, 2.0], [1.0, 2.0, 3.0]), isTrue);
      expect(Diff.numListChanged([1.0, 2.0], [1.0, 2.5], epsilon: 0.4), isTrue);
    });
  });

  group('JSON round-trip', () {
    final now = DateTime.utc(2026, 4, 20, 12, 0);
    test('CpuStats', () {
      final s = CpuStats(
        coreUsage: const [10.5, 22.1, 5.0, 99.9],
        loadAvg: const [0.5, 1.2, 0.7],
        sampledAt: now,
        tempC: 51.2,
      );
      final back = CpuStats.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.coreUsage, s.coreUsage);
      expect(back.loadAvg, s.loadAvg);
      expect(back.tempC, s.tempC);
      expect(back.sampledAt.isAtSameMomentAs(s.sampledAt), isTrue);
      expect(back.changedFrom(s), isFalse);
    });
    test('MemStats / change detection', () {
      final a = MemStats(
        totalKb: 16000,
        usedKb: 8000,
        availKb: 8000,
        swapTotalKb: 4000,
        swapUsedKb: 0,
        sampledAt: now,
      );
      final b = MemStats(
        totalKb: 16000,
        usedKb: 8050,
        availKb: 7950,
        swapTotalKb: 4000,
        swapUsedKb: 0,
        sampledAt: now,
      );
      expect(b.changedFrom(a, pctEpsilon: 1), isFalse);
      final c = MemStats(
        totalKb: 16000,
        usedKb: 14000,
        availKb: 2000,
        swapTotalKb: 4000,
        swapUsedKb: 1000,
        sampledAt: now,
      );
      expect(c.changedFrom(a, pctEpsilon: 1), isTrue);
    });
    test('AlertList changedFrom on set / severity transition', () {
      final cpu = Alert(
        id: 'cpu.high',
        severity: Severity.warn,
        metric: 'cpu',
        value: 92,
        threshold: 90,
        message: 'CPU high',
        since: now,
      );
      final l1 = AlertList(active: [cpu], sampledAt: now);
      final l2 = AlertList(active: [cpu], sampledAt: now);
      expect(l2.changedFrom(l1), isFalse);
      final escalated = Alert(
        id: 'cpu.high',
        severity: Severity.crit,
        metric: 'cpu',
        value: 99,
        threshold: 90,
        message: 'CPU critical',
        since: now,
      );
      final l3 = AlertList(active: [escalated], sampledAt: now);
      expect(l3.changedFrom(l1), isTrue);
    });
  });
}
