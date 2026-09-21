# Gateway Native cloudflared Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the repository-managed AI-PC cloudflared service and route the Cloudflare Access origin through the existing native Gateway cloudflared service without exposing the Parent dashboard to unrestricted LAN clients.

**Architecture:** Parent Netdata will bind its dashboard to `192.168.1.102:19999` and streaming to `192.168.1.102:19998`. Gateway native cloudflared will use the Parent dashboard as its origin; the AI-PC firewall must allow both ports only from `192.168.1.103`. Gateway Child Web UI remains disabled and continues streaming metrics to Parent.

**Tech Stack:** Docker Compose, Netdata, native systemd-managed cloudflared on Gateway, shell tests, ShellCheck, UFW/nftables-compatible firewall runbook.

## Global Constraints

- Do not add or run cloudflared in the AI-PC Compose stack.
- Do not expose TCP/19999 to the whole LAN or Internet.
- Keep Child Web UI disabled and keep Parent streaming API-key/source-IP restrictions.
- Do not commit or print tunnel tokens, streaming API keys, generated runtime configs, or ignored `images.env` files.
- Do not stop, uninstall, or replace pre-existing native cloudflared services without explicit host-owner authorization.
- Do not replace existing firewall rules blindly; inspect the active firewall implementation first.

---

### Task 1: Lock the new network contract with tests

**Files:**
- Modify: `tests/render-config.sh`
- Modify: `tests/validate.sh`

**Interfaces:**
- Consumes: `scripts/render-config.sh`, `parent/compose.yaml`, `child/compose.yaml`.
- Produces: Regression checks for Parent LAN dashboard binding and absence of repository-managed cloudflared.

- [ ] **Step 1: Write failing assertions**

Add checks that rendered Parent config contains `192.168.1.102:19999=dashboard` when `PARENT_LAN_IP=192.168.1.102`, and that neither Compose file contains a `cloudflared` service. Keep the existing Child `netdatacli ping` healthcheck assertion.

- [ ] **Step 2: Run the focused tests and verify the expected failure**

Run:

```bash
bash tests/render-config.sh
bash tests/validate.sh
```

Expected: the new dashboard-bind assertion fails against the current loopback-only template, and the Parent cloudflared assertion fails against the current Parent Compose file.

- [ ] **Step 3: Keep the assertions secret-safe**

Ensure the tests inspect only fixed configuration strings and never print `parent/images.env`, `cloudflared-token`, or `stream-api-key` contents.

### Task 2: Remove repository-managed AI-PC cloudflared

**Files:**
- Modify: `parent/compose.yaml`
- Modify: `parent/images.env.example`
- Modify: `scripts/validate.sh`

**Interfaces:**
- Consumes: Parent Netdata service and existing token-safe validation.
- Produces: Parent Compose containing only the Netdata service; no `CLOUDFLARED_IMAGE`, `CLOUDFLARED_TOKEN_FILE`, Compose secret, or cloudflared container.

- [ ] **Step 1: Remove the cloudflared service and Compose secret**

Delete the `cloudflared` service, its `secrets` declaration, and its `tunnel-token` reference from `parent/compose.yaml`. Keep the Parent Netdata service, named volumes, host mounts, read-only root, tmpfs, and capabilities unchanged.

- [ ] **Step 2: Remove cloudflared image/token inputs**

Delete the `CLOUDFLARED_IMAGE` and `CLOUDFLARED_TOKEN_FILE` lines from `parent/images.env.example`. Do not touch ignored runtime `parent/images.env` outside the repository.

- [ ] **Step 3: Update static validation**

Remove Parent-only token/image validation from `scripts/validate.sh`. Add a security invariant that fails if either `parent/compose.yaml` or `child/compose.yaml` contains `cloudflared`.

- [ ] **Step 4: Run the focused tests and Compose checks**

Run:

```bash
bash tests/render-config.sh
bash tests/validate.sh
docker compose --env-file parent/images.env.example -f parent/compose.yaml config
docker compose --env-file child/images.env.example -f child/compose.yaml config
```

Expected: all commands pass and the rendered Compose output contains no cloudflared service.

### Task 3: Change Parent dashboard binding to LAN-restricted origin

**Files:**
- Modify: `parent/config/netdata.conf.tmpl`
- Modify: `tests/render-config.sh`

**Interfaces:**
- Consumes: `PARENT_LAN_IP` supplied to `scripts/render-config.sh`.
- Produces: Parent runtime binding `__PARENT_LAN_IP__:19999=dashboard __PARENT_LAN_IP__:19998=streaming`.

- [ ] **Step 1: Update the template**

Replace the loopback dashboard endpoint with the Parent LAN endpoint while retaining the streaming endpoint and labels:

```ini
[web]
    default port = 19999
    bind to = __PARENT_LAN_IP__:19999=dashboard __PARENT_LAN_IP__:19998=streaming
```

- [ ] **Step 2: Update the renderer assertion**

Change the test expectation from `127.0.0.1:19999=dashboard` to `192.0.2.10:19999=dashboard` for the test fixture.

- [ ] **Step 3: Run render and static checks**

Run:

```bash
bash tests/render-config.sh
bash tests/validate.sh
```

Expected: rendered Parent config contains both LAN endpoints and no unresolved placeholders.

### Task 4: Document Gateway-native Tunnel ownership and firewall rules

**Files:**
- Modify: `README.md`
- Modify: `docs/deployment.md`
- Modify: `docs/security.md`
- Modify: `docs/verification.md`
- Modify: `docs/superpowers/specs/2026-09-21-gateway-native-cloudflared-design.md`

**Interfaces:**
- Consumes: New Parent bind and Compose contract.
- Produces: A runbook that identifies Gateway native cloudflared as the only Netdata Tunnel connector and records the LAN-only origin requirement.

- [ ] **Step 1: Update architecture and deployment flow**

Document the origin as `http://192.168.1.102:19999`, the Gateway native cloudflared owner, and the required Access policy. Remove instructions that provision a Parent Compose tunnel token.

- [ ] **Step 2: Add firewall examples without assuming an implementation**

Document the required policy as source `192.168.1.103` to destination `192.168.1.102` TCP ports `19998` and `19999`, with deny-by-default for other LAN sources. Include inspection commands for the existing firewall and explicitly state that rules must be adapted, not blindly replaced.

- [ ] **Step 3: Record verification boundaries**

Mark Cloudflare origin reconfiguration, authenticated Access dashboard display, and firewall enforcement as `NOT VERIFIED` until the Gateway owner performs them. Keep Child streaming and Web UI checks as runtime evidence.

### Task 5: Apply and verify the runtime configuration

**Files:**
- Runtime only: ignored `parent/runtime/*.conf`, `child/runtime/*.conf`, `parent/images.env`, `child/images.env`.
- Remote runtime only: Gateway deployment under the existing user-owned project directory.

**Interfaces:**
- Consumes: Parent/Gateway LAN addresses and the existing streaming API key.
- Produces: Parent dashboard reachable only through the intended LAN path, Child healthy, and Gateway streaming preserved.

- [ ] **Step 1: Render the Parent runtime configuration**

Run locally without printing the key:

```bash
NETDATA_HOSTNAME=ai-agent \
PARENT_LAN_IP=192.168.1.102 \
GATEWAY_LAN_IP=192.168.1.103 \
STREAM_API_KEY_FILE=parent/secrets/stream-api-key \
./scripts/render-config.sh parent
```

- [ ] **Step 2: Recreate only the Parent Netdata service**

Run `docker compose --env-file parent/images.env -f parent/compose.yaml up -d netdata`. Do not start a repository cloudflared service.

- [ ] **Step 3: Regenerate and deploy Child runtime files**

Render the Child config with `PARENT_LAN_IP=192.168.1.102`, transfer only tracked files plus the ignored Child `images.env`, runtime files, and API key over SSH, then recreate the Child service.

- [ ] **Step 4: Verify the runtime path**

Run:

```bash
curl --fail http://127.0.0.1:19999/api/v1/info
curl --fail 'http://127.0.0.1:19999/api/v1/data?chart=system.cpu&host=gateway&after=-60&before=0&format=json'
ssh -p 2022 192.168.1.103 'curl --fail --max-time 5 http://192.168.1.102:19999/api/v1/info'
```

Do not claim firewall isolation until an unrelated LAN source is tested or the active firewall rules are inspected.

### Task 6: Final verification and integration

**Files:**
- Modify: `docs/verification.md` only if fresh evidence changes a status.

- [ ] **Step 1: Run all repository checks**

```bash
bash tests/render-config.sh
bash tests/preflight.sh
bash tests/validate.sh
./scripts/validate.sh --deployment
bash -n scripts/*.sh tests/*.sh
shellcheck scripts/*.sh tests/*.sh
docker compose --env-file parent/images.env -f parent/compose.yaml config
docker compose --env-file child/images.env -f child/compose.yaml config
git diff --check
```

- [ ] **Step 2: Confirm the security boundary**

Confirm no tracked secret-bearing files, no `cloudflared` service in Compose, Child Web UI unavailable, and Parent dashboard not reachable from an unauthorized LAN source.

- [ ] **Step 3: Commit and push only intended files**

Use separate commits for repository behavior and documentation if the diff remains logically separable. Never stage `.codegraph/`, `.justice/`, `.omo/`, ignored runtime files, or ignored secrets.

## Self-Review

- The selected design covers the no-AI-PC-cloudflared constraint, Parent LAN origin, Gateway native connector, Child isolation, and firewall verification boundary.
- No credentials or absolute machine-specific paths are added to tracked files.
- Runtime Cloudflare origin and firewall changes remain explicitly manual where current credentials or host firewall ownership are unavailable.
- The plan does not authorize stopping or uninstalling pre-existing native cloudflared services.
