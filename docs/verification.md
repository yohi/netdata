# Verification and Issue #1 Coverage

## Evidence Rules

`PASS`は、この文書に記載した実装ファイルまたは実行済みコマンドの証拠がある場合だけに使う。container起動、Gateway通信、Cloudflare Access、hardware chart、recreate、rebootを実測していない項目は`NOT VERIFIED`または`BLOCKED`とする。能力pathが存在するだけではNetdata chartのPASSにしない。

## Gate 0 Evidence

実行元はAI-PC相当のUbuntu 26.04.1 LTS、kernel 7.0.0-31-generic、x86_64です。Docker 29.8.1、Compose 5.5.1を確認しました。`/sys/devices/virtual/powercap`に`intel-rapl`と`intel-rapl-mmio`、`/sys/class/hwmon`にcoretemp/NVMeを含む複数entry、WD_BLACK SN7100 1TB NVMeを確認しました。Gatewayは`192.168.1.103:2022`でSSH接続でき、Ubuntu 26.04 LTS、Docker 29.6.2、Compose 5.3.1を確認しました。

Cloudflare API token/origin certificateは取得していません。GatewayへChildを配置・起動し、Gatewayの既存native `cloudflared` serviceはactiveです。Parent Composeからcloudflared serviceを除去し、AI-PC側native serviceはinactiveになりました。AI-PC firewallはGateway sourceだけを許可するiptables-nftルールを適用し、`netfilter-persistent`でenabled/activeを確認しました。Netdata runtimeとGatewayの設定はGit archiveへsecretを含めず、SSH経由で配置しました。

## Static Validation

```bash
bash tests/render-config.sh
bash tests/preflight.sh
bash tests/validate.sh
bash tests/rapl-statsd.sh
bash scripts/validate.sh --examples
bash scripts/preflight.sh
docker compose --env-file parent/images.env.example -f parent/compose.yaml config
docker compose --env-file child/images.env.example -f child/compose.yaml config
./scripts/validate.sh --deployment
docker compose --env-file parent/images.env -f parent/compose.yaml config
docker compose --env-file child/images.env -f child/compose.yaml config
git diff --check
```

上記のrenderer、preflight、validator、Compose config、ShellCheck、bash syntax、diff check、`--deployment`を通過しています。`tests/rapl-statsd.sh`も通過しています。

## Parent Runtime Evidence

AI-PC上でdigest固定のNetdata Parentを起動し、Gateway Childからのstreamingを実測しました。

- Parent container: `running`, `healthy`, restart count `0`。
- `http://192.168.1.102:19999/api/v1/info`: HTTP `200`。
- `192.168.1.102:19999`: Parent LAN dashboard bind。Gateway-only firewall enforcementを確認。
- `192.168.1.102:19998`: HTTP `451`。Dashboard HTMLではなくstreaming専用endpointの応答。
- `system.cpu`: APIから30点を取得。NVMe I/O (`disk.nvme0n1`)、network、memory chart名を確認。
- containerから`/host/sys/devices/virtual/powercap`、`/host/sys/class/hwmon`、`/host/sys/class/nvme`を確認。
- Rootless Dockerでは標準RAPL collectorがhost `energy_uj`を読めず、debugfs pluginがpermission deniedで停止したため、host helperへ分離した。両ホストへのroot install後、Watts chart/dataを確認。
- `--force-recreate`後も`running/healthy`、API HTTP `200`、`system.cpu` dataを確認。recreate前の最終sampleとrecreate後の180秒queryに重複sampleがあり、Parent named volumeのDB保持を確認。
- 起動ログにはsystemd journalのread-only更新失敗とdebugfs無効化があった。必須dashboard/CPU/NVMe/APIは動作したが、journal/debugfsは追加権限なしの制約として記録する。
- Gateway native `cloudflared` serviceはactiveだが、Tunnel originのCloudflare側変更は未実施。Access認証後のdashboard表示とpolicy内容は未確認。

## Gateway Runtime Evidence

- GatewayのChild container: `running`, `healthy`, restart count `0`。
- Gatewayの`netdata-rapl-statsd.service`は`active`。StatsDは`127.0.0.1:8125`だけでlisten。
- Child image healthcheckはWeb UI無効化と衝突したため、`child/compose.yaml`で`/usr/sbin/netdatacli ping`へ変更した。変更後のhealthcheckとCLI pingは成功。
- Gatewayの`127.0.0.1:19999`はconnection refused。Child Web UIが公開されていないことを確認。
- GatewayからParent `192.168.1.102:19998`へのTCP接続に成功。
- GatewayからParent `192.168.1.102:19999`へのDashboard API接続に成功。
- GatewayからParent `:19998`はHTTP `451`を返した。streaming専用bindの想定内応答。
- Parent `/api/v1/charts`で`hosts_count=2`、`gateway` hostを確認。
- Parent `/api/v1/data?chart=system.cpu&host=gateway`で直近60行を取得。Gateway streamingを実測済み。
- AI-PCの別LANアドレス`192.168.1.202`からParent `:19999`はtimeoutになった。Gateway-only firewall ruleの適用後挙動を確認。
- AI-PC/Gatewayの`netdata-rapl-statsd.service`は`active`。Parentに`statsd_netdata.rapl.package_watts_gauge`が生成され、直近60行のWatts dataを取得。

## Requirement Coverage

| Requirement | Status | Evidence / reason |
| --- | --- | --- |
| REQ-ARCH-001 | PASS | `parent/compose.yaml`, `child/compose.yaml`。NetdataのみをComposeで定義し、cloudflaredはGateway native serviceで管理。 |
| REQ-ARCH-002 | PASS | Composeにhost package installationを含めず、docs/deployment.md。Gatewayの既存native cloudflaredを再利用。 |
| REQ-ARCH-003 | PASS | Compose、templates、renderer、docsをGit管理。secret/runtimeはignore。 |
| REQ-ARCH-004 | PASS | `images.env.example`はstable manifest digest固定。 |
| REQ-PARENT-001 | PASS | `parent/compose.yaml`のNetdata service。 |
| REQ-PARENT-002 | PASS | Parent local collectionとstream receiver設定。runtimeで`system.cpu` chart/APIを確認。 |
| REQ-PARENT-003 | PASS | Parent named volumes `/var/lib/netdata`等。force-recreate後もAPI/dataが維持された。 |
| REQ-PARENT-004 | PASS | `parent/config/netdata.conf.tmpl`はParent LANの19999/19998 bind。Gateway source許可と別LAN source timeoutを確認。 |
| REQ-PARENT-005 | PASS | `parent/config/stream.conf.tmpl`のUUID/API/source-IP制限。Gatewayの`system.cpu` dataをParentで取得。 |
| REQ-CHILD-001 | PASS | `child/compose.yaml`。 |
| REQ-CHILD-002 | PASS | Child templateの`[web] mode = none`。Gatewayの19999 connection refusedを確認。 |
| REQ-CHILD-003 | PASS | Child templateのLAN `PARENT_LAN_IP:19998` destination。ParentでGateway dataを取得。 |
| REQ-CHILD-004 | PASS | Childにrouting/DNS/DHCP/firewall依存を追加していない。故障試験は未検証。 |
| REQ-CHILD-005 | PASS | Child Tier 0 2日と再接続設定。replication実測は未検証。 |
| REQ-CONT-001 | PASS | Composeのhost mountはread-only。 |
| REQ-CONT-002 | PASS | `pid: host`と`network_mode: host`。 |
| REQ-CONT-003 | PASS | capを初期化用5つとcollector用2つに限定し、AppArmor override/socket/privilegedを除外。 |
| REQ-CONT-004 | PASS | Rootless Dockerを採用し、RAPLのroot-only読み取りはhost helperへ分離。 |
| REQ-DOCKER-001 | NOT VERIFIED | Docker socketなしのためEngine固有container metricsは未提供。host/cgroup範囲のchartも未実測。 |
| REQ-DOCKER-002 | PASS | direct socketを使わずproxyを将来候補として文書化。 |
| REQ-CF-001 | PASS | `docs/deployment.md`に固定hostnameを記載。Gateway native Tunnel routeは未変更。 |
| REQ-CF-002 | NOT VERIFIED | origin `http://192.168.1.102:19999`を文書化。Cloudflare側origin変更と認証後originは未確認。 |
| REQ-CF-003 | PASS | Parent/Child Composeにcloudflaredを定義せず、Gateway native serviceを使用。 |
| REQ-CF-004 | NOT VERIFIED | Gateway native cloudflaredのsystemd/token管理は既存状態を確認したが、Netdata origin routeは未確認。 |
| REQ-CF-005 | PASS | Composeにportsがなく、Tunnel outbound方式。Internet scanは未検証。 |
| REQ-CF-006 | NOT VERIFIED | Access先行手順とbypass禁止を文書化。Tunnel origin/policy実設定は未確認。 |
| REQ-POWER-001 | PASS | AI-PC/Gatewayのrootless対応helperをsystemdで起動し、Parentの`statsd_netdata.rapl.package_watts_gauge`でWatts data 60行を確認。 |
| REQ-POWER-002 | PASS | CPU Package Powerを全体消費電力と扱わない説明。 |
| REQ-POWER-003 | PASS | Smart Plug/UPS/PDUを初期scope外と記載。 |
| REQ-DATA-001 | PASS | Parent named volumesとChild short DB。 |
| REQ-DATA-002 | PASS | Parent Tier 0 30d target。実Retention chartは未検証。 |
| REQ-DATA-003 | PASS | Parent DB directoriesをCompose lifecycleから分離し、force-recreate後のdata APIを確認。 |
| REQ-HA-001 | NOT VERIFIED | 設計上Gateway機能へ依存しないがParent停止試験は未実施。 |
| REQ-HA-002 | NOT VERIFIED | Gateway native cloudflared独立serviceだが停止試験は未実施。 |
| REQ-HA-003 | PASS | servicesに`restart: unless-stopped`。host rebootは未検証。 |
| REQ-PERF-001 | NOT VERIFIED | Gateway実機負荷を測定していない。 |
| REQ-PERF-002 | PASS | Childへ不要な公開機能を追加していない。 |
| REQ-PERF-003 | PASS | update every 1をtemplateに定義し、調整手順を残した。 |
| REQ-CLOUD-001 | PASS | Self-hosted Parent/Childのみで構成し、Netdata Cloudを要求しない。 |

## Acceptance Coverage

| Acceptance | Status | Evidence / reason |
| --- | --- | --- |
| AC-001 | NOT VERIFIED | 公開URLはHTTP `302`でAccessへredirectするが、認証後dashboard表示は未確認。 |
| AC-002 | NOT VERIFIED | Access policyのidentity条件を実環境で確認していない。 |
| AC-003 | PASS | Parent dashboardは`192.168.1.102:19999`へbindし、Gatewayから到達、別LANアドレス`192.168.1.202`からtimeoutを確認。 |
| AC-004 | NOT VERIFIED | Internetからのport probe未実施。Composeはportsなし。 |
| AC-005 | PASS | GatewayからParent TCP/19998へ接続し、Parentで`host=gateway`の`system.cpu` data 60行を取得。 |
| AC-006 | PASS | Child Composeにport公開なし、`[web] mode = none`、Gateway 19999 connection refused。 |
| AC-007 | PASS | Parent APIのhost listに`gateway`が現れ、Gateway chart dataを取得。 |
| AC-008 | NOT VERIFIED | AI-PC hardware chartをNetdata runtimeで未確認。 |
| AC-009 | PASS | 両ホストのRAPL helperがactiveで、ParentにWatts chart/dataを確認。これはCPU Package/RAPL値であり、壁コンセント全体の実測ではない。 |
| AC-010 | PASS | Parent force-recreate後もhealth/API/dataが維持され、named volumeが残った。 |
| AC-011 | NOT VERIFIED | Parent停止時のGateway routing/DNS/DHCP試験未実施。 |
| AC-012 | NOT VERIFIED | Gatewayのhardware-specific chartは今回未確認。 |
| AC-013 | NOT VERIFIED | Host reboot試験未実施。 |
| AC-014 | NOT VERIFIED | AI-PC native serviceはinactive、Gateway native serviceはactive。AI-PC package削除と認証後Cloudflare routeは未確認。 |

## Failure Tests

実施済み:

- Parent Compose force-recreate後のmetrics persistence。
- Child Compose healthcheck変更後の再作成とstreaming継続。

未実施:

- Parent stop/restartとGateway routing/DNS/DHCP継続。
- Gateway native cloudflared stopと外部UIだけの停止。
- Gateway/AI-PC host reboot後の自動復旧。
