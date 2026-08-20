# Midnight Fireworks Screensaver

[English](README.md) | **日本語**

**午前二時の花火** — 月と星が浮かぶ静かな海辺で、遠くの花火を眺めるmacOS用スクリーンセーバーです。

![午前二時の花火 — 月夜の海辺と遠くの花火](screenshots/hero.png)


## ダウンロード

[**Midnight Fireworks Screensaver v1.1.1（ZIP）**](release/Midnight-Fireworks-Screensaver-v1.1.1.zip)

- 対応OS: macOS 11 Big Sur以降
- 対応CPU: Apple Silicon / Intel（Universal Binary）
- 表示名: `午前二時の花火`

## 特長

- 月、星、遠い島影、月明かりが映る海辺を描いたピクセルアート
- 菊、牡丹、柳、輪、点滅、千輪、椰子の7種類の花火
- 起動直後に最初の花火を打ち上げ
- 打ち上げは垂直方向、高めの位置で開花
- スターマインや画面全体のフラッシュを使わない静かな演出
- 花火の間隔を3段階から選択可能
- さざ波、風鈴、遠くの花火音を個別にオン・オフ可能（初期設定はすべてオフ）

## インストール

1. 上のZIPファイルをダウンロードして展開します。
2. `午前二時の花火.saver` をダブルクリックします。
3. macOSの案内に従ってインストールします。
4. 「システム設定」→「スクリーンセーバ」で `午前二時の花火` を選びます。
5. 必要に応じて「オプション」から花火の間隔や音を設定します。

### macOSのセキュリティ警告について

この配布物はad hoc署名済みですが、Apple Developer IDによる署名・公証は行っていません。そのため、初回起動時にmacOSが開発元を確認できない旨を表示する場合があります。

ソースコードとビルド手順を確認し、配布元を信頼できる場合に限り、いったん開こうとした後で「システム設定」→「プライバシーとセキュリティ」から「このまま開く」を選択してください。詳しくは[Appleの案内](https://support.apple.com/en-gb/102445)を参照してください。

## 設定

| 項目 | 内容 |
| --- | --- |
| 賑やか | 約4〜6秒間隔 |
| 静か | 約20〜45秒間隔（初期設定） |
| とても静か | 約35〜70秒間隔 |
| 音 | さざ波、風鈴、遠くの花火音を個別設定 |

![午前二時の花火の設定画面](screenshots/settings.png)

## ソースからビルド

Xcode Command Line Toolsが必要です。リポジトリを取得した後、次を実行します。

```sh
chmod +x build.sh
./build.sh
```

ビルドされたスクリーンセーバーは `dist/午前二時の花火.saver` に作成されます。ビルドスクリプトはarm64 / x86_64のUniversal Binaryを生成し、ローカルでad hoc署名を行います。

## 動作確認用プレビューホスト

ScreenSaverフレームワーク上での描画、7種類の花火、設定項目を確認するための小さなテストホストを同梱しています。

```sh
mkdir -p build
xcrun clang -fobjc-arc -fmodules \
  -framework AppKit -framework ScreenSaver \
  Tools/PreviewHost.m -o build/PreviewHost

./build/PreviewHost \
  "dist/午前二時の花火.saver" \
  /tmp/midnight-fireworks-preview.png \
  /tmp/midnight-fireworks-settings.png
```

## ライセンス

ソースコードは[MIT License](LICENSE)です。音声素材はCC0で公開されている録音を使用しています。出典は[AUDIO_CREDITS.md](AUDIO_CREDITS.md)を参照してください。
