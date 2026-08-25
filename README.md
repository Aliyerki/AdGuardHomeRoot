# AdGuardHome for Root (Aliyerki)

English | [Español](README_es.md)

![arm-64](https://img.shields.io/badge/arm--64-supported-ef476f?logo=linux&logoColor=white)
![arm-v7](https://img.shields.io/badge/arm--v7-supported-ffa500?logo=linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-9b5de5?logo=opensourceinitiative&logoColor=white)

Based on [twoone-3/AdGuardHomeForRoot](https://github.com/twoone-3/AdGuardHomeForRoot),
with the DNS blackout that module caused on every boot fixed, and a build that
follows AdGuardHome releases on its own.

All credit for the module itself goes to [twoone3](https://github.com/twoone-3);
this project only adds the patches described below. This page covers **what is
different here**; for the module's own documentation see the original README in
[English](README_en.md) or [简体中文](README_zh.md), and the
[docs](docs/index.md).

## About the module

AdGuardHome for Root runs [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome)
as a root module (Magisk, KernelSU or APatch), giving the phone a local DNS server
that blocks ads, malware and trackers — no VPN slot used, so it coexists with
proxy apps. Filtering uses the
[AWAvenue Ads Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule) list, and
the control panel lives at <http://127.0.0.1:3000>.

---

## Why this exists

After every reboot the phone had **no internet in the browser or Google Play**,
while other apps worked fine. Toggling airplane mode fixed it until the next
reboot.

Reading the logs turned up three separate causes.

### 1. Boot race (the main one)

`tool.sh` checked `ps | grep AdGuardHome` and then immediately redirected port 53
with iptables. That check only proves the **process spawned** — not that the DNS
server is listening. The server binds much later, after it loads the filter lists
and probes the upstreams.

On a Redmi Note 11 the window was **40 seconds**:

```
21:31:45.804  starting adguard home
21:31:45      Applied iptables rules successfully   <- history.log
21:32:25.988  dnsproxy: listening to udp addr=127.0.0.1:5591
```

For those 40 seconds **every DNS query on the device was redirected to a port
nothing was listening on**. Android runs its connectivity check inside that
window, it fails, and the network gets flagged as having no internet. The browser
and Play Store honour that flag and refuse to use the network, while apps that
ignore it keep working — which is why it looked like an app problem rather than a
DNS one. Airplane mode forced a re-validation once the server was finally up.

### 2. Upstreams unreachable from the Americas

The stock config pointed at Chinese DoH servers with Chinese bootstrap servers.
From a Mexican network every query burned a **20 second timeout**, including the
domains Android needs to validate the connection:

```
exchange failed ... question=";www.gstatic.com. IN AAAA"  timeout exceeded
```

### 3. Dropping IPv6 DNS on an IPv6-native carrier

The module silently dropped IPv6 DNS queries. With no answer at all, the client
waits out its full timeout before retrying over IPv4. This is the mechanism
described in upstream
[issue #71](https://github.com/twoone-3/AdGuardHomeForRoot/issues/71).

---

## What differs from upstream

| File | Change |
|---|---|
| `src/scripts/tool.sh` | Waits for the DNS listener to actually bind before applying iptables, by reading `/proc/net/udp{,6}`. If it never binds within `startup_timeout`, the rules are **skipped** instead of leaving the device with no DNS. |
| `src/scripts/iptables.sh` | `REJECT` instead of `DROP` for IPv6 DNS, so the client falls back to IPv4 immediately. Falls back to `DROP` where the kernel lacks `REJECT`. |
| `src/settings.conf` | New `startup_timeout` key (120s). Timezone set to `America/Mexico_City`. |
| `src/bin/AdGuardHome.yaml` | Cloudflare and Google DoH upstreams using **literal IPs**, so nothing needs resolving via bootstrap at startup. |
| `brand.sh` | Stamps this project's name, author and update URL onto `module.prop` **at build time**. `src/module.prop` and `version.json` stay byte-identical to upstream in git, so upstream's monthly version bumps to those files never conflict when changes are picked up. |
| `pack.sh` | Builds on Linux (upstream ships only the PowerShell `pack.ps1`). |
| `.github/workflows/pack.yml` | Checks daily whether AdGuardTeam published a new AdGuardHome and, if so, builds and releases on its own. |
| `.github/workflows/upstream-check.yml` | Opens an issue here when twoone-3 gets ahead — nothing watches that repo otherwise. |
| `sync-upstream.sh` | Pulls those changes in without losing these patches. |

Note that only the first two rows are bug fixes. The timezone and the DNS
upstreams are personal configuration and are deliberately **not** part of the
patches sent upstream.

### Measured result, cold boot

| | Before | After |
|---|---|---|
| DNS blackout | **40.2 s** | **0 s** |
| DNS server startup | 40 s | 1.26 s |
| Timeouts in the log | dozens | 0 |
| Network validated without airplane mode | no | **yes** |

Ad blocking is unaffected: `doubleclick.net` still resolves to a null address and
normal domains resolve fine.

---

## Installing

1. Download the zip for your architecture from
   [Releases](https://github.com/Aliyerki/AdGuardHomeRoot/releases/latest)
   (`arm64` for most current phones).
2. Make sure **Private DNS is off**: Settings → Network & internet → Private DNS.
   If it is on, it bypasses the module.
3. Install from your root manager (Magisk, KernelSU or APatch) and reboot.
4. Control panel at <http://127.0.0.1:3000>, default credentials `root`/`root`.

When **upgrading**, the installer asks whether to keep your existing config
(volume up = yes, volume down = no, 30s of no input = yes). Keeping it preserves
your filters and statistics, but it also **keeps your old `AdGuardHome.yaml` and
`settings.conf`** — any change to upstreams or timezone has to be applied to the
files on the device by hand.

## Building

```bash
./pack.sh arm64     # or armv7
```

Downloads the official AdGuardHome binary, stages it into `src/` and produces the
flashable zip. Uses `zip` when available and `python3` otherwise.

## Releasing

Two ways, both ending in a published release plus an updated `update.json`,
which is the file installed modules poll:

- **Automatic.** A daily job compares the latest AdGuardHome release against the
  one the last build used. When AdGuardTeam ships a new version, it builds both
  architectures and releases without being asked.
- **On demand.** Push an 8-digit date tag:

  ```bash
  git tag 20260901 && git push origin 20260901
  ```

Every build downloads AdGuardHome's `releases/latest`, so no zip ever carries a
stale binary.

## Picking up changes from twoone-3

Nothing does this on a schedule; a weekly job only opens an issue here when
there is something to pick up. Doing it:

```bash
./sync-upstream.sh          # review the changes
./sync-upstream.sh --push   # publish them
```

Rebases the local patches onto `upstream/main`, shows what changed upstream and
what is being replayed, and stops if there is a conflict. Conflicts are expected
whenever upstream touches `tool.sh`, `iptables.sh`, `settings.conf`, `pack.yml` or
the README — but no longer on `module.prop` or `version.json`, which is where
every upstream release used to collide.

---

## Upstream status

The two generic fixes were submitted as separate pull requests, without the
parts specific to this project (custom DNS, timezone, `updateJson`):

- [#77](https://github.com/twoone-3/AdGuardHomeForRoot/pull/77) — the boot race
- [#78](https://github.com/twoone-3/AdGuardHomeForRoot/pull/78) — the IPv6 `REJECT`

If they are merged, `sync-upstream.sh` will absorb them during the rebase and
those local patches become unnecessary.

## Credits

Original module by [twoone3](https://github.com/twoone-3/AdGuardHomeForRoot),
MIT licensed, same as this project.

- [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome)
- [AWAvenue Ads Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule)
