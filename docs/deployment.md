# Deployment

## Prerequisites

- Ubuntu Server、Docker Engine、Docker Compose pluginを対象ホストへ用意する。
- AI-PCへcloudflaredを追加しない。Gatewayの既存native `cloudflared` serviceを使用する。
- ParentのLAN IP、Gatewayの固定LAN IP、Cloudflare Tunnelの既存構成を先に確認する。
- `parent/images.env.example`と`child/images.env.example`のdigestを対象architectureで確認する。

## Parent

作業ディレクトリをリポジトリのルートとする。

```bash
cp parent/images.env.example parent/images.env
```

Streaming API keyはUUIDとして生成し、key自体を端末へ表示しない。

```bash
mkdir -p parent/secrets child/secrets
umask 077
uuidgen > parent/secrets/stream-api-key
cp parent/secrets/stream-api-key child/secrets/stream-api-key
chmod 600 parent/secrets/stream-api-key child/secrets/stream-api-key
```

Parent設定を生成する。値は対象LANへ置き換える。

```bash
NETDATA_HOSTNAME=ai-agent \
PARENT_LAN_IP=192.0.2.10 \
GATEWAY_LAN_IP=192.0.2.20 \
STREAM_API_KEY_FILE=parent/secrets/stream-api-key \
./scripts/render-config.sh parent
```

```bash
./scripts/validate.sh --deployment
docker compose --env-file parent/images.env -f parent/compose.yaml config
docker compose --env-file parent/images.env -f parent/compose.yaml up -d netdata
docker compose --env-file parent/images.env -f parent/compose.yaml ps
```

DashboardはParent LAN IPのTCP/19999、Child受信は同じParent LAN IPのTCP/19998です。両ポートはGateway LAN IPだけを許可し、それ以外をdenyするhost firewall ruleを、既存のUFW/nftables/firewalld方針に合わせて追加します。Firewall implementationが不明な状態で既存ruleを置換してはいけません。

## Child

Gatewayへリポジトリを配置し、Child用image envを作る。

```bash
cp child/images.env.example child/images.env
```

Parentと同じAPI keyをGateway上のroot-only fileへ配置し、Child設定を生成する。

```bash
NETDATA_HOSTNAME=gateway \
PARENT_LAN_IP=192.0.2.10 \
STREAM_API_KEY_FILE=child/secrets/stream-api-key \
./scripts/render-config.sh child
```

起動する。

```bash
./scripts/validate.sh --deployment
docker compose --env-file child/images.env -f child/compose.yaml config
docker compose --env-file child/images.env -f child/compose.yaml up -d
docker compose --env-file child/images.env -f child/compose.yaml ps
```

ChildはWeb UIを無効化しており、Gatewayのrouting、DNS、DHCP、firewallへ監視処理の依存を追加しない。Parent停止時もChild containerは稼働し、`stream.conf`の再接続処理を使う。

## Cloudflare

既存TunnelをDashboardまたはCloudflare APIで確認し、再利用可能なら新規Tunnelを作らない。Public hostnameを有効化する前に、Cloudflare AccessのSelf-hosted applicationを作成する。cloudflaredはGatewayのnative serviceで実行し、AI-PCでは実行しない。

```text
Hostname: netdata.y-ohi.com
Origin:   http://192.168.1.102:19999
```

Access policyは許可Identityを明示したPermit policyだけにする。未認証状態でoriginへ到達可能なbypass routeを作らない。Cloudflare側の設定変更は、現在のTunnelとAccess policyを確認した後に手動で行う。今回の実装はCloudflare APIを呼び出さず、既存設定を変更しない。

Gateway native `cloudflared`のtokenとsystemd unitはGatewayのroot-only管理下に置き、GitやAI-PCへコピーしない。既存serviceのoriginと管理方法を確認し、同じTunnelを別serviceで二重起動しない。

## Image Update and Rollback

更新前に対象architectureのmanifestを確認し、digestを`images.env`へ反映する。

```bash
docker buildx imagetools inspect netdata/netdata:stable
docker compose --env-file parent/images.env -f parent/compose.yaml pull
```

更新後は`docker compose ps`、localhost Dashboard、streaming、hardware collectorを確認する。問題がある場合は、変更前のdigestを`images.env`へ戻し、同じ`pull`と`up -d`で再生成する。自動更新は行わない。
