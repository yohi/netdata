# Gateway Native cloudflared Design

## Decision

Do not install or run cloudflared on the AI-PC. Keep the existing native
cloudflared service on the Gateway and make it the Cloudflare Tunnel origin
connector for the Parent dashboard.

The Parent dashboard listens on `192.168.1.102:19999` for the Gateway only.
The AI-PC firewall must allow TCP/19999 from `192.168.1.103` and deny other
LAN sources. Parent streaming remains on `192.168.1.102:19998` and is also
restricted to the Gateway.

The Gateway Child continues to have its Web UI disabled. It sends metrics to
the Parent and does not provide the Cloudflare origin.

## Alternatives

1. Run native cloudflared on the Gateway and bind Parent dashboard to the
   Parent LAN address. This is the selected option because it avoids an
   AI-PC cloudflared installation while keeping the Child isolated.
2. Keep Parent dashboard loopback-only and maintain an SSH or TCP reverse
   forward from Gateway to Parent. This avoids LAN dashboard binding but adds
   another long-running service and failure mode.
3. Enable the Child Web UI and tunnel Gateway localhost. This is rejected
   because it exposes the non-Parent Child surface and bypasses the Parent
   metrics database.

## Data Flow

```text
Cloudflare Access
        |
Gateway native cloudflared
        | HTTP over LAN, 192.168.1.103 -> 192.168.1.102:19999
AI-PC Parent dashboard
        |
Gateway Child -- TCP/19998 --> AI-PC Parent streaming receiver
```

Cloudflare public origin changes from `http://127.0.0.1:19999` to
`http://192.168.1.102:19999` in the Gateway Tunnel configuration. The route
must be protected by the existing Access application and Permit policy.

## Repository Changes

- Remove the Parent Compose cloudflared service and its image/token inputs.
- Change the Parent dashboard bind template to use the Parent LAN address.
- Keep Parent streaming and Child streaming API-key restrictions unchanged.
- Document native cloudflared ownership on the Gateway and the required
  firewall rules.
- Add static checks that no cloudflared service exists in either Compose file.

## Operational Constraints

- Do not stop or replace the existing Gateway native cloudflared service
  without confirming its Tunnel and systemd ownership.
- Do not expose TCP/19999 to the whole LAN or Internet.
- Do not place the Tunnel token or streaming API key in Git, logs, or command
  output.
- The current host firewall implementation must be inspected before adding a
  rule; existing rules must not be replaced blindly.

## Verification

- Parent binds `192.168.1.102:19999` and `192.168.1.102:19998`.
- Gateway reaches both ports, while an unrelated LAN source cannot reach
  `19999`.
- Gateway Child remains `healthy` with Web UI unavailable locally.
- Parent receives Gateway `system.cpu` data through streaming.
- Cloudflare public hostname returns the Access challenge and, after a user
  authenticates, displays the Parent dashboard.
- AI-PC has no cloudflared process or Compose service introduced by this
  repository.
