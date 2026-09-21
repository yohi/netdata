# Security

[日本語](security.ja.md)

This is the canonical English security rationale for the repository. It
documents the implemented boundary and deferred capabilities; it is not a
replacement for host or Cloudflare security policy.

## Threat Surface

- The Netdata dashboard listens on the Parent LAN IP, allows only the Gateway
  source through the host firewall, and is not published directly to the
  Internet.
- Netdata streaming uses TCP/19998 on the Parent LAN IP with both the Child API
  key and a Gateway source-IP restriction.
- The external Web UI is reached only through the Cloudflare Tunnel after
  Cloudflare Access.
- Only the Gateway native `cloudflared` service is the Tunnel connector. The
  repository does not add a reverse proxy, public Child Web UI, or Parent DB to
  the Gateway.
- The Gateway Tunnel token and streaming API key are not tracked in Git. They
  are managed by the Gateway root-only native service and local Compose runtime
  files respectively.

## Capabilities

| Item | Decision | Reason |
| --- | --- | --- |
| `CHOWN` / `FOWNER` | Used | Limited to Netdata image initialization of named-volume runtime directories. |
| `DAC_OVERRIDE` | Used | Limited to Netdata image initialization access to named volumes. |
| `SETUID` / `SETGID` | Used | Allows the image to drop from root initialization to the `netdata` user. |
| `SYS_PTRACE` | Used | Supports the official Netdata requirements for local-listener and process monitoring. |
| `SYS_ADMIN` | Used | Supports the official Netdata requirements for cgroups and network-viewer monitoring. |
| `apparmor=unconfined` | Not used | The official sample includes it, but the initial implementation has no confirmed runtime failure that justifies the relaxation. |
| `privileged: true` | Not used | There is no requirement-based justification; capability additions are used instead. |
| Docker socket | Not used | Even a read-only mount grants strong access to the Docker API. Docker-specific metrics are outside the initial scope. |
| Rootless Docker | Adopted | Root-only RAPL sysfs access is separated into a host helper instead of changing the Docker daemon to rootful mode. |

After `cap_drop: ALL`, only capabilities needed for image initialization and
the official collector requirements are added. RAPL host-only access is not
expanded into the container; it is limited to the root helper at
`host/netdata-rapl-statsd`.

## Host Mounts

| Host path | Container path | Mode | Purpose |
| --- | --- | --- | --- |
| `/` | `/host/root` | read-only, rslave | Filesystem and mount-point discovery. |
| `/proc` | `/host/proc` | read-only | Host CPU, memory, process, and network metrics. |
| `/sys` | `/host/sys` | read-only | Cgroup, hwmon, powercap, and disk metrics. |
| `/etc/passwd`, `/etc/group` | `/host/etc/...` | read-only | User and group process attribution. |
| `/etc/os-release`, `/etc/localtime` | `/host/etc/...` | read-only | Host identity and timezone. |
| `/var/log` | `/host/var/log` | read-only | Optional log collectors. |
| `/run/dbus` | `/run/dbus` | read-only | Optional systemd unit collectors. |

Netdata writable data is limited to named volumes at `/var/lib/netdata`,
`/var/cache/netdata`, and `/var/log/netdata`. The Compose files do not mount a
writable path into the host root.

With `read_only: true`, required runtime state is placed in the Netdata
service's `tmpfs: /run`; this does not write to the host filesystem.

## Rootless RAPL Helper

`host/netdata-rapl-statsd.service` is a root service that retains only
`CAP_DAC_READ_SEARCH` in its bounding set. It reads RAPL energy counters and
sends a Watts gauge to localhost StatsD. It has no external listener, Docker
socket, or host write mount. Its output is measurement data only; it does not
handle credentials or API keys.

## Docker Monitoring Policy

The initial Compose files do not mount `/var/run/docker.sock`. Therefore,
host CPU, memory, disk, network, process, cgroup, and hardware metrics are
distinct from Docker Engine API metrics such as container names, state, and
restart counts. If Docker-specific metrics become necessary, first validate a
socket-proxy design based on the official Netdata guidance, limiting it to the
minimum required API such as `/containers` and to the intended caller. Do not
assume that a proxy is fully compatible without testing it.

## Cloudflare Access and Direct Access

Do not enable the public hostname before creating the Access application. The
Tunnel origin is `http://192.168.1.102:19999`, reachable from the Gateway, and
TLS termination is not performed by Netdata. Inbound TCP/19998 and TCP/19999
on the AI-PC must not be open to sources other than the Gateway.

Treat the Parent bind configuration, host firewall, and Cloudflare Access as
separate defense layers. When the Tunnel stops, only the external UI should
stop; Parent local collection and Child LAN streaming are designed to continue
independently. Do not mark this failure separation as verified until the live
failure test is complete.

## Secret Handling

- `*/secrets/stream-api-key`, `*/runtime/*.conf`, and `images.env` are ignored
  by Git. The Gateway native Tunnel token stays on the Gateway.
- The native Tunnel token must be managed root-only on the Gateway with
  permissions equivalent to mode `600`.
- The `stream.conf` template contains placeholders only. Runtime files with
  an API key must not be committed.
- Do not paste Tunnel tokens or API keys into GitHub Issues, the README, logs,
  or Compose output.
- If `cloudflared tunnel list` fails, do not expose token or credential values
  in the error handling or diagnostic output.
