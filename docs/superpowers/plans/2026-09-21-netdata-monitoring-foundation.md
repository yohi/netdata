# Netdata Monitoring Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Issue #1のParent/Child Netdata監視基盤を、秘密情報を含めずDocker Composeから再生成できる状態にする。

**Architecture:** ParentとChildを別Compose projectとして管理し、Netdataのruntime configはtemplateから生成する。ParentだけがDBとcloudflaredを持ち、ChildはWeb UIを無効化してLAN上のParentへstreamする。Docker socketとCloudflare実設定は初期repo構成から分離する。

**Tech Stack:** Docker Compose、Netdata Agent、cloudflared、POSIX/Bash shell、ShellCheck、Markdown。

## Global Constraints

- Netdata/cloudflaredはnative packageとして追加しない。
- `latest`を恒久運用に使わず、Compose imageはdigestで指定する。
- Tunnel token、streaming API key、Cloudflare credential、generated `stream.conf`をGitへ保存しない。
- Parent dashboardは`127.0.0.1:19999`、streamingはParent LAN IPのTCP/19998だけにする。
- Childにcloudflared、reverse proxy、公開Web UI、Parent DBを配置しない。
- Docker socket、`privileged: true`、`apparmor=unconfined`は初期実装に含めない。
- `SYS_ADMIN`/`SYS_PTRACE`はNetdata collector要件とsecurity.mdで対応付ける。
- Gateway/Cloudflare実機に接続できない項目はPASSにせず、`BLOCKED`/`NOT VERIFIED`/`UNAVAILABLE`へ分類する。

---

### Task 1: Repository contract and secret boundaries

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `parent/images.env.example`
- Create: `child/images.env.example`
- Create: `parent/secrets/cloudflared-token.example`
- Create: `parent/runtime/.gitkeep`
- Create: `child/runtime/.gitkeep`

**Interfaces:**
- Produces the directory and environment contract consumed by all later Compose and validation tasks.
- `images.env.example` exposes `NETDATA_IMAGE`, `CLOUDFLARED_IMAGE`, and `CLOUDFLARED_TOKEN_FILE` without secret values.

- [ ] **Step 1: Write the failing repository contract check**

Create a temporary shell assertion in `scripts/validate.sh` only after the directories exist; before implementation, verify the expected files are absent with:

```bash
test -e parent/compose.yaml
```

Expected: FAIL because the repository has no implementation yet.

- [ ] **Step 2: Add ignore rules and placeholders**

Ignore `parent/secrets/*`, `child/secrets/*`, `parent/runtime/*`, and `child/runtime/*` while re-including `.gitkeep` and `.example` files. Document that `images.env` and generated configs are local runtime files.

- [ ] **Step 3: Add README quick start**

Document the Parent/Child roles, deployment paths, the required `images.env` and secret provisioning, and links to deployment, security, and verification documents. State explicitly that the current checkout is an AI-PC preflight environment and that Gateway/Cloudflare runtime checks remain unverified.

- [ ] **Step 4: Run the repository contract checks**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intended new files plus pre-existing untracked agent directories are present.

- [ ] **Step 5: Commit**

```bash
git add .gitignore README.md parent/images.env.example child/images.env.example parent/secrets/cloudflared-token.example parent/runtime/.gitkeep child/runtime/.gitkeep
git commit -m "feat: add monitoring repository contract"
```

### Task 2: Runtime config rendering with tests

**Files:**
- Create: `parent/config/netdata.conf.tmpl`
- Create: `parent/config/stream.conf.tmpl`
- Create: `child/config/netdata.conf.tmpl`
- Create: `child/config/stream.conf.tmpl`
- Create: `scripts/render-config.sh`
- Create: `tests/render-config.sh`

**Interfaces:**
- `scripts/render-config.sh parent` reads `NETDATA_HOSTNAME`, `PARENT_LAN_IP`, `GATEWAY_LAN_IP`, `STREAM_API_KEY_FILE`, and writes `parent/runtime/netdata.conf` plus `parent/runtime/stream.conf`.
- `scripts/render-config.sh child` reads `NETDATA_HOSTNAME`, `PARENT_LAN_IP`, `STREAM_API_KEY_FILE`, and writes the equivalent Child files.
- The script rejects missing variables, nonexistent key files, non-regular key files, keys containing whitespace/newlines, and non-IP endpoint values.

- [ ] **Step 1: Write failing renderer tests**

`tests/render-config.sh` must create a temporary key file containing a known UUID, run the renderer for both roles, and assert with `grep -F` that the output contains the expected hostname, bind endpoints, API key, `allow from`, and Child destination. It must also assert that a missing key file exits nonzero and creates no runtime secret config.

Run:

```bash
bash tests/render-config.sh
```

Expected: FAIL because `scripts/render-config.sh` does not exist.

- [ ] **Step 2: Implement the minimal renderer**

Use a repository-root calculation based on `${BASH_SOURCE[0]}`. Render with quoted heredocs and shell parameter expansion rather than `envsubst`; write temporary files with mode `600`, then atomically rename them. Keep the API key only in the generated stream config and never print it.

Use these current Netdata directives:

```ini
[web]
    default port = 19999
    bind to = 127.0.0.1:19999=dashboard PARENT_LAN_IP:19998=streaming
```

```ini
[API_KEY]
    type = api
    enabled = yes
    allow from = GATEWAY_LAN_IP
    db = dbengine
```

```ini
[stream]
    enabled = yes
    destination = PARENT_LAN_IP:19998
    api key = API_KEY
    send charts matching = *
```

The Child template must use `[web] mode = none` and a two-day Tier 0 database.

- [ ] **Step 3: Run tests and ShellCheck**

Run:

```bash
bash tests/render-config.sh
bash -n scripts/render-config.sh tests/render-config.sh
shellcheck scripts/render-config.sh tests/render-config.sh
```

Expected: all pass without displaying the test API key in normal output.

- [ ] **Step 4: Commit**

```bash
git add parent/config child/config scripts/render-config.sh tests/render-config.sh
git commit -m "feat: render secret-safe Netdata runtime config"
```

### Task 3: Parent and Child Compose definitions

**Files:**
- Create: `parent/compose.yaml`
- Create: `child/compose.yaml`

**Interfaces:**
- Parent Compose consumes rendered `parent/runtime/netdata.conf` and `stream.conf` and the token file selected by `CLOUDFLARED_TOKEN_FILE`.
- Child Compose consumes rendered `child/runtime/netdata.conf` and `stream.conf`.
- Both Compose files expose only the host namespaces required by Netdata and persist Netdata writable directories in named volumes.

- [ ] **Step 1: Add Compose definitions with the least privilege baseline**

Use `pid: host`, `network_mode: host`, `restart: unless-stopped`, `read_only: true`, writable named volumes for `/var/lib/netdata`, `/var/cache/netdata`, and `/var/log/netdata`, plus read-only mounts for `/`, `/proc`, `/sys`, `/etc/passwd`, `/etc/group`, `/etc/os-release`, `/etc/localtime`, `/var/log`, and `/run/dbus`. Add `SYS_PTRACE` and `SYS_ADMIN` only to Netdata with comments in security documentation; omit Docker socket and AppArmor override.

The Parent cloudflared service must use `network_mode: host`, `read_only: true`, no capabilities, a Compose secret at `/run/secrets/tunnel-token`, and:

```yaml
command:
  - tunnel
  - --no-autoupdate
  - run
  - --token-file
  - /run/secrets/tunnel-token
```

Do not publish ports because host networking and Netdata bind rules provide the required exposure.

- [ ] **Step 2: Run Compose config against safe example inputs**

Create local untracked `parent/images.env` and `child/images.env` from the examples, point the Parent token path at `parent/secrets/cloudflared-token.example`, and run:

```bash
docker compose --env-file parent/images.env -f parent/compose.yaml config
docker compose --env-file child/images.env -f child/compose.yaml config
```

Expected: valid rendered YAML; no container starts and no external port is published.

- [ ] **Step 3: Assert security invariants**

Run checks that fail if either Compose file contains `privileged`, `/var/run/docker.sock`, `apparmor=unconfined`, a `ports:` section, or a `cloudflared` service in Child.

- [ ] **Step 4: Commit**

```bash
git add parent/compose.yaml child/compose.yaml
git commit -m "feat: add least-privilege Parent and Child Compose"
```

### Task 4: Preflight and static validation

**Files:**
- Create: `scripts/preflight.sh`
- Create: `scripts/validate.sh`
- Create: `tests/validate.sh`

**Interfaces:**
- `scripts/preflight.sh [--json]` reports Docker/Compose, OS/kernel, architecture, local interfaces, RAPL, hwmon, NVMe, native Netdata/cloudflared package presence, and whether Gateway/Cloudflare credentials are available. It never prints token values.
- `scripts/validate.sh` runs syntax, template, secret, Compose, and diff checks without starting containers.
- `tests/validate.sh` exercises the static validator with a valid temporary fixture and a missing-required-variable fixture.

- [ ] **Step 1: Write failing static validation tests**

Test that validation rejects missing `images.env`, rejects unresolved template placeholders in generated runtime files, rejects secret files with group/world permissions, and rejects tracked secret filenames. Test that valid example files pass.

Run:

```bash
bash tests/validate.sh
```

Expected: FAIL before the validator exists.

- [ ] **Step 2: Implement preflight**

Use command existence checks and guarded reads. Report `/sys/devices/virtual/powercap`, `/sys/class/hwmon`, and `/sys/class/nvme` as capability evidence only. Report native packages as pre-existing host state; do not install or remove them. Report `cloudflared tunnel list` authentication failure without exposing credentials.

- [ ] **Step 3: Implement static validator**

Run `bash -n` for scripts, `shellcheck` when available, `docker compose config` for both projects, template completeness checks, secret mode checks, `git ls-files` secret checks, and `git diff --check`. Accept a `VALIDATE_ROOT` fixture directory for tests and use temporary generated configs so real secrets are not needed.

- [ ] **Step 4: Run all static checks**

```bash
bash tests/validate.sh
bash scripts/validate.sh
bash scripts/preflight.sh
```

Expected: static checks pass; runtime checks are not attempted.

- [ ] **Step 5: Commit**

```bash
git add scripts/preflight.sh scripts/validate.sh tests/validate.sh
git commit -m "test: add monitoring preflight and static validation"
```

### Task 5: Deployment, security, and verification documentation

**Files:**
- Create: `docs/deployment.md`
- Create: `docs/security.md`
- Create: `docs/verification.md`
- Modify: `README.md`

**Interfaces:**
- Documentation consumes the Compose and renderer interfaces from Tasks 2-4.
- `docs/verification.md` is the source of truth for Issue #1 REQ/AC status and must distinguish implementation evidence from runtime evidence.

- [ ] **Step 1: Document deployment**

Describe host directory provisioning, ownership/mode, digest update and rollback, rendering configs, Parent/Child startup order, Gateway LAN firewall rule procedure without guessing the firewall implementation, and Cloudflare existing Tunnel reuse. Include Access application creation before public hostname exposure, origin `http://127.0.0.1:19999`, and token file provisioning.

- [ ] **Step 2: Document security decisions**

List threat surface, host mounts, capabilities, omitted Docker socket, omitted AppArmor override, no direct inbound ports, API key source-IP restriction, Child isolation, Access requirement, and the exact reason for each exception or deferred capability.

- [ ] **Step 3: Create verification and coverage matrix**

Cover REQ-ARCH, REQ-PARENT, REQ-CHILD, REQ-CONT, REQ-DOCKER, REQ-CF, REQ-POWER, REQ-DATA, REQ-HA, REQ-PERF, REQ-CLOUD and AC-001 through AC-014. Mark static implementation evidence as `PASS` only where a file or deterministic check proves it; mark live network, hardware chart, Gateway, Cloudflare, recreate, reboot, and streaming observations as `NOT VERIFIED` or `BLOCKED`.

- [ ] **Step 4: Run Markdown and whitespace checks**

```bash
git diff --check
```

If `markdownlint-cli2` is already available, run it; do not install packages solely for this check.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/deployment.md docs/security.md docs/verification.md
git commit -m "docs: document monitoring deployment and acceptance"
```

### Task 6: Final verification and evidence report

**Files:**
- Modify: `docs/verification.md`
- Modify: `README.md` only if validation reveals a reproducibility gap

- [ ] **Step 1: Run the complete deterministic gate**

```bash
git status --short --branch
bash tests/render-config.sh
bash tests/validate.sh
bash scripts/validate.sh
docker compose --env-file parent/images.env -f parent/compose.yaml config
docker compose --env-file child/images.env -f child/compose.yaml config
```

- [ ] **Step 2: Verify secret safety**

Confirm `git ls-files` contains no `stream.conf` runtime file, tunnel token, API key file, `.env` runtime file, or digest-bearing private config. Search the diff for `eyJ`, UUID test values, and token-like values without printing secret files.

- [ ] **Step 3: Record environment-dependent status**

Record the AI-PC preflight evidence, existing native cloudflared package as a pre-existing host modification, no Gateway access, no Cloudflare management access, no Netdata runtime container, and all unperformed failure tests. Do not claim runtime PASS.

- [ ] **Step 4: Inspect the final diff and commit**

```bash
git push --set-upstream origin feature/netdata-monitoring-foundation
```

Push only the feature branch. Do not close Issue #1 and do not merge any pull request.
