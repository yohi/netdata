# Netdata Home Monitoring Foundation

[日本語](README.ja.md)

Reproducible Docker Compose definitions for a two-host Netdata Parent/Child
monitoring setup.

This repository is for operators who want to collect host metrics on an AI-PC
and a Gateway PC while keeping the Parent database on the AI-PC. It is a
home-lab foundation, not a turnkey production deployment.

> [!WARNING]
> The Cloudflare Access authenticated dashboard, host reboot recovery, and
> several failure tests are not verified yet. See the [verification record](docs/verification.md)
> before treating the deployment as complete.
>
> The repository has no CI or release workflow. The local validation commands
> in [Development](#development) are the current quality gate.

## Quick Start

The Parent and Child run on separate hosts. Prepare Docker Engine and the
Docker Compose plugin on both hosts, then:

1. Copy the repository to the Parent host and the Gateway host.
2. Copy `parent/images.env.example` and `child/images.env.example` to local
   `images.env` files and verify the digest for the target architecture.
3. Generate the streaming API key once on the Parent, then install the same
   key in a Gateway root-only file through an approved secure channel. Never
   print or commit the key.
4. Render the Parent and Child runtime configuration with
   `scripts/render-config.sh`.
5. Run `./scripts/validate.sh --examples` and `docker compose config` for both
   Compose projects before starting services.
6. Follow the [deployment guide](docs/deployment.md) for startup order,
   firewall rules, and the existing Gateway `cloudflared` service.

Expected result: both Compose configurations validate without tracking a
generated secret or runtime file, and the deployment guide provides the next
steps to bring up healthy Parent and Child services.

## Features

- Parent-only metrics database with Child streaming over the home LAN.
- Child Web UI disabled; the Gateway does not become a second dashboard.
- Dashboard and streaming endpoints bound to the Parent LAN address and
  restricted to the Gateway source address.
- Digest-pinned Netdata images and generated runtime configuration that keeps
  API keys out of Git.
- Rootless Docker baseline without `privileged`, Docker socket mounts, or an
  AppArmor override.
- Host-only RAPL helper that sends CPU package power to local Netdata StatsD.
- Static validation for shell syntax, templates, image pins, Compose files,
  secret boundaries, and security invariants.

## How It Works

```text
Cloudflare Access
        |
Gateway native cloudflared -> http://<PARENT_LAN_IP>:19999
        |
AI-PC: netdata-parent
  <PARENT_LAN_IP>:19999 = dashboard
  <PARENT_LAN_IP>:19998 = streaming receiver
        ^
        | TCP/19998, Gateway source only
Gateway PC: netdata-child
  Web UI disabled
```

Only the Parent owns the central metrics database. The Child collects local
metrics and sends them to the Parent. The existing native `cloudflared`
service on the Gateway provides the Tunnel origin; this repository does not
install or run `cloudflared` in either Compose project.

## Usage

- Open the dashboard through the existing Cloudflare Access application after
  the Gateway Tunnel origin has been configured.
- Use the Parent LAN address for local checks. Do not expose TCP/19999 or
  TCP/19998 to unrestricted LAN or Internet clients.
- Use `docs/deployment.md` for image updates, rollback, RAPL installation, and
  service recreation.

## Configuration

- `parent/images.env.example` and `child/images.env.example` are safe input
  templates. Local `images.env` files are ignored and must remain untracked.
- `scripts/render-config.sh` requires `NETDATA_HOSTNAME`,
  `PARENT_LAN_IP`, `STREAM_API_KEY_FILE`, and, for the Parent,
  `GATEWAY_LAN_IP`.
- Generated `runtime/*.conf` files and `*/secrets/stream-api-key` files are
  local runtime state. Their permissions and Git tracking status are checked
  by the validation scripts.

## Documentation

| I want to... | Start here |
| --- | --- |
| Deploy Parent and Child | [Deployment](docs/deployment.md) / [日本語](docs/deployment.ja.md) |
| Review security boundaries | [Security](docs/security.md) / [日本語](docs/security.ja.md) |
| Check evidence and Issue #1 coverage | [Verification](docs/verification.md) / [日本語](docs/verification.ja.md) |
| Review the Gateway Tunnel decision | [Architecture decision](docs/superpowers/specs/2026-09-21-gateway-native-cloudflared-design.md) |

The English files are canonical. Japanese files are translations and may lag
temporarily; when contents differ, use the English file as the authority.

## Development

Run deterministic checks from the repository root:

```bash
bash tests/render-config.sh
bash tests/preflight.sh
bash tests/validate.sh
./scripts/validate.sh --examples
git diff --check
```

For a checkout that contains both roles' local `images.env` and rendered
runtime files, use `./scripts/validate.sh --deployment`. On a host that is
being prepared for only one role, run that role's `docker compose config`
command instead. `shellcheck` is used automatically when it is installed.

The main implementation paths are:

```text
parent/                 Parent Compose and templates
child/                  Child Compose and templates
scripts/                Rendering, preflight, and validation
host/                   Root RAPL helper and systemd unit
tests/                  Shell regression tests
```

## License

[MIT](LICENSE)
