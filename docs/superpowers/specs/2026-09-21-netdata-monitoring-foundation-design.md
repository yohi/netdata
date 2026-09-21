# Netdata Monitoring Foundation Design

## Scope

Issue #1 の初期実装として、AI-PC上のNetdata ParentとGateway上のNetdata Childを、Docker Composeで再生成可能な形にする。外部Cloudflare設定やGateway実機の変更は行わず、必要な手順と検証項目をリポジトリへ含める。

## Options

### A. Netdata公式Dockerサンプルをそのまま採用

`pid: host`、`network_mode: host`、`SYS_ADMIN`、`SYS_PTRACE`、`apparmor=unconfined`、Docker socket、広範なhost mountを採用する。機能互換性は高いが、Issueの最小権限要件に反し、Docker socketはread-onlyでも強い管理権限を与える。

### B. 必須ホスト監視に限定した最小権限構成

`pid: host`、`network_mode: host`、必要なkernel mountをread-onlyで使い、Docker socketと`apparmor=unconfined`を使わない。Netdata公式の説明に基づき、`SYS_PTRACE`はlocal-listeners/process監視、`SYS_ADMIN`はcgroups/network-viewer監視に対応付ける。Docker Engine固有のコンテナ名・状態・再起動情報は初期実装の未提供範囲として明記する。

### C. Docker socket proxyを追加

SocketをNetdataへ直接渡さず、`/containers` APIだけをproxyする。安全性は改善するが、初期要件に不要なサービスと互換性検証を追加し、Netdata公式もproxy方式は未検証機能があると説明している。Docker固有metricsが必要になったPhase 2へ延期する。

**採用案:** B。Cは将来の拡張候補としてsecurity documentationに比較結果を残す。

## Architecture

- `parent/compose.yaml` はNetdata Parentとcloudflaredを定義する。
- `child/compose.yaml` はNetdata Childだけを定義する。Gatewayにcloudflared、reverse proxy、公開Web UI、中央DBを置かない。
- ParentのNetdataはhost PID/network namespaceを使い、`127.0.0.1:19999=dashboard`と`PARENT_LAN_IP:19998=streaming`を現行の`[web].bind to`構文で分離する。
- Childは`[web] mode = none`とし、短期のdbengineを保持してParentへ再接続する。
- Parent/Childのstream.confはAPI keyと送信元IPを含むため、`.tmpl`だけをGit管理し、`scripts/render-config.sh`が秘密ファイルからruntime configを生成する。
- cloudflaredはremotely-managed Tunnelのtoken fileを`/run/secrets/tunnel-token`へ渡し、host networkで`http://127.0.0.1:19999`へ接続する。Public hostnameとAccess policyの変更はCloudflare側の手動手順にする。
- イメージは`images.env`でdigestを指定し、`images.env.example`にはplaceholderだけを置く。

## Mounts and Capabilities

- `/`、`/proc`、`/sys`、`/etc/passwd`、`/etc/group`、`/etc/os-release`、`/etc/localtime`、`/var/log`、`/run/dbus`をread-onlyで提供する。`host access prefix = /host`を使用する。
- Netdataの`/var/lib/netdata`、`/var/cache/netdata`、`/var/log/netdata`はnamed volumeに分離する。
- Netdata serviceは`CHOWN`、`DAC_OVERRIDE`、`FOWNER`、`SETUID`、`SETGID`をimage初期化用に、`SYS_PTRACE`と`SYS_ADMIN`をcollector用に採用する。`security.md`に各理由を記録し、`apparmor=unconfined`は採用しない。
- `read_only: true`で必要なruntime directoryはNetdata serviceの`tmpfs: /run`へ置く。
- `/var/run/docker.sock`はmountしない。Docker固有metricsの不足は検証結果と将来のproxy設計に記録する。
- cloudflaredは追加capabilityなし、read-only root filesystem、token secret mountだけとする。

## Retention and Streaming

- ParentはdbengineのTier 0を30日、Tier 1を6か月、Tier 2を2年の目標として設定する。各tierの`retention size = 0`は空き容量依存となるため、運用時はdbengine retention chartとディスク使用量を実測する。
- Childはdbengine Tier 0を2日とし、Parent障害時の短期吸収に限定する。
- Parentのreceiver sectionは`type = api`、`enabled = yes`、`allow from = GATEWAY_LAN_IP`、`db = dbengine`を使う。
- Childのsender sectionは`enabled = yes`、`destination = PARENT_LAN_IP:19998`、同一API key、`send charts matching = *`を使う。TLSはLAN初期実装の範囲外で、将来追加可能とする。

## Validation

- `docker compose --env-file images.env config`をParent/Childで実行する。
- shellcheckが存在する場合は全shell scriptを検査し、常に`bash -n`を実行する。
- templateのplaceholder、必須env、secret file mode、Git追跡状態を検査する。
- 実機が利用できないため、container health、HTTP bind、streaming、Access、recreate、reboot、RAPL chart、hwmon chart、NVMe chartは実測せず、`NOT VERIFIED`または`BLOCKED`とする。
- 現在のAI-PCで確認済みのRAPL/hwmon/NVMe capabilityはpreflight evidenceとして記録するが、Netdata chart生成のPASSとは扱わない。

## Official References

- Netdata Docker: https://learn.netdata.cloud/docs/netdata-agent/installation/docker
- Netdata web server reference: https://learn.netdata.cloud/docs/netdata-agent/configuration/securing-agents/web-server-reference
- Netdata streaming: https://learn.netdata.cloud/docs/netdata-parents/metrics-centralization-points/configuring-metrics-centralization-points
- Netdata database: https://learn.netdata.cloud/docs/netdata-agent/database
- Cloudflare tunnel tokens: https://developers.cloudflare.com/tunnel/reference/tunnel-tokens/
- Cloudflare run parameters: https://developers.cloudflare.com/tunnel/reference/run-parameters/
