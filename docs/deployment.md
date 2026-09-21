# Deployment

[日本語](deployment.ja.md)

This is the canonical English deployment guide. The Japanese file is a
translation; use this file when the two versions differ.

## Prerequisites

- Provide Ubuntu Server, Docker Engine, and the Docker Compose plugin on both
  target hosts.
- Do not add `cloudflared` to the AI-PC. Use the existing native
  `cloudflared` service on the Gateway.
- Confirm the Parent LAN IP, the Gateway's fixed LAN IP, and the existing
  Cloudflare Tunnel configuration before deployment.
- Verify the digest in `parent/images.env.example` and
  `child/images.env.example` for the target architecture.

## Parent

Run the following commands from the repository root on the Parent host.

```bash
cp parent/images.env.example parent/images.env
```

Generate the streaming API key once on the Parent host as a UUID without
displaying the key in the terminal.

Before generating the key, ensure that the Gateway has a clean checkout of the
repository without runtime files or secrets.

```bash
mkdir -p parent/secrets
umask 077
uuidgen > parent/secrets/stream-api-key
chmod 600 parent/secrets/stream-api-key
```

Transfer only this key file to the Gateway through an approved secure channel.
Do not copy the full checkout after the key has been created. On the Gateway,
place the received file at `child/secrets/stream-api-key` with mode `600`, then
remove any temporary transfer copy. Do not print the key during transfer.

Render the Parent configuration. Replace the example addresses with the
addresses on the target LAN.

```bash
NETDATA_HOSTNAME=ai-agent \
PARENT_LAN_IP=192.0.2.10 \
GATEWAY_LAN_IP=192.0.2.20 \
STREAM_API_KEY_FILE=parent/secrets/stream-api-key \
./scripts/render-config.sh parent
```

```bash
./scripts/validate.sh --examples
docker compose --env-file parent/images.env -f parent/compose.yaml config
docker compose --env-file parent/images.env -f parent/compose.yaml up -d netdata
docker compose --env-file parent/images.env -f parent/compose.yaml ps
```

The dashboard listens on TCP/19999 and the Child receiver listens on
TCP/19998, both on the Parent LAN IP. Add host firewall rules that allow both
ports only from the Gateway LAN IP and deny other sources, following the
existing UFW, nftables, or firewalld policy. Do not replace existing rules
blindly when the active firewall implementation is unknown.

## Child

On the clean Gateway checkout, create the Child image environment file.

```bash
cp child/images.env.example child/images.env
```

Confirm that the same API key is installed in the Gateway root-only file
`child/secrets/stream-api-key`, then render the Child configuration.

```bash
NETDATA_HOSTNAME=gateway \
PARENT_LAN_IP=192.0.2.10 \
STREAM_API_KEY_FILE=child/secrets/stream-api-key \
./scripts/render-config.sh child
```

Start the Child service.

```bash
./scripts/validate.sh --examples
docker compose --env-file child/images.env -f child/compose.yaml config
docker compose --env-file child/images.env -f child/compose.yaml up -d
docker compose --env-file child/images.env -f child/compose.yaml ps
```

The Child Web UI is disabled. Monitoring must not add a dependency on the
Gateway's routing, DNS, DHCP, or firewall services. The Child container stays
running when the Parent is unavailable and uses the reconnect behavior in
`stream.conf`.

The `--deployment` mode is a full repository check. Run it only from a
checkout that contains both local `images.env` files and both rendered runtime
configurations:

```bash
./scripts/validate.sh --deployment
```

On a host prepared for only one role, the role-specific `docker compose
config` command above is the appropriate check.

## Rootless RAPL Power Collection

With rootless Docker, root inside the container cannot read the host's
`/sys/devices/virtual/powercap/*/energy_uj`, so the standard Netdata RAPL
collector cannot be used directly. Instead of changing the Docker daemon to
rootful mode, a minimal root helper on the host reads the RAPL energy counter
and sends Watts to local Netdata StatsD.

Run the following on both the AI-PC and Gateway.

```bash
sudo install -d -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0750 host/netdata-rapl-statsd /usr/local/libexec/netdata-rapl-statsd
sudo install -o root -g root -m 0644 host/netdata-rapl-statsd.service /etc/systemd/system/netdata-rapl-statsd.service
sudo systemctl daemon-reload
sudo systemctl enable --now netdata-rapl-statsd.service
systemctl is-active netdata-rapl-statsd.service
```

The helper does not create an external listening socket. It only sends to
StatsD at `127.0.0.1:8125`. The metric name is
`netdata.rapl.package_watts`; it appears as a StatsD chart on the Parent and
streams from the Child to the Parent. On a host without an RAPL counter, the
service fails and no power chart is generated.

## Cloudflare

Inspect the existing Tunnel in the Dashboard or through the Cloudflare API.
Reuse it when possible instead of creating a new Tunnel. Create the
Cloudflare Access self-hosted application before enabling the public
hostname. Run `cloudflared` as the native Gateway service, not on the AI-PC.

```text
Hostname: netdata.y-ohi.com
Origin:   http://192.168.1.102:19999
```

The Access policy must use an explicit Permit policy for the allowed
identities. Do not create a bypass route that can reach the origin without
authentication. Change Cloudflare settings manually only after confirming the
current Tunnel and Access policy. This repository does not call the
Cloudflare API or change existing Cloudflare settings.

Keep the Gateway native `cloudflared` token and systemd unit under root-only
management on the Gateway. Do not copy them to Git or the AI-PC. Confirm the
existing service's origin and ownership, and do not start the same Tunnel in a
second service.

## Image Update and Rollback

Before an update, inspect the manifest for the target architecture and put the
selected digest in both hosts' role-specific `images.env` files.

```bash
docker buildx imagetools inspect netdata/netdata:stable
docker compose --env-file parent/images.env -f parent/compose.yaml pull
docker compose --env-file parent/images.env -f parent/compose.yaml up -d netdata
docker compose --env-file parent/images.env -f parent/compose.yaml ps
docker compose --env-file child/images.env -f child/compose.yaml pull
docker compose --env-file child/images.env -f child/compose.yaml up -d
docker compose --env-file child/images.env -f child/compose.yaml ps
```

Run the Parent commands on the Parent host and the Child commands on the
Gateway host. After each update, check `docker compose ps`, the local
dashboard, streaming, and hardware collectors. If there is a problem, restore
the previous digest in both role-specific `images.env` files and repeat the
same role-specific `pull` and `up -d` commands. Do not enable automatic
updates.
