# Security

## Threat Surface

- Netdata dashboardはParent LAN IPで待ち受け、Gateway sourceだけをhost firewallで許可し、Internetへ直接公開しない。
- Netdata streamingはParent LAN IPのTCP/19998だけで、Child API keyとGateway IP制限を併用する。
- 外部Web UIはCloudflare Accessを先に通過したCloudflare Tunnelだけを使う。
- Gatewayのnative `cloudflared`だけがCloudflare Tunnel connectorを担当し、reverse proxy、公開Child Web UI、Parent DBは配置しない。
- Gateway Tunnel tokenとstreaming API keyはGit管理せず、それぞれGatewayのroot-only native service管理とCompose runtime configで扱う。

## Capabilities

| Item | Decision | Reason |
| --- | --- | --- |
| `CHOWN`/`FOWNER` | 使用 | Netdata imageがnamed volumeのruntime directoryを初期化するために限定する。 |
| `DAC_OVERRIDE` | 使用 | Netdata imageの初期化処理がnamed volumeへアクセスするために限定する。 |
| `SETUID`/`SETGID` | 使用 | Netdata imageがroot初期化後にnetdataユーザーへdrop privilegeするために限定する。 |
| `SYS_PTRACE` | 使用 | Netdata公式Docker要件のlocal-listeners/process関連監視に対応する。 |
| `SYS_ADMIN` | 使用 | Netdata公式Docker要件のcgroups/network-viewer関連監視に対応する。 |
| `apparmor=unconfined` | 不使用 | 公式サンプルにはあるが、初期実装でruntime failureを確認していないため無条件に緩和しない。 |
| `privileged: true` | 不使用 | 必須要件に対応する根拠がなく、capability追加で代替する。 |
| Docker socket | 不使用 | read-only mountでもDocker APIへの強い権限になる。Docker固有metricsは初期実装の未提供範囲とする。 |
| Rootless Docker | 採用 | RAPLのroot-only sysfs読み取りはhost helperへ分離し、Docker daemonをrootfulにしない。 |

`cap_drop: ALL`後に、Netdata imageの初期化と公式collector要件に対応するcapabilityだけを追加している。RAPLのhost-only権限はcontainerへ拡大せず、`host/netdata-rapl-statsd`のroot helperへ限定する。

## Host Mounts

| Host path | Container path | Mode | Purpose |
| --- | --- | --- | --- |
| `/` | `/host/root` | read-only, rslave | filesystem/mount point discovery |
| `/proc` | `/host/proc` | read-only | host CPU/memory/process/network metrics |
| `/sys` | `/host/sys` | read-only | cgroup, hwmon, powercap, disk metrics |
| `/etc/passwd`, `/etc/group` | `/host/etc/...` | read-only | user/group process attribution |
| `/etc/os-release`, `/etc/localtime` | `/host/etc/...` | read-only | host identity and timezone |
| `/var/log` | `/host/var/log` | read-only | optional log collectors |
| `/run/dbus` | `/run/dbus` | read-only | optional systemd unit collectors |

Netdata writable dataは`/var/lib/netdata`、`/var/cache/netdata`、`/var/log/netdata`のnamed volumeだけに置く。Host rootへwrite mountは行わない。

`read_only: true`で必要なruntime stateはNetdata serviceの`tmpfs: /run`へ置く。これはHost filesystemへの書き込みではない。

## Rootless RAPL Helper

`host/netdata-rapl-statsd.service`は`CAP_DAC_READ_SEARCH`だけをBoundingSetへ残したroot serviceで、RAPL energy counterを読み取り、Watts gaugeをlocalhost StatsDへ送信する。外部listen、Docker socket、host write mountは持たない。Helperの出力は測定値だけで、credentialやAPI keyを扱わない。

## Docker Monitoring Policy

初期Composeは`/var/run/docker.sock`をmountしない。そのためHost CPU/memory/disk/network/process/cgroup/hardwareの範囲と、Docker Engine API由来のcontainer name/state/restart情報を区別する。後からDocker固有metricsが必要になった場合は、Netdata公式が示すsocket proxy方式を先に検証し、`/containers`など必要最小限のAPIと接続元を限定する。proxy方式も完全互換とは仮定しない。

## Cloudflare Access and Direct Access

Access applicationを作成する前にpublic hostnameを有効化しない。Tunnel originはGatewayから到達する`http://192.168.1.102:19999`で、Netdata側でTLS terminationしない。AI-PCのInbound Internet TCP/19998・19999はGateway source以外へ開放しない。

Parentのbind設定、host firewall、Cloudflare Accessを別々の防御層として扱う。Tunnel停止時は外部UIだけが停止し、Parent local collectionとChild LAN streamingは独立して継続する設計とする。この故障分離は実機試験完了までPASSとしない。

## Secret Handling

- `*/secrets/stream-api-key`、`*/runtime/*.conf`、`images.env`はGit ignore対象。Gateway native Tunnel tokenはAI-PCへ配置しない。
- native Tunnel tokenはGateway側でmode `600`相当のroot-only管理を要求する。
- `stream.conf` templateにはplaceholderだけを置き、API key入りruntime fileをcommitしない。
- GitHub Issue、README、ログ、Compose outputへtoken/API keyを貼り付けない。
- `cloudflared tunnel list`失敗時もtokenやcredentialの値を表示しない。
