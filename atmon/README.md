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

See [`atmon/packages/atmon_models`](packages/atmon_models),
[`atmon/packages/atmon_agent`](packages/atmon_agent) and
[`atmon/packages/atmon_dashboard`](packages/atmon_dashboard).

## Layout

```
atmon/
├─ pubspec.yaml                         # workspace + SDK path overrides
└─ packages/
   ├─ atmon_models/                     # shared models, factories, diff
   ├─ atmon_agent/                      # Dart CLI agent
   └─ atmon_dashboard/                  # Flutter desktop dashboard
```

## Quick start

Prereqs: Dart 3.6+, Flutter 3.29+, an atSign with `.atKeys` in `~/.atsign/keys/`
for the agent and one for the dashboard.

```bash
# 1. From the parent directory you must already have at_client_sdk cloned at
#    ../at_client_sdk on the gkc-enhance-api branch (this is what the workspace
#    overrides point at).

# 2. Resolve deps once for the workspace.
cd atmon
dart pub get

# 3. Run an agent that reports to your dashboard atSign.
dart run packages/atmon_agent/bin/atmon_agent.dart \
  -a @agent_alpha -d host01 -m @ops1

# 4. Launch the dashboard (macOS or Linux).
cd packages/atmon_dashboard
flutter run -d macos
```

See the per-package READMEs for full details.
