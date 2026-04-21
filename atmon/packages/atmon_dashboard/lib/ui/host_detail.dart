import 'package:atmon_models/atmon_models.dart';
import 'package:flutter/material.dart';

import '../services/fleet_store.dart';

/// btop-style host detail view. Shown when tapping a tile in the fleet grid.
///
/// Contains four panes, each lazily rendered (null data shows a placeholder):
///  1. CPU — per-core usage bars + load averages
///  2. Memory — used/swap bar
///  3. Disk — table of mounted filesystems
///  4. Network — per-interface TX/RX stats
///  5. Processes — top-N by CPU
///  6. Alerts — banner list
class HostDetail extends StatelessWidget {
  final FleetStore store;
  final HostKey hostKey;
  const HostDetail({super.key, required this.store, required this.hostKey});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final state = store.hostBy(hostKey);
        if (state == null) {
          return Scaffold(
            appBar: AppBar(title: Text(hostKey.deviceId)),
            body: const Center(child: Text('Host removed.')),
          );
        }
        final h = state.host;
        final hostname = h?.hostname ?? state.key.deviceId;
        return Scaffold(
          appBar: AppBar(
            title: Text('$hostname  ·  ${state.key.owner}'),
            actions: [
              if (state.isOffline())
                const Chip(
                  label: Text('OFFLINE'),
                  backgroundColor: Colors.grey,
                ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hostInfoBar(h),
                  const SizedBox(height: 12),
                  _alertBanner(state.alerts),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _cpuPane(state.cpu)),
                      const SizedBox(width: 12),
                      Expanded(child: _memPane(state.mem)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _diskPane(state.disk)),
                      const SizedBox(width: 12),
                      Expanded(child: _netPane(state.net)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _procPane(state.procs),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hostInfoBar(HostInfo? h) {
    if (h == null) return const SizedBox.shrink();
    return Wrap(spacing: 16, runSpacing: 4, children: [
      _chip('OS', '${h.os} ${h.kernel}'),
      _chip('CPU', '${h.cpuCount}× ${h.cpuModel}'),
      _chip('RAM', _formatKb(h.totalMemKb)),
      _chip('Uptime', _formatDuration(Duration(seconds: h.uptimeSec))),
      _chip('Agent', h.agentVersion),
    ]);
  }

  Widget _chip(String k, String v) => Chip(
        label: RichText(
          text: TextSpan(children: [
            TextSpan(
                text: '$k ',
                style: const TextStyle(
                    color: Colors.grey, fontFamily: 'monospace', fontSize: 11)),
            TextSpan(
                text: v,
                style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 11)),
          ]),
        ),
      );

  Widget _alertBanner(AlertList? a) {
    if (a == null || a.active.isEmpty) return const SizedBox.shrink();
    final worst = a.worstSeverity;
    final bg =
        worst == Severity.crit ? Colors.red.shade900 : Colors.orange.shade900;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final alert in a.active)
            Text(
              '${alert.severity.name.toUpperCase()}  ${alert.message}',
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _cpuPane(CpuStats? cpu) {
    return _pane('CPU', [
      if (cpu == null)
        const Text('No data', style: TextStyle(color: Colors.grey))
      else ...[
        _labeledBar('mean', cpu.meanCore / 100),
        if (cpu.loadAvg.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'load avg  ${cpu.loadAvg.map((v) => v.toStringAsFixed(2)).join('  ')}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
        if (cpu.tempC != null) ...[
          const SizedBox(height: 4),
          Text(
            'temp  ${cpu.tempC!.toStringAsFixed(1)} °C',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
        const SizedBox(height: 6),
        ...cpu.coreUsage.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: _labeledBar('C${e.key}', e.value / 100),
              ),
            ),
      ],
    ]);
  }

  Widget _memPane(MemStats? mem) {
    return _pane('Memory', [
      if (mem == null)
        const Text('No data', style: TextStyle(color: Colors.grey))
      else ...[
        _labeledBar('RAM  ${_formatKb(mem.usedKb)} / ${_formatKb(mem.totalKb)}',
            mem.usedPct / 100),
        if (mem.swapTotalKb > 0) ...[
          const SizedBox(height: 4),
          _labeledBar(
              'Swap ${_formatKb(mem.swapUsedKb)} / ${_formatKb(mem.swapTotalKb)}',
              mem.swapUsedPct / 100),
        ],
      ],
    ]);
  }

  Widget _diskPane(DiskStats? disk) {
    return _pane('Disk', [
      if (disk == null)
        const Text('No data', style: TextStyle(color: Colors.grey))
      else
        Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(1),
          },
          children: [
            const TableRow(
              children: [
                _TableHeader('Mount'),
                _TableHeader('Used / Total'),
                _TableHeader('Pct'),
              ],
            ),
            for (final fs in disk.filesystems)
              TableRow(children: [
                _TableCell(fs.mount),
                _TableCell('${_formatKb(fs.usedKb)} / ${_formatKb(fs.sizeKb)}'),
                _TableCell('${fs.usedPct.toStringAsFixed(0)}%'),
              ]),
          ],
        ),
    ]);
  }

  Widget _netPane(NetStats? net) {
    return _pane('Network', [
      if (net == null)
        const Text('No data', style: TextStyle(color: Colors.grey))
      else
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
          },
          children: [
            const TableRow(
              children: [
                _TableHeader('Iface'),
                _TableHeader('↓ RX'),
                _TableHeader('↑ TX'),
              ],
            ),
            for (final iface in net.ifaces)
              TableRow(children: [
                _TableCell(iface.name),
                _TableCell('${iface.rxKbps.toStringAsFixed(0)} KB/s'),
                _TableCell('${iface.txKbps.toStringAsFixed(0)} KB/s'),
              ]),
          ],
        ),
    ]);
  }

  Widget _procPane(ProcSnapshot? procs) {
    return _pane('Processes', [
      if (procs == null)
        const Text('No data', style: TextStyle(color: Colors.grey))
      else
        Table(
          columnWidths: const {
            0: FixedColumnWidth(50),
            1: FlexColumnWidth(2),
            2: FixedColumnWidth(55),
            3: FixedColumnWidth(55),
            4: FlexColumnWidth(3),
          },
          children: [
            const TableRow(
              children: [
                _TableHeader('PID'),
                _TableHeader('User'),
                _TableHeader('CPU%'),
                _TableHeader('MEM'),
                _TableHeader('Name'),
              ],
            ),
            for (final p in procs.topByCpu)
              TableRow(children: [
                _TableCell('${p.pid}'),
                _TableCell(p.user),
                _TableCell('${p.cpuPct.toStringAsFixed(1)}%'),
                _TableCell('${p.memMb} MB'),
                _TableCell(p.name, overflow: TextOverflow.ellipsis),
              ]),
          ],
        ),
    ]);
  }

  Widget _pane(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade700),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.grey.shade900,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(title,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
        ],
      ),
    );
  }

  Widget _labeledBar(String label, double value) {
    final pct = (value * 100).toStringAsFixed(0);
    final barColor = value < 0.7
        ? Colors.green
        : value < 0.85
            ? Colors.orange
            : Colors.redAccent;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          flex: 3,
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
        SizedBox(
          width: 30,
          child: Text('$pct%',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
      );
}

class _TableCell extends StatelessWidget {
  final String text;
  final TextOverflow overflow;
  const _TableCell(this.text, {this.overflow = TextOverflow.clip});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            overflow: overflow),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatKb(int kb) {
  if (kb < 1024) return '$kb KB';
  if (kb < 1024 * 1024) return '${(kb / 1024).toStringAsFixed(0)} MB';
  return '${(kb / 1024 / 1024).toStringAsFixed(1)} GB';
}

String _formatDuration(Duration d) {
  final days = d.inDays;
  final hours = d.inHours % 24;
  final mins = d.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${mins}m';
  return '${mins}m';
}
