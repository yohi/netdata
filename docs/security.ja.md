# Security

[English](security.md)

この文書は`security.md`の日本語訳です。リポジトリで実装した境界と延期した機能を記録するものであり、hostまたはCloudflareのsecurity policyの代わりではありません。内容が異なる場合は英語版を正本として扱います。

## Threat Surface

- Netdata dashboardはParent LAN IPでlistenし、host firewallでGateway sourceだけを許可し、Internetへ直接公開しません。
- Netdata streamingはParent LAN IPのTCP/19998だけで、Child API keyとGateway source-IP restrictionを併用します。
- 外部Web UIはCloudflare Access通過後のCloudflare Tunnelだけで到達します。
- Tunnel connectorはGateway native `cloudflared` serviceだけです。リポジトリはGatewayへreverse proxy、公開Child Web UI、Parent DBを追加しません。
- Gateway Tunnel tokenとstreaming API keyはGit管理しません。前者はGatewayのroot-only native service、後者はローカルCompose runtime fileで管理します。

## Capabilities

| Item | Decision | Reason |
| --- | --- | --- |
| `CHOWN` / `FOWNER` | 使用 | Netdata imageがnamed-volumeのruntime directoryを初期化するために限定します。 |
| `DAC_OVERRIDE` | 使用 | Netdata imageのnamed volume初期化アクセスに限定します。 |
| `SETUID` / `SETGID` | 使用 | imageがroot初期化後に`netdata` userへdrop privilegeするために使います。 |
| `SYS_PTRACE` | 使用 | local-listenerとprocess monitoringに対するNetdata公式要件に対応します。 |
| `SYS_ADMIN` | 使用 | cgroupとnetwork-viewer monitoringに対するNetdata公式要件に対応します。 |
| `apparmor=unconfined` | 不使用 | 公式sampleにはありますが、初期実装で緩和を正当化するruntime failureを確認していません。 |
| `privileged: true` | 不使用 | 要件に基づく根拠がなく、capability追加で対応します。 |
| Docker socket | 不使用 | read-only mountでもDocker APIへの強いaccessを与えるためです。Docker固有metricsは初期scope外です。 |
| Rootless Docker | 採用 | root-only RAPL sysfs accessをhost helperへ分離し、Docker daemonをrootfulへ変更しません。 |

`cap_drop: ALL`の後に、image初期化と公式collector要件に必要なcapabilityだけを追加します。RAPLのhost-only accessをcontainerへ拡大せず、`host/netdata-rapl-statsd`のroot helperへ限定します。

## Host Mounts

| Host path | Container path | Mode | Purpose |
| --- | --- | --- | --- |
| `/` | `/host/root` | read-only, rslave | filesystemとmount pointのdiscovery。 |
| `/proc` | `/host/proc` | read-only | host CPU、memory、process、network metrics。 |
| `/sys` | `/host/sys` | read-only | cgroup、hwmon、powercap、disk metrics。 |
| `/etc/passwd`, `/etc/group` | `/host/etc/...` | read-only | userとgroupのprocess attribution。 |
| `/etc/os-release`, `/etc/localtime` | `/host/etc/...` | read-only | host identityとtimezone。 |
| `/var/log` | `/host/var/log` | read-only | optional log collector。 |
| `/run/dbus` | `/run/dbus` | read-only | optional systemd unit collector。 |

Netdata writable dataは`/var/lib/netdata`、`/var/cache/netdata`、`/var/log/netdata`のnamed volumeだけに制限します。Compose fileはhost rootへのwrite pathをmountしません。

`read_only: true`で必要なruntime stateはNetdata serviceの`tmpfs: /run`へ置きます。これはhost filesystemへ書き込みません。

## Rootless RAPL Helper

`host/netdata-rapl-statsd.service`はBoundingSetに`CAP_DAC_READ_SEARCH`だけを残したroot serviceです。RAPL energy counterを読み取り、localhost StatsDへWatts gaugeを送ります。外部listen、Docker socket、host write mountを持ちません。出力は測定値だけで、credentialやAPI keyを扱いません。

## Docker Monitoring Policy

初期Composeは`/var/run/docker.sock`をmountしません。そのためhost CPU、memory、disk、network、process、cgroup、hardware metricsと、container name、state、restart countなどDocker Engine API由来のmetricsを区別します。Docker固有metricsが必要になった場合は、Netdata公式のsocket-proxy guidanceに基づく設計を先に検証し、`/containers`など必要最小限のAPIと接続元を限定します。proxyが完全互換だとは、検証なしに仮定しません。

## Cloudflare Access and Direct Access

Access applicationを作成する前にpublic hostnameを有効化しません。Tunnel originはGatewayから到達する`http://192.168.1.102:19999`で、Netdata側でTLS terminationしません。AI-PCのInbound TCP/19998とTCP/19999はGateway以外のsourceへ開放しません。

Parent bind設定、host firewall、Cloudflare Accessを別々の防御層として扱います。Tunnel停止時は外部UIだけが停止し、Parent local collectionとChild LAN streamingは独立して継続する設計です。この故障分離はlive failure testが完了するまでverifiedにしません。

## Secret Handling

- `*/secrets/stream-api-key`、`*/runtime/*.conf`、`images.env`はGit ignore対象です。Gateway native Tunnel tokenはGatewayに留めます。
- native Tunnel tokenはGateway側でmode `600`相当のroot-only管理にします。
- `stream.conf` templateにはplaceholderだけを置き、API key入りruntime fileをcommitしません。
- GitHub Issue、README、ログ、Compose outputへTunnel tokenやAPI keyを貼り付けません。
- `cloudflared tunnel list`失敗時もtokenやcredentialの値をerror handlingやdiagnostic outputへ出しません。
