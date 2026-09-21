# Verification and Issue #1 Coverage

[日本語](verification.ja.md)

This is the canonical English evidence record. A requirement is marked
`PASS` only when an implementation file or an executed command provides
evidence. Container startup, Gateway communication, Cloudflare Access,
hardware charts, recreation, and reboot must remain `NOT VERIFIED` or
`BLOCKED` until they are observed directly.

## Evidence Rules

`PASS` is reserved for evidence from an implementation file or an executed
command recorded in this document. The existence of a capability path alone
does not prove that Netdata generated a chart.

## Gate 0 Evidence

The test source was an AI-PC-equivalent Ubuntu 26.04.1 LTS host with kernel
7.0.0-31-generic and x86_64 architecture. Docker 29.8.1 and Compose 5.5.1
were confirmed. `/sys/devices/virtual/powercap` contained `intel-rapl` and
`intel-rapl-mmio`; `/sys/class/hwmon` contained multiple entries including
coretemp and NVMe; and a WD_BLACK SN7100 1TB NVMe device was present. The
Gateway was reachable through SSH at `192.168.1.103:2022` and reported Ubuntu
26.04 LTS, Docker 29.6.2, and Compose 5.3.1.

No Cloudflare API token or origin certificate was obtained. The Child was
deployed and started on the Gateway, whose existing native `cloudflared`
service was active. The Parent Compose `cloudflared` service was removed and
the AI-PC native service was inactive. An AI-PC firewall rule allowing only
the Gateway source was applied with iptables-nft and enabled through
`netfilter-persistent`. Netdata runtime files and Gateway configuration were
transferred over SSH without including secrets in the Git archive.

## Static Validation

```bash
bash tests/render-config.sh
bash tests/preflight.sh
bash tests/validate.sh
bash tests/rapl-statsd.sh
./scripts/validate.sh --examples
bash scripts/preflight.sh
docker compose --env-file parent/images.env.example -f parent/compose.yaml config
docker compose --env-file child/images.env.example -f child/compose.yaml config
./scripts/validate.sh --deployment
docker compose --env-file parent/images.env -f parent/compose.yaml config
docker compose --env-file child/images.env -f child/compose.yaml config
git diff --check
```

The renderer, preflight, validator, Compose config, ShellCheck, Bash syntax,
diff check, and `--deployment` checks passed. `tests/rapl-statsd.sh` also
passed.

## Parent Runtime Evidence

The digest-pinned Netdata Parent was started on the AI-PC, and streaming from
the Gateway Child was observed.

- Parent container: `running`, `healthy`, restart count `0`.
- `http://192.168.1.102:19999/api/v1/info`: HTTP `200`.
- `192.168.1.102:19999`: Parent LAN dashboard bind; Gateway-only firewall
  enforcement was confirmed.
- `192.168.1.102:19998`: HTTP `451`; the response was the streaming-only
  endpoint, not dashboard HTML.
- `system.cpu`: 30 data points from the API. NVMe I/O (`disk.nvme0n1`),
  network, and memory chart names were confirmed.
- The container exposed `/host/sys/devices/virtual/powercap`,
  `/host/sys/class/hwmon`, and `/host/sys/class/nvme`.
- Rootless Docker prevented the standard RAPL collector from reading host
  `energy_uj`, and the debugfs plugin stopped with permission denied. After
  installing the host helper on both hosts, Watts chart and data were
  confirmed.
- After `--force-recreate`, the container remained `running/healthy`, the API
  returned HTTP `200`, and `system.cpu` data remained available. A sample
  before recreation overlapped with a query 180 seconds afterward, confirming
  that the Parent named volume retained the database.
- Startup logs showed read-only journal update failures and debugfs disabled.
  The required dashboard, CPU, NVMe, and API worked; journal and debugfs are
  recorded as limitations without additional permissions.
- The Gateway native `cloudflared` service was active, but the Cloudflare-side
  Tunnel origin change was not performed. Authenticated Access dashboard
  display and policy contents were not confirmed.

## Gateway Runtime Evidence

- Gateway Child container: `running`, `healthy`, restart count `0`.
- Gateway `netdata-rapl-statsd.service` was `active`; StatsD listened only on
  `127.0.0.1:8125`.
- The Child image healthcheck conflicted with the disabled Web UI, so
  `child/compose.yaml` uses `/usr/sbin/netdatacli ping`. The updated
  healthcheck and CLI ping succeeded.
- Gateway `127.0.0.1:19999` returned connection refused, confirming that the
  Child Web UI was not exposed.
- The Gateway connected to Parent `192.168.1.102:19998` over TCP.
- The Gateway connected to the Parent Dashboard API at
  `192.168.1.102:19999`.
- Gateway requests to Parent `:19998` returned HTTP `451`, as expected for the
  streaming-only bind.
- Parent `/api/v1/charts` reported `hosts_count=2` and the `gateway` host.
- Parent `/api/v1/data?chart=system.cpu&host=gateway` returned the latest 60
  rows. Gateway streaming was observed.
- From the AI-PC's other LAN address, `192.168.1.202`, Parent `:19999`
  timed out after the Gateway-only firewall rule was applied.
- The AI-PC and Gateway `netdata-rapl-statsd.service` instances were
  `active`. Parent created `statsd_netdata.rapl.package_watts_gauge`, and 60
  recent Watts data rows were retrieved.

## Requirement Coverage

| Requirement | Status | Evidence / reason |
| --- | --- | --- |
| REQ-ARCH-001 | PASS | `parent/compose.yaml` and `child/compose.yaml` define only Netdata; `cloudflared` is managed by the Gateway native service. |
| REQ-ARCH-002 | PASS | Compose does not install host packages; `docs/deployment.md` records reuse of the existing Gateway native `cloudflared`. |
| REQ-ARCH-003 | PASS | Compose, templates, renderer, and docs are tracked; secrets and runtime files are ignored. |
| REQ-ARCH-004 | PASS | `images.env.example` pins the stable manifest by digest. |
| REQ-PARENT-001 | PASS | Parent Netdata service is defined in `parent/compose.yaml`. |
| REQ-PARENT-002 | PASS | Parent local collection and stream receiver configuration; `system.cpu` chart and API data were observed. |
| REQ-PARENT-003 | PASS | Parent named volumes at `/var/lib/netdata` and related paths; data remained after force recreation. |
| REQ-PARENT-004 | PASS | `parent/config/netdata.conf.tmpl` binds Parent LAN ports 19999 and 19998; Gateway source allow and other-LAN timeout were observed. |
| REQ-PARENT-005 | PASS | `parent/config/stream.conf.tmpl` configures UUID, API key, and source-IP restriction; Gateway `system.cpu` data arrived at the Parent. |
| REQ-CHILD-001 | PASS | `child/compose.yaml` defines the Child service. |
| REQ-CHILD-002 | PASS | Child template uses `[web] mode = none`; Gateway port 19999 returned connection refused. |
| REQ-CHILD-003 | PASS | Child destination is `PARENT_LAN_IP:19998`; Parent returned Gateway data. |
| REQ-CHILD-004 | PASS | Child adds no routing, DNS, DHCP, or firewall dependency; failure test remains unverified. |
| REQ-CHILD-005 | PASS | Child Tier 0 is two days and reconnect settings are present; replication was not measured. |
| REQ-CONT-001 | PASS | Compose host mounts are read-only. |
| REQ-CONT-002 | PASS | `pid: host` and `network_mode: host` are configured. |
| REQ-CONT-003 | PASS | Five initialization capabilities and two collector capabilities are limited; AppArmor override, socket, and privileged mode are excluded. |
| REQ-CONT-004 | PASS | Rootless Docker is used; root-only RAPL reads are isolated in the host helper. |
| REQ-DOCKER-001 | NOT VERIFIED | Docker socket is absent, so Engine-specific container metrics are not provided; host/cgroup chart coverage was not measured. |
| REQ-DOCKER-002 | PASS | A direct socket is not used; a proxy is documented as a future candidate. |
| REQ-CF-001 | PASS | Fixed hostname is documented in `docs/deployment.md`; the Gateway native Tunnel route was not changed. |
| REQ-CF-002 | NOT VERIFIED | Origin `http://192.168.1.102:19999` is documented; Cloudflare-side origin change and authenticated origin were not confirmed. |
| REQ-CF-003 | PASS | Neither Compose file defines `cloudflared`; the Gateway native service is used. |
| REQ-CF-004 | NOT VERIFIED | Existing Gateway native service and token management were inspected, but the Netdata origin route was not confirmed. |
| REQ-CF-005 | PASS | Compose has no published ports and uses the outbound Tunnel model; an Internet scan was not performed. |
| REQ-CF-006 | NOT VERIFIED | Access-first and no-bypass procedures are documented; the live Tunnel origin and policy were not confirmed. |
| REQ-POWER-001 | PASS | Rootless-compatible helpers were active on both hosts; Parent Watts data was observed in `statsd_netdata.rapl.package_watts_gauge`. |
| REQ-POWER-002 | PASS | Documentation distinguishes CPU package power from total wall power. |
| REQ-POWER-003 | PASS | Smart Plug, UPS, and PDU measurements are outside the initial scope. |
| REQ-DATA-001 | PASS | Parent named volumes and Child short-lived database configuration are present. |
| REQ-DATA-002 | PASS | Parent Tier 0 target is 30 days; actual retention chart behavior was not measured. |
| REQ-DATA-003 | PASS | Parent DB directories are separated from Compose lifecycle; data API survived force recreation. |
| REQ-HA-001 | NOT VERIFIED | Gateway independence is a design property, but Parent-stop testing was not performed. |
| REQ-HA-002 | NOT VERIFIED | Gateway native `cloudflared` is an independent service, but stop testing was not performed. |
| REQ-HA-003 | PASS | Services use `restart: unless-stopped`; host reboot was not tested. |
| REQ-PERF-001 | NOT VERIFIED | Gateway device load was not measured. |
| REQ-PERF-002 | PASS | No unnecessary public functionality was added to the Child. |
| REQ-PERF-003 | PASS | The template defines `update every 1` and records adjustment guidance. |
| REQ-CLOUD-001 | PASS | The design uses only self-hosted Parent/Child components and does not require Netdata Cloud. |

## Acceptance Coverage

| Acceptance | Status | Evidence / reason |
| --- | --- | --- |
| AC-001 | NOT VERIFIED | The public URL redirects with HTTP `302` to Access, but authenticated dashboard display was not confirmed. |
| AC-002 | NOT VERIFIED | Access policy identity conditions were not confirmed in the live environment. |
| AC-003 | PASS | Parent dashboard binds to `192.168.1.102:19999`, is reachable from the Gateway, and times out from the other LAN address `192.168.1.202`. |
| AC-004 | NOT VERIFIED | No Internet port probe was performed; Compose has no published ports. |
| AC-005 | PASS | Gateway connected to Parent TCP/19998 and Parent returned 60 rows of `host=gateway` `system.cpu` data. |
| AC-006 | PASS | Child Compose has no published ports, `[web] mode = none`, and Gateway port 19999 returned connection refused. |
| AC-007 | PASS | Parent API host list contains `gateway` and returned its chart data. |
| AC-008 | NOT VERIFIED | AI-PC hardware charts were not confirmed through the Netdata runtime. |
| AC-009 | PASS | Both RAPL helpers were active and Parent returned Watts data. This is CPU package/RAPL power, not total wall power. |
| AC-010 | PASS | Parent health, API, and data remained after force recreation; named volumes persisted. |
| AC-011 | NOT VERIFIED | Parent-stop testing for Gateway routing, DNS, and DHCP continuity was not performed. |
| AC-012 | NOT VERIFIED | Gateway hardware-specific charts were not checked in this run. |
| AC-013 | NOT VERIFIED | Host reboot testing was not performed. |
| AC-014 | NOT VERIFIED | The AI-PC native service was inactive and the Gateway native service was active; AI-PC package removal and authenticated Cloudflare route were not confirmed. |

## Failure Tests

Completed:

- Metric persistence after Parent Compose force recreation.
- Child recreation and continued streaming after the healthcheck change.

Not completed:

- Parent stop/restart with Gateway routing, DNS, and DHCP continuity.
- Gateway native `cloudflared` stop with only the external UI becoming
  unavailable.
- Gateway and AI-PC host reboot with automatic recovery.
