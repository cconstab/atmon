import 'package:atmon_models/atmon_models.dart';
import 'package:flutter/material.dart';

import '../services/fleet_store.dart';
import 'host_detail.dart';

/// A scrollable grid of host tiles inspired by btop. Each tile summarises CPU,
/// memory, worst alert, and liveness in a compact card. Tapping opens
/// [HostDetail].
class FleetGrid extends StatelessWidget {
  final FleetStore store;
  const FleetGrid({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final hosts = store.hosts;
    if (hosts.isEmpty) {
      return const Center(
          child: Text('No hosts yet — start atmon_agent to send data.'));
    }
    final sorted = hosts.values.toList()
      ..sort((a, b) {
        // Push offline hosts to the end, then sort by worst alert severity.
        final aOff = a.isOffline() ? 1 : 0;
        final bOff = b.isOffline() ? 1 : 0;
        if (aOff != bOff) return aOff - bOff;
        return b.status.index.compareTo(a.status.index);
      });
    return LayoutBuilder(builder: (context, constraints) {
      final cols = (constraints.maxWidth / 280).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.5,
        ),
        itemCount: sorted.length,
        itemBuilder: (ctx, i) => _HostTile(store: store, state: sorted[i]),
      );
    });
  }
}

class _HostTile extends StatelessWidget {
  final FleetStore store;
  final HostState state;
  const _HostTile({required this.store, required this.state});

  @override
  Widget build(BuildContext context) {
    final offline = state.isOffline();
    final hostname = state.host?.hostname ?? state.key.deviceId;
    final cpuMean = state.cpu?.meanCore ?? 0.0;
    final memPct = state.mem?.usedPct ?? 0.0;
    final worst = state.alerts?.worstSeverity;
    final borderColor = offline
        ? Colors.grey
        : worst == Severity.crit
            ? Colors.redAccent
            : worst == Severity.warn
                ? Colors.orangeAccent
                : Colors.greenAccent;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HostDetail(store: store, hostKey: state.key),
        ));
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: borderColor, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  offline ? Icons.cloud_off : Icons.computer,
                  size: 16,
                  color: offline ? Colors.grey : borderColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hostname,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (offline)
                  const Text('offline',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 6),
            _LabeledBar(label: 'CPU', value: cpuMean / 100),
            const SizedBox(height: 4),
            _LabeledBar(label: 'MEM', value: memPct / 100),
            const Spacer(),
            Text(
              state.host?.os ?? state.key.owner,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledBar extends StatelessWidget {
  final String label;
  final double value; // 0..1
  const _LabeledBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).toStringAsFixed(0);
    Color barColor = value < 0.7
        ? Colors.green
        : value < 0.85
            ? Colors.orange
            : Colors.redAccent;
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(label, style: const TextStyle(fontSize: 10)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text('$pct%', style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}
