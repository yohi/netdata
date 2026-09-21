# Verification and Issue #1 Coverage

## Evidence Rules

`PASS`は、この文書に記載した実装ファイルまたは実行済みコマンドの証拠がある場合だけに使う。container起動、Gateway通信、Cloudflare Access、hardware chart、recreate、rebootを実測していない項目は`NOT VERIFIED`または`BLOCKED`とする。能力pathが存在するだけではNetdata chartのPASSにしない。

## Gate 0 Evidence

実行元はAI-PC相当のUbuntu 26.04.1 LTS、kernel 7.0.0-31-generic、x86_64です。Docker 29.8.1、Compose 5.5.1を確認しました。`/sys/devices/virtual/powercap`に`intel-rapl`と`intel-rapl-mmio`、`/sys/class/hwmon`にcoretemp/NVMeを含む複数entry、WD_BLACK SN7100 1TB NVMeを確認しました。

Gateway SSH情報はなく、Cloudflare API token/origin certificateは取得できず、既存Tunnel一覧はCLI認証エラーでした。実装中にDocker container、Firewall、Cloudflare設定、Gatewayへ変更していません。ホストには作業開始前からnative `cloudflared 2026.9.1`が存在しました。

## Static Validation

```bash
bash tests/render-config.sh
bash tests/preflight.sh
bash tests/validate.sh
bash scripts/validate.sh --examples
bash scripts/preflight.sh
docker compose --env-file parent/images.env.example -f parent/compose.yaml config
docker compose --env-file child/images.env.example -f child/compose.yaml config
git diff --check
```

実装時点で上記のrenderer、preflight、validator、Compose config、ShellCheck、bash syntax、diff checkは通過しています。`--deployment`は実際のsecretとruntime `images.env`を配置した対象ホストで実行します。

## Requirement Coverage

| Requirement | Status | Evidence / reason |
| --- | --- | --- |
| REQ-ARCH-001 | PASS | `parent/compose.yaml`, `child/compose.yaml`。Netdata/cloudflaredをComposeで定義。 |
| REQ-ARCH-002 | PASS | Composeにhost package installationを含めず、docs/deployment.md。 |
| REQ-ARCH-003 | PASS | Compose、templates、renderer、docsをGit管理。secret/runtimeはignore。 |
| REQ-ARCH-004 | PASS | `images.env.example`はstable manifest digest固定。 |
| REQ-PARENT-001 | PASS | `parent/compose.yaml`のNetdata service。 |
| REQ-PARENT-002 | PASS | Parent local collectionとstream receiver設定。runtime観測は未検証。 |
| REQ-PARENT-003 | PASS | Parent named volumes `/var/lib/netdata`等。履歴保持の再生成実測は未検証。 |
| REQ-PARENT-004 | PASS | `parent/config/netdata.conf.tmpl`の現行`bind to`構文。bind runtimeは未検証。 |
| REQ-PARENT-005 | PASS | `parent/config/stream.conf.tmpl`のUUID/API/source-IP制限。stream接続は未検証。 |
| REQ-CHILD-001 | PASS | `child/compose.yaml`。 |
| REQ-CHILD-002 | PASS | Child templateの`[web] mode = none`。runtime到達不可は未検証。 |
| REQ-CHILD-003 | PASS | Child templateのLAN `PARENT_LAN_IP:19998` destination。 |
| REQ-CHILD-004 | PASS | Childにrouting/DNS/DHCP/firewall依存を追加していない。故障試験は未検証。 |
| REQ-CHILD-005 | PASS | Child Tier 0 2日と再接続設定。replication実測は未検証。 |
| REQ-CONT-001 | PASS | Composeのhost mountはread-only。 |
| REQ-CONT-002 | PASS | `pid: host`と`network_mode: host`。 |
| REQ-CONT-003 | PASS | capを2つに限定し、AppArmor override/socket/privilegedを除外。 |
| REQ-CONT-004 | PASS | Rootlessを採用せずdocs/security.mdに理由を記載。 |
| REQ-DOCKER-001 | NOT VERIFIED | Docker socketなしのためEngine固有container metricsは未提供。host/cgroup範囲のchartも未実測。 |
| REQ-DOCKER-002 | PASS | direct socketを使わずproxyを将来候補として文書化。 |
| REQ-CF-001 | PASS | `docs/deployment.md`に固定hostnameを記載。実環境routeは未変更。 |
| REQ-CF-002 | PASS | origin `http://127.0.0.1:19999`を文書化。外部疎通はBLOCKED。 |
| REQ-CF-003 | PASS | Parent Composeだけにcloudflaredを定義。 |
| REQ-CF-004 | PASS | cloudflaredはhost networkとtoken-file。 |
| REQ-CF-005 | PASS | Composeにportsがなく、Tunnel outbound方式。Internet scanは未検証。 |
| REQ-CF-006 | PASS | Access先行手順とbypass禁止を文書化。Access設定自体はBLOCKED。 |
| REQ-POWER-001 | NOT VERIFIED | AI-PCにpowercap pathはあるがNetdata Watts chart未実測。Gatewayは未接続。 |
| REQ-POWER-002 | PASS | CPU Package Powerを全体消費電力と扱わない説明。 |
| REQ-POWER-003 | PASS | Smart Plug/UPS/PDUを初期scope外と記載。 |
| REQ-DATA-001 | PASS | Parent named volumesとChild short DB。 |
| REQ-DATA-002 | PASS | Parent Tier 0 30d target。実Retention chartは未検証。 |
| REQ-DATA-003 | PASS | Parent DB directoriesをCompose lifecycleから分離。recreateは未検証。 |
| REQ-HA-001 | NOT VERIFIED | 設計上Gateway機能へ依存しないがParent停止試験は未実施。 |
| REQ-HA-002 | NOT VERIFIED | cloudflared独立serviceだが停止試験は未実施。 |
| REQ-HA-003 | PASS | servicesに`restart: unless-stopped`。host rebootは未検証。 |
| REQ-PERF-001 | NOT VERIFIED | Gateway実機負荷を測定していない。 |
| REQ-PERF-002 | PASS | Childへ不要な公開機能を追加していない。 |
| REQ-PERF-003 | PASS | update every 1をtemplateに定義し、調整手順を残した。 |
| REQ-CLOUD-001 | PASS | Self-hosted Parent/Childのみで構成し、Netdata Cloudを要求しない。 |

## Acceptance Coverage

| Acceptance | Status | Evidence / reason |
| --- | --- | --- |
| AC-001 | BLOCKED | Cloudflare管理権限/既存routeを取得できず、公開URLを変更していない。 |
| AC-002 | BLOCKED | Access policyを実環境で確認できない。 |
| AC-003 | NOT VERIFIED | Parent containerを起動してLAN-IP:19999をprobeしていない。 |
| AC-004 | NOT VERIFIED | Internetからのport probe未実施。Composeはportsなし。 |
| AC-005 | BLOCKED | Gateway実機とstreaming接続未実施。 |
| AC-006 | PASS | Child Composeにport公開なし、`[web] mode = none`。実container確認は未検証。 |
| AC-007 | BLOCKED | Gateway実機未接続。 |
| AC-008 | NOT VERIFIED | AI-PC hardware chartをNetdata runtimeで未確認。 |
| AC-009 | NOT VERIFIED | AI-PC RAPL pathは存在するがchart未確認、Gatewayは未接続。 |
| AC-010 | NOT VERIFIED | Parent containerのdelete/recreate試験未実施。 |
| AC-011 | NOT VERIFIED | Parent停止時のGateway routing/DNS/DHCP試験未実施。 |
| AC-012 | BLOCKED | Gateway実機未接続。 |
| AC-013 | NOT VERIFIED | Host reboot試験未実施。 |
| AC-014 | BLOCKED | native cloudflared 2026.9.1が作業前から存在し、今回削除や変更はしていない。Netdata native packageは未確認。 |

## Failure Tests

以下は本作業では安全性の理由から実行していない。

- Parent stop/restartとGateway routing/DNS/DHCP継続。
- cloudflared stopと外部UIだけの停止。
- Parent Compose recreate後のmetrics persistence。
- Gateway/AI-PC host reboot後の自動復旧。
