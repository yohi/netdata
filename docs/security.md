# Security

## Threat Surface

- Netdata dashboardはhost loopbackだけで待ち受け、LAN/Internetへ直接公開しない。
- Netdata streamingはParent LAN IPのTCP/19998だけで、Child API keyとGateway IP制限を併用する。
- 外部Web UIはCloudflare Accessを先に通過したCloudflare Tunnelだけを使う。
- Gatewayにはcloudflared、reverse proxy、公開Web UI、Parent DBを配置しない。
- Tunnel tokenとstreaming API keyはGit管理せず、root-only fileとCompose secret/runtime configで扱う。

## Capabilities

| Item | Decision | Reason |
| --- | --- | --- |
| `SYS_PTRACE` | 使用 | Netdata公式Docker要件のlocal-listeners/process関連監視に対応する。 |
| `SYS_ADMIN` | 使用 | Netdata公式Docker要件のcgroups/network-viewer関連監視に対応する。 |
| `apparmor=unconfined` | 不使用 | 公式サンプルにはあるが、初期実装でruntime failureを確認していないため無条件に緩和しない。 |
| `privileged: true` | 不使用 | 必須要件に対応する根拠がなく、capability追加で代替する。 |
| Docker socket | 不使用 | read-only mountでもDocker APIへの強い権限になる。Docker固有metricsは初期実装の未提供範囲とする。 |
| Rootless Docker | 採用しない | Issueのhost process/disk/cgroup監視要件と公式のrootless制約が合わない。 |

`cap_drop: ALL`後に`SYS_ADMIN`と`SYS_PTRACE`だけを追加している。Netdata imageの実機起動で不足が確認された場合も、`privileged`へ拡大せず、失敗したcollectorと必要capabilityを記録して個別に再評価する。

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

## Docker Monitoring Policy

初期Composeは`/var/run/docker.sock`をmountしない。そのためHost CPU/memory/disk/network/process/cgroup/hardwareの範囲と、Docker Engine API由来のcontainer name/state/restart情報を区別する。後からDocker固有metricsが必要になった場合は、Netdata公式が示すsocket proxy方式を先に検証し、`/containers`など必要最小限のAPIと接続元を限定する。proxy方式も完全互換とは仮定しない。

## Cloudflare Access and Direct Access

Access applicationを作成する前にpublic hostnameを有効化しない。Tunnel originは`http://127.0.0.1:19999`で、Netdata側でTLS terminationしない。AI-PCのInbound Internet TCP/19998・19999は開放しない。

Parentのbind設定、host firewall、Cloudflare Accessを別々の防御層として扱う。Tunnel停止時は外部UIだけが停止し、Parent local collectionとChild LAN streamingは独立して継続する設計とする。この故障分離は実機試験完了までPASSとしない。

## Secret Handling

- `parent/secrets/cloudflared-token`、`*/secrets/stream-api-key`、`*/runtime/*.conf`、`images.env`はGit ignore対象。
- token fileはmode `600`を要求する。
- `stream.conf` templateにはplaceholderだけを置き、API key入りruntime fileをcommitしない。
- GitHub Issue、README、ログ、Compose outputへtoken/API keyを貼り付けない。
- `cloudflared tunnel list`失敗時もtokenやcredentialの値を表示しない。
