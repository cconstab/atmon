# atmon — atSign btop-style fleet monitor

A demo of the new `AtCollection<T>` API on the
[`gkc-enhance-api`](https://github.com/atsign-foundation/at_client_sdk/tree/gkc-enhance-api)
branch of `at_client_sdk`. A Dart CLI **agent** samples Linux/macOS host metrics
and publishes them as typed `CItem`s through per-category collections so only
the categories whose values **actually changed** are pushed over the wire.
A Flutter desktop **dashboard** subscribes via `AtCollection.events` and paints
a btop-like view of one host or a fleet of hosts.

```
agent (per-host Dart CLI)        Atsign Platform           dashboard (Flutter)
  AtCollection<CpuStats>     ──put──► notify ─────► AtCollection<CpuStats>.events
  AtCollection<MemStats>                              AtCollection<MemStats>.events
  AtCollection<DiskStats>                             AtCollection<DiskStats>.events
  AtCollection<NetStats>                              AtCollection<NetStats>.events
  AtCollection<ProcSnapshot>                          AtCollection<ProcSnapshot>.events
  AtCollection<HostInfo>                              AtCollection<HostInfo>.events
  AtCollection<AlertList>                             AtCollection<AlertList>.events
```

## Prerequisites

- Dart ≥ 3.6 / Flutter ≥ 3.41 (stable)
- Two atSigns — one for the agent machine(s), one for the dashboard viewer
- `.atKeys` files for both atSigns in `~/.atsign/keys/`

## Step 1 — Clone the SDK (required before anything else)

atmon depends on the `gkc-enhance-api` branch of `at_client_sdk` for the
`AtCollection<T>` API which is not yet published to pub.dev.
The SDK must be cloned as a **sibling directory** alongside `atmon/`:

```bash
# Run this from the same parent directory that contains atmon/
git clone --branch gkc-enhance-api --single-branch \
  https://github.com/atsign-foundation/at_client_sdk.git
```

Your directory layout must look exactly like this:

```
<parent>/
├─ at_client_sdk/       ← cloned above (gkc-enhance-api branch)
└─ atmon/               ← this repo
   ├─ pubspec.yaml
   └─ packages/
      ├─ atmon_models/
      ├─ atmon_agent/
      └─ atmon_dashboard/
```

The root `pubspec.yaml` uses `dependency_overrides` with relative paths
(`../at_client_sdk/packages/…`) — if `at_client_sdk` is not in the right
place `dart pub get` will fail with "path does not exist" errors.

## Step 2 — Get dependencies

```bash
cd atmon
dart pub get
```

## Step 3 — Build the agent binary

```bash
dart compile exe packages/atmon_agent/bin/atmon_agent.dart -o /usr/local/bin/atmon_agent
```

Or run directly without compiling:

```bash
dart run packages/atmon_agent/bin/atmon_agent.dart --help
```

### Agent flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--atsign` | `-a` | — | atSign the agent authenticates as |
| `--key-file` | `-k` | `~/.atsign/keys/<atsign>_key.atKeys` | Path to `.atKeys` file |
| `--device-id` | `-D` | — | Name for this machine. Repeat up to 25× |
| `--monitor` | `-m` | — | Dashboard atSign to share data with. Repeat for fan-out |
| `--sample-sec` | `-S` | `2` | Seconds between samples |
| `--verbose` | `-v` | false | More logging |

Example:

```bash
atmon_agent -a @myserver -k ~/.atsign/keys/@myserver_key.atKeys \
            -D web-01 -m @ops -S 5
```

## Step 4 — Run the dashboard

```bash
cd packages/atmon_dashboard
flutter run -d macos
```

In the connect screen enter the **dashboard atSign** (e.g. `@ops`) and
optionally browse to its `.atKeys` file (defaults to `~/.atsign/keys/`).
Any agent already sharing data with that atSign will appear immediately;
new agents appear as soon as their first tick arrives.

Tap a tile to open the full detail view — CPU cores, memory, disk, network,
processes, and alerts all update live.

## Alert thresholds (defaults)

| Metric | WARN | CRIT |
|--------|------|------|
| CPU mean | 80 % | 85 % |
| Load avg (1 min) | cpu_count × 0.8 | cpu_count |
| Memory used | 85 % | 95 % |
| Swap used | 50 % | 80 % |
| Disk per mount | 90 % | 95 % |

Thresholds live in `MonitorConfig.defaults()` in
`packages/atmon_models/lib/src/models/config.dart`.

## Layout

```
atmon/
├─ pubspec.yaml                         # workspace + SDK path overrides
└─ packages/
   ├─ atmon_models/                     # shared models, factories, diff helpers
   ├─ atmon_agent/                      # Dart CLI agent (Linux + macOS samplers)
   └─ atmon_dashboard/                  # Flutter macOS desktop dashboard
```

## Architecture notes

Data flows strictly **agent → atServer → dashboard** — the dashboard never
connects directly to the agent machine. All communication is end-to-end
encrypted via the atPlatform.

Each metric category (`cpu`, `mem`, `disk`, `net`, `procs`, `host`, `alerts`)
is a separate `AtCollection<T>` with namespace `<category>.atmon.monitoring`.
The agent writes one `CItem` per device; the dashboard subscribes to all seven
collections and merges updates by `(owner atSign, device-id)`.
