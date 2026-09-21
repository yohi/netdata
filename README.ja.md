# Netdata宅内監視基盤

[English](README.md)

2台のホストで動作するNetdata Parent/Child監視構成を、Docker Composeで再生成できるようにしたリポジトリです。

AI-PCとGateway PCのホストメトリクスを収集し、中央metrics DBをAI-PCのParentだけに保持したい運用者を対象とします。宅内環境向けの基盤であり、そのまま本番運用へ投入する完成済みの配布物ではありません。

> [!WARNING]
> Cloudflare Access認証後のdashboard表示、host reboot後の復旧、いくつかのfailure testは未検証です。導入完了と判断する前に、[検証記録](docs/verification.ja.md)を確認してください。
>
> このリポジトリにはCIまたはrelease workflowがありません。現在のquality gateは、[Development](#development)のlocal validation commandです。

## Quick Start

ParentとChildは別ホストで実行します。両ホストにDocker EngineとDocker Compose pluginを用意し、次の順で進めます。

1. リポジトリをParentホストとGatewayホストへ配置します。
2. `parent/images.env.example`と`child/images.env.example`を、それぞれローカルの`images.env`へコピーし、対象architectureのdigestを確認します。
3. Parentでstreaming API keyを一度だけ生成し、承認済みの安全なchannelで同じkeyをGatewayのroot-only fileへ配置します。keyを表示またはcommitしてはいけません。
4. `scripts/render-config.sh`でParentとChildのruntime configを生成します。
5. 起動前に`./scripts/validate.sh --examples`と、両Compose projectの`docker compose config`を実行します。
6. 起動順序、firewall rule、既存Gateway `cloudflared` serviceは[deployment guide](docs/deployment.ja.md)に従って構成します。

期待する結果は、生成secretまたはruntime fileを追跡せずに両Compose configurationが検証を通過し、deployment guideの次の手順でhealthyなParentとChildを起動できることです。

## Features

- Parentだけがmetrics DBを持ち、Childは宅内LAN経由でstreamingします。
- Child Web UIを無効化し、Gatewayを2つ目のdashboardにしません。
- Dashboardとstreaming endpointをParentのLAN addressへbindし、Gateway source addressだけに制限します。
- Netdata imageをdigest固定し、生成runtime configによってAPI keyをGitから分離します。
- `privileged`、Docker socket mount、AppArmor overrideを使わないrootless Docker baselineです。
- Host-only RAPL helperがCPU package powerをローカルNetdata StatsDへ送信します。
- Shell syntax、template、image pin、Compose、secret境界、security invariantを静的検証します。

## How It Works

```text
Cloudflare Access
        |
Gateway native cloudflared -> http://<PARENT_LAN_IP>:19999
        |
AI-PC: netdata-parent
  <PARENT_LAN_IP>:19999 = dashboard
  <PARENT_LAN_IP>:19998 = streaming receiver
        ^
        | TCP/19998、Gateway source only
Gateway PC: netdata-child
  Web UI disabled
```

中央metrics DBを持つのはParentだけです。Childはローカルmetricsを収集してParentへ送信します。Tunnel originはGatewayの既存native `cloudflared` serviceが担当し、このリポジトリはどちらのCompose projectにも`cloudflared`をinstallまたはrunしません。

## Usage

- Gateway Tunnel originを構成した後、既存のCloudflare Access application経由でdashboardを開きます。
- ローカル確認にはParent LAN addressを使います。TCP/19999とTCP/19998をLAN全体またはInternetへ無制限公開しないでください。
- image update、rollback、RAPL install、service recreateは`docs/deployment.ja.md`を参照します。

## Configuration

- `parent/images.env.example`と`child/images.env.example`は安全な入力templateです。ローカルの`images.env`はignore対象で、untrackedのままにします。
- `scripts/render-config.sh`は`NETDATA_HOSTNAME`、`PARENT_LAN_IP`、`STREAM_API_KEY_FILE`を必須とし、Parentでは`GATEWAY_LAN_IP`も必須とします。
- 生成した`runtime/*.conf`と`*/secrets/stream-api-key`はローカルruntime stateです。permissionとGit tracking statusはvalidation scriptが検査します。

## Documentation

| 目的 | 参照先 |
| --- | --- |
| ParentとChildをdeployする | [Deployment](docs/deployment.md) / [日本語](docs/deployment.ja.md) |
| Security boundaryを確認する | [Security](docs/security.md) / [日本語](docs/security.ja.md) |
| EvidenceとIssue #1 coverageを確認する | [Verification](docs/verification.md) / [日本語](docs/verification.ja.md) |
| Gateway Tunnelの設計判断を確認する | [Architecture decision](docs/superpowers/specs/2026-09-21-gateway-native-cloudflared-design.md) |

英語ファイルが正本です。日本語ファイルは翻訳であり、一時的に同期が遅れる場合があります。内容が異なる場合は英語ファイルを優先してください。

## Development

リポジトリルートから決定的な検証を実行します。

```bash
bash tests/render-config.sh
bash tests/preflight.sh
bash tests/validate.sh
./scripts/validate.sh --examples
git diff --check
```

両roleのローカル`images.env`と生成済みruntime fileを含むcheckoutでは、`./scripts/validate.sh --deployment`を実行します。片方のroleだけを準備するhostでは、そのroleの`docker compose config`を実行します。`shellcheck`がinstall済みならvalidation scriptが自動的に使用します。

主な実装pathは次のとおりです。

```text
parent/                 Parent Composeとtemplate
child/                  Child Composeとtemplate
scripts/                rendering、preflight、validation
host/                   root RAPL helperとsystemd unit
tests/                  shell regression test
```

## License

[MIT](LICENSE)
