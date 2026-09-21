# Netdata宅内監視基盤

Issue #1の要件に基づく、Docker Composeで再生成可能なNetdata Parent/Child構成です。

## Architecture

```text
Cloudflare Access
        |
Cloudflare Tunnel -> http://192.168.1.102:19999
        |
AI-PC: netdata-parent
  192.168.1.102:19999 = dashboard (Gateway-only)
  AI-PC LAN IP:19998 = streaming
        ^
        | TCP/19998, Gateway LAN IP only
Gateway PC: netdata-child
  dashboard disabled
```

Parentだけがmetrics DBを持ちます。GatewayはChildとしてローカルmetricsを収集し、宅内LAN経由でParentへ送信します。Cloudflare TunnelはGatewayの既存native `cloudflared` serviceが担当し、AI-PCにはcloudflaredを配置しません。Gateway上のChild Web UI、reverse proxy、Docker socket、中央DBは配置しません。

## Quick Start

1. 対象ホストへこのリポジトリを配置します。ParentとChildはそれぞれ別ホストで実行します。
2. `parent/images.env.example`または`child/images.env.example`を`images.env`へコピーし、digestとパスを確認します。
3. Gateway native `cloudflared`のTunnel originを`http://192.168.1.102:19999`へ設定し、Access policyを先に確認します。
4. Streaming API keyを安全なファイルへ生成し、`scripts/render-config.sh`でruntime configを生成します。生成ファイルとkeyはGitへ追加しません。
5. `scripts/validate.sh`で静的検証を行い、各Composeで`docker compose config`を実行します。
6. `docs/deployment.md`の手順でParent、Child、Firewall、Cloudflare Accessを順に構成します。

## Directory Structure

```text
parent/
  compose.yaml
  images.env.example
  config/*.tmpl
  runtime/                 # generated, ignored
  secrets/                 # streaming key only, local and ignored
child/
  compose.yaml
  images.env.example
  config/*.tmpl
  runtime/                 # generated, ignored
scripts/
  render-config.sh
  preflight.sh
  validate.sh
host/
  netdata-rapl-statsd
  netdata-rapl-statsd.service
```

## Scope and Evidence

このcheckoutはAI-PC上で作業しています。Parent/Child container、GatewayからParentへのstreaming、Child Web UI無効化、FirewallによるGateway-only Dashboard到達、RAPL helper経由のpower chartを実測済みです。Access認証後のdashboard、reboot、failure testは未検証です。詳細は`docs/verification.md`を参照してください。

## Documents

- [Deployment](docs/deployment.md)
- [Security](docs/security.md)
- [Verification and Issue #1 coverage](docs/verification.md)
- [Design](docs/superpowers/specs/2026-09-21-netdata-monitoring-foundation-design.md)
