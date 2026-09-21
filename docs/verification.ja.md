# Verification and Issue #1 Coverage

[English](verification.md)

この文書は`verification.md`の日本語訳です。実装fileまたは実行済みcommandのevidenceがある場合だけ`PASS`とし、内容が異なる場合は英語版を正本として扱います。

## Evidence Rules

`PASS`は、この文書に記載した実装fileまたは実行済みcommandのevidenceがある場合だけに使います。container起動、Gateway通信、Cloudflare Access、hardware chart、recreate、rebootは、直接観測するまで`NOT VERIFIED`または`BLOCKED`のままにします。capability pathが存在するだけではNetdataがchartを生成した証拠になりません。

## Gate 0 Evidence

実行元はAI-PC相当のUbuntu 26.04.1 LTS、kernel 7.0.0-31-generic、x86_64です。Docker 29.8.1、Compose 5.5.1を確認しました。`/sys/devices/virtual/powercap`に`intel-rapl`と`intel-rapl-mmio`、`/sys/class/hwmon`にcoretemp/NVMeを含む複数entry、WD_BLACK SN7100 1TB NVMe deviceを確認しました。Gatewayは`192.168.1.103:2022`でSSH接続でき、Ubuntu 26.04 LTS、Docker 29.6.2、Compose 5.3.1を確認しました。

Cloudflare API token/origin certificateは取得していません。GatewayへChildを配置・起動し、Gatewayの既存native `cloudflared` serviceはactiveです。Parent Composeからcloudflared serviceを除去し、AI-PC側native serviceはinactiveになりました。AI-PC firewallはGateway sourceだけを許可するiptables-nft ruleを適用し、`netfilter-persistent`でenabled/activeを確認しました。Netdata runtimeとGateway設定はGit archiveへsecretを含めず、SSH経由で配置しました。

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

renderer、preflight、validator、Compose config、ShellCheck、Bash syntax、diff check、`--deployment`が通過しています。`tests/rapl-statsd.sh`も通過しています。

## Parent Runtime Evidence

AI-PC上でdigest固定のNetdata Parentを起動し、Gateway Childからのstreamingを実測しました。

- Parent container: `running`、`healthy`、restart count `0`。
- `http://192.168.1.102:19999/api/v1/info`: HTTP `200`。
- `192.168.1.102:19999`: Parent LAN dashboard bind。Gateway-only firewall enforcementを確認。
- `192.168.1.102:19998`: HTTP `451`。Dashboard HTMLではなくstreaming-only endpointの応答。
- `system.cpu`: APIから30 data pointを取得。NVMe I/O（`disk.nvme0n1`）、network、memory chart名を確認。
- containerから`/host/sys/devices/virtual/powercap`、`/host/sys/class/hwmon`、`/host/sys/class/nvme`を確認。
- Rootless Dockerでは標準RAPL collectorがhost `energy_uj`を読めず、debugfs pluginがpermission deniedで停止しました。両hostへのroot helper install後、Watts chartとdataを確認しました。
- `--force-recreate`後も`running/healthy`、API HTTP `200`、`system.cpu` dataを確認しました。recreate前のsampleと180秒後のqueryに重複があり、Parent named volumeのDB保持を確認しました。
- 起動logにはread-only journal更新失敗とdebugfs無効化がありました。必須dashboard、CPU、NVMe、APIは動作しましたが、journalとdebugfsは追加権限なしの制約として記録します。
- Gateway native `cloudflared` serviceはactiveですが、Cloudflare側のTunnel origin変更は未実施です。Access認証後のdashboard表示とpolicy内容は未確認です。

## Gateway Runtime Evidence

- Gateway Child container: `running`、`healthy`、restart count `0`。
- Gatewayの`netdata-rapl-statsd.service`は`active`で、StatsDは`127.0.0.1:8125`だけでlistenしました。
- Child image healthcheckはWeb UI無効化と衝突したため、`child/compose.yaml`で`/usr/sbin/netdatacli ping`へ変更しました。変更後のhealthcheckとCLI pingは成功しました。
- Gatewayの`127.0.0.1:19999`はconnection refusedでした。Child Web UIが公開されていないことを確認しました。
- GatewayからParent `192.168.1.102:19998`へのTCP接続に成功しました。
- GatewayからParent Dashboard API `192.168.1.102:19999`への接続に成功しました。
- GatewayからParent `:19998`はHTTP `451`を返しました。streaming-only bindの想定内です。
- Parent `/api/v1/charts`で`hosts_count=2`、`gateway` hostを確認しました。
- Parent `/api/v1/data?chart=system.cpu&host=gateway`で直近60行を取得しました。Gateway streamingを実測済みです。
- AI-PCの別LAN address `192.168.1.202`からParent `:19999`はtimeoutになりました。Gateway-only firewall rule適用後の挙動を確認しました。
- AI-PCとGatewayの`netdata-rapl-statsd.service`は`active`でした。Parentに`statsd_netdata.rapl.package_watts_gauge`が生成され、直近60行のWatts dataを取得しました。

## Requirement Coverage

| Requirement | Status | Evidence / reason |
| --- | --- | --- |
| REQ-ARCH-001 | PASS | `parent/compose.yaml`、`child/compose.yaml`はNetdataだけを定義し、`cloudflared`はGateway native serviceで管理します。 |
| REQ-ARCH-002 | PASS | Composeにhost package installationを含めず、`docs/deployment.md`にGateway既存native `cloudflared`の再利用を記録しています。 |
| REQ-ARCH-003 | PASS | Compose、template、renderer、docsをGit管理し、secretとruntime fileをignoreしています。 |
| REQ-ARCH-004 | PASS | `images.env.example`はstable manifestをdigest固定しています。 |
| REQ-PARENT-001 | PASS | `parent/compose.yaml`にParent Netdata serviceがあります。 |
| REQ-PARENT-002 | PASS | Parent local collectionとstream receiver設定があり、`system.cpu` chartとAPI dataを確認しました。 |
| REQ-PARENT-003 | PASS | Parent named volume `/var/lib/netdata`などがあり、force recreate後もdataが残りました。 |
| REQ-PARENT-004 | PASS | `parent/config/netdata.conf.tmpl`はParent LANの19999/19998へbindし、Gateway source allowと別LAN timeoutを確認しました。 |
| REQ-PARENT-005 | PASS | `parent/config/stream.conf.tmpl`のUUID、API key、source-IP restrictionと、ParentでのGateway `system.cpu` dataを確認しました。 |
| REQ-CHILD-001 | PASS | `child/compose.yaml`にChild serviceがあります。 |
| REQ-CHILD-002 | PASS | Child templateの`[web] mode = none`と、Gateway 19999 connection refusedを確認しました。 |
| REQ-CHILD-003 | PASS | Child destinationは`PARENT_LAN_IP:19998`で、ParentでGateway dataを取得しました。 |
| REQ-CHILD-004 | PASS | Childにrouting、DNS、DHCP、firewall dependencyを追加していません。failure testは未検証です。 |
| REQ-CHILD-005 | PASS | Child Tier 0は2日で再接続設定があります。replicationは未実測です。 |
| REQ-CONT-001 | PASS | Composeのhost mountはread-onlyです。 |
| REQ-CONT-002 | PASS | `pid: host`と`network_mode: host`を設定しています。 |
| REQ-CONT-003 | PASS | 初期化用5つとcollector用2つのcapabilityに限定し、AppArmor override、socket、privilegedを除外しています。 |
| REQ-CONT-004 | PASS | Rootless Dockerを採用し、root-only RAPL readをhost helperへ分離しています。 |
| REQ-DOCKER-001 | NOT VERIFIED | Docker socketがないためEngine固有container metricsは提供せず、host/cgroup chart範囲も未実測です。 |
| REQ-DOCKER-002 | PASS | direct socketを使わず、proxyを将来候補として文書化しています。 |
| REQ-CF-001 | PASS | `docs/deployment.md`に固定hostnameを記載しています。Gateway native Tunnel routeは変更していません。 |
| REQ-CF-002 | NOT VERIFIED | origin `http://192.168.1.102:19999`を文書化しましたが、Cloudflare側origin変更と認証後originは未確認です。 |
| REQ-CF-003 | PASS | どちらのCompose fileにも`cloudflared`を定義せず、Gateway native serviceを使います。 |
| REQ-CF-004 | NOT VERIFIED | Gateway native serviceとtoken管理の既存状態は確認しましたが、Netdata origin routeは未確認です。 |
| REQ-CF-005 | PASS | Composeにpublished portがなく、outbound Tunnel方式です。Internet scanは未実施です。 |
| REQ-CF-006 | NOT VERIFIED | Access先行とbypass禁止を文書化しましたが、live Tunnel originとpolicyは未確認です。 |
| REQ-POWER-001 | PASS | 両hostでrootless対応helperがactiveで、Parentの`statsd_netdata.rapl.package_watts_gauge`にWatts dataがあります。 |
| REQ-POWER-002 | PASS | CPU package powerとwall power全体を区別して説明しています。 |
| REQ-POWER-003 | PASS | Smart Plug、UPS、PDU測定は初期scope外です。 |
| REQ-DATA-001 | PASS | Parent named volumeとChild short DB設定があります。 |
| REQ-DATA-002 | PASS | Parent Tier 0 targetは30日ですが、実際のretention chart挙動は未実測です。 |
| REQ-DATA-003 | PASS | Parent DB directoryをCompose lifecycleから分離し、force recreate後のdata APIを確認しました。 |
| REQ-HA-001 | NOT VERIFIED | Gateway independenceは設計上の性質ですが、Parent停止試験は未実施です。 |
| REQ-HA-002 | NOT VERIFIED | Gateway native `cloudflared`は独立serviceですが、停止試験は未実施です。 |
| REQ-HA-003 | PASS | serviceは`restart: unless-stopped`で、host rebootは未試験です。 |
| REQ-PERF-001 | NOT VERIFIED | Gateway実機負荷は未測定です。 |
| REQ-PERF-002 | PASS | Childへ不要な公開機能を追加していません。 |
| REQ-PERF-003 | PASS | templateに`update every 1`を定義し、調整手順を記録しています。 |
| REQ-CLOUD-001 | PASS | self-hosted Parent/Childだけを使い、Netdata Cloudを要求しません。 |

## Acceptance Coverage

| Acceptance | Status | Evidence / reason |
| --- | --- | --- |
| AC-001 | NOT VERIFIED | public URLはHTTP `302`でAccessへredirectしますが、認証後dashboard表示は未確認です。 |
| AC-002 | NOT VERIFIED | live environmentでAccess policyのidentity条件を確認していません。 |
| AC-003 | PASS | Parent dashboardは`192.168.1.102:19999`へbindし、Gatewayから到達し、別LAN address `192.168.1.202`からtimeoutを確認しました。 |
| AC-004 | NOT VERIFIED | Internet port probeは未実施です。Composeにpublished portはありません。 |
| AC-005 | PASS | GatewayからParent TCP/19998へ接続し、Parentで`host=gateway`の`system.cpu` data 60行を取得しました。 |
| AC-006 | PASS | Child Composeにpublished portがなく、`[web] mode = none`で、Gateway 19999はconnection refusedでした。 |
| AC-007 | PASS | Parent APIのhost listに`gateway`が現れ、そのchart dataを取得しました。 |
| AC-008 | NOT VERIFIED | AI-PC hardware chartをNetdata runtimeで確認していません。 |
| AC-009 | PASS | 両RAPL helperがactiveで、ParentにWatts dataがあります。CPU package/RAPL powerであり、wall power全体ではありません。 |
| AC-010 | PASS | Parent health、API、dataがforce recreate後も維持され、named volumeが残りました。 |
| AC-011 | NOT VERIFIED | Parent停止時のGateway routing、DNS、DHCP継続試験は未実施です。 |
| AC-012 | NOT VERIFIED | Gateway hardware-specific chartは今回確認していません。 |
| AC-013 | NOT VERIFIED | host reboot試験は未実施です。 |
| AC-014 | NOT VERIFIED | AI-PC native serviceはinactive、Gateway native serviceはactiveでした。AI-PC package削除と認証後Cloudflare routeは未確認です。 |

## Failure Tests

実施済み:

- Parent Compose force recreate後のmetric persistence。
- healthcheck変更後のChild recreateとstreaming継続。

未実施:

- Parent stop/restart時のGateway routing、DNS、DHCP継続。
- Gateway native `cloudflared` stop時に外部UIだけが利用不可になること。
- GatewayとAI-PCのhost reboot後のautomatic recovery。
