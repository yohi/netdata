# Deployment

[English](deployment.md)

この文書は`deployment.md`の日本語訳です。内容が異なる場合は英語版を正本として扱います。

## Prerequisites

- Ubuntu Server、Docker Engine、Docker Compose pluginを両方の対象ホストへ用意します。
- AI-PCへ`cloudflared`を追加せず、Gatewayの既存native `cloudflared` serviceを使います。
- ParentのLAN IP、Gatewayの固定LAN IP、既存Cloudflare Tunnel構成を先に確認します。
- `parent/images.env.example`と`child/images.env.example`のdigestを対象architectureで確認します。

## Parent

Parent host上のリポジトリrootから実行します。

```bash
cp parent/images.env.example parent/images.env
```

Streaming API keyはParent hostで一度だけUUIDとして生成し、key自体をterminalへ表示しません。

keyを生成する前に、Gatewayへruntime fileやsecretを含まないclean checkoutを配置しておきます。

```bash
mkdir -p parent/secrets
umask 077
uuidgen > parent/secrets/stream-api-key
chmod 600 parent/secrets/stream-api-key
```

このkey fileだけを、承認済みの安全なchannelでGatewayへtransferします。keyを生成した後のcheckout全体をcopyしてはいけません。Gatewayでは受信fileを`child/secrets/stream-api-key`へmode `600`で配置し、一時transfer copyを削除します。transfer中にkeyを表示してはいけません。

Parent設定を生成します。example addressは対象LANの値へ置き換えます。

```bash
NETDATA_HOSTNAME=ai-agent \
PARENT_LAN_IP=192.0.2.10 \
GATEWAY_LAN_IP=192.0.2.20 \
STREAM_API_KEY_FILE=parent/secrets/stream-api-key \
./scripts/render-config.sh parent
```

```bash
./scripts/validate.sh --examples
docker compose --env-file parent/images.env -f parent/compose.yaml config
docker compose --env-file parent/images.env -f parent/compose.yaml up -d netdata
docker compose --env-file parent/images.env -f parent/compose.yaml ps
```

DashboardはParent LAN IPのTCP/19999、Child receiverは同じParent LAN IPのTCP/19998でlistenします。既存のUFW、nftables、firewalld方針に合わせ、両portをGateway LAN IPからだけ許可し、それ以外をdenyするhost firewall ruleを追加します。active firewall implementationが不明な状態で既存ruleを置換してはいけません。

## Child

cleanなGateway checkoutでChild用image environment fileを作ります。

```bash
cp child/images.env.example child/images.env
```

同じAPI keyがGateway上のroot-only file `child/secrets/stream-api-key`へ配置されていることを確認し、Child設定を生成します。

```bash
NETDATA_HOSTNAME=gateway \
PARENT_LAN_IP=192.0.2.10 \
STREAM_API_KEY_FILE=child/secrets/stream-api-key \
./scripts/render-config.sh child
```

Child serviceを起動します。

```bash
./scripts/validate.sh --examples
docker compose --env-file child/images.env -f child/compose.yaml config
docker compose --env-file child/images.env -f child/compose.yaml up -d
docker compose --env-file child/images.env -f child/compose.yaml ps
```

Child Web UIは無効です。監視処理はGatewayのrouting、DNS、DHCP、firewall serviceへ依存しません。Parentが利用できない場合もChild containerは稼働し、`stream.conf`の再接続処理を使います。

`--deployment` modeはリポジトリ全体のcheckです。両roleのローカル`images.env`と、両roleの生成済みruntime configurationを含むcheckoutからだけ実行します。

```bash
./scripts/validate.sh --deployment
```

片方のroleだけを準備するhostでは、上記のrole-specificな`docker compose config` commandを使います。

## Rootless RAPL Power Collection

Rootless Dockerではcontainer内rootがhostの`/sys/devices/virtual/powercap/*/energy_uj`を読めないため、Netdata標準のRAPL collectorを直接使えません。Docker daemonをrootfulへ変更せず、host上の最小root helperがRAPL energy counterを読み、localhostのNetdata StatsDへWattsを送信します。

AI-PCとGatewayの両方で実行します。

```bash
sudo install -d -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0750 host/netdata-rapl-statsd /usr/local/libexec/netdata-rapl-statsd
sudo install -o root -g root -m 0644 host/netdata-rapl-statsd.service /etc/systemd/system/netdata-rapl-statsd.service
sudo systemctl daemon-reload
sudo systemctl enable --now netdata-rapl-statsd.service
systemctl is-active netdata-rapl-statsd.service
```

Helperは外部listen socketを作らず、`127.0.0.1:8125`のStatsDへだけ送信します。Metric名は`netdata.rapl.package_watts`で、ParentではStatsD chartとして現れ、GatewayではChildからParentへstreamingされます。RAPL counterがないhostではserviceが失敗し、power chartは生成されません。

## Cloudflare

既存TunnelをDashboardまたはCloudflare APIで確認し、再利用可能なら新規Tunnelを作りません。public hostnameを有効化する前にCloudflare Access self-hosted applicationを作成します。`cloudflared`はGatewayのnative serviceで実行し、AI-PCでは実行しません。

```text
Hostname: netdata.y-ohi.com
Origin:   http://192.168.1.102:19999
```

Access policyは許可identityを明示したPermit policyだけにします。未認証状態でoriginへ到達可能なbypass routeを作りません。Cloudflare側の設定変更は、現在のTunnelとAccess policyを確認した後に手動で行います。このリポジトリはCloudflare APIを呼び出さず、既存設定を変更しません。

Gateway native `cloudflared`のtokenとsystemd unitはGatewayのroot-only管理下に置き、GitやAI-PCへコピーしません。既存serviceのoriginと管理方法を確認し、同じTunnelを別serviceで二重起動しません。

## Image Update and Rollback

更新前に対象architectureのmanifestを確認し、選択したdigestを両hostのrole-specificな`images.env`へ反映します。

```bash
docker buildx imagetools inspect netdata/netdata:stable
docker compose --env-file parent/images.env -f parent/compose.yaml pull
docker compose --env-file parent/images.env -f parent/compose.yaml up -d netdata
docker compose --env-file parent/images.env -f parent/compose.yaml ps
docker compose --env-file child/images.env -f child/compose.yaml pull
docker compose --env-file child/images.env -f child/compose.yaml up -d
docker compose --env-file child/images.env -f child/compose.yaml ps
```

Parent commandはParent hostで、Child commandはGateway hostで実行します。各update後に`docker compose ps`、local dashboard、streaming、hardware collectorを確認します。問題がある場合は、両roleの`images.env`を変更前のdigestへ戻し、role-specificな`pull`と`up -d`を再実行します。automatic updateは有効化しません。
