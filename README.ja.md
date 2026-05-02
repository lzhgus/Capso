<p align="right">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | <strong>日本語</strong> | <a href="README.ko.md">한국어</a>
</p>

# Capso

**macOS向けのオープンソースなスクリーンショット＆画面録画ツール**

Swift 6.0 と SwiftUI で構築された、無料・ネイティブな CleanShot X 代替アプリです。macOS 15.0 以降に対応しています。

[![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-blue)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![License: BSL 1.1](https://img.shields.io/badge/License-BSL%201.1-green.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/lzhgus/Capso?style=social)](https://github.com/lzhgus/Capso/stargazers)

<p align="center">
  <a href="https://www.producthunt.com/products/capso?embed=true&utm_source=badge-top-post-badge&utm_medium=badge&utm_campaign=badge-capso" target="_blank" rel="noopener noreferrer"><img alt="Capso - Free open-source screenshot &amp; screen recorder for Mac | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/top-post-badge.svg?post_id=1120330&theme=light&period=daily&t=1776201173308"></a>
</p>

<p align="center">
  <img src=".github/assets/hero.gif" alt="Capso デモ" width="720">
</p>

<p align="center">
  <a href="https://github.com/lzhgus/Capso/releases/latest"><strong>ダウンロード &rarr;</strong></a> &nbsp;&bull;&nbsp;
  <a href="https://www.awesomemacapp.com/app/capso">公式サイト</a> &nbsp;&bull;&nbsp;
  <a href="https://x.com/lzhgus">@lzhgus をフォロー</a> &nbsp;&bull;&nbsp;
  <a href="#機能">機能</a> &nbsp;&bull;&nbsp;
  <a href="#ソースからビルド">ソースからビルド</a>
</p>

---

## ダウンロード

[**GitHub Releases →**](https://github.com/lzhgus/Capso/releases/latest) から、署名・公証済みの最新 DMG を入手できます。

Homebrew でもインストールできます。

```bash
brew tap lzhgus/tap
brew install --cask capso
```

または [ソースからビルド](#ソースからビルド) してください。

> 初回利用時に、画面収録・カメラ・マイクの権限が必要です。アプリが案内を表示します。

---

## なぜオープンソースなのか

macOS のスクリーンショットツールで実用的なものはたいてい有料です。CleanShot X は $29、Cap は $58。どちらも素晴らしいアプリですが、日常的な生産性機能が課金前提である必要はないと考えました。

Capso はその答えです。**完全にネイティブで、機能が充実した無料の代替アプリ**であり、オープンに開発されています。CaptureKit、AnnotationKit、OCRKit などの基盤機能は独立した SPM パッケージとして分割されているため、自分のアプリに組み込むこともできます。

私たちは [他のツール](https://www.awesomemacapp.com/) から収益を得ています。Capso は macOS コミュニティへの還元であり、Swift 6 ベースのモダンでモジュール化されたアプリの実例でもあります。

---

## 機能

### オールインワンキャプチャ
- **CleanShot 風のキャプチャ HUD** — 1 つのフローティングツールバーから、範囲、フルスクリーン、ウィンドウ、スクロール、タイマー、OCR、録画を選択
- **調整可能な選択範囲** — 確定前にキャプチャ範囲を移動・リサイズでき、周囲を暗くして選択部分を明るく表示
- **アスペクト比と固定サイズのプリセット** — Freeform、1:1、4:3、16:9、カスタム固定ピクセルサイズを素早く切り替え
- **インライン注釈** — 保存やコピーの前に、キャプチャ範囲へ矢印、図形、テキスト、ハイライト、ピクセル化を直接追加

### スクリーンショット
- **範囲キャプチャ** — ドラッグで範囲を選択し、サイズをリアルタイム表示。**R** キーでアスペクト比や固定サイズのプリセット（1:1、16:9、1920×1080、カスタム）を切り替え
- **フルスクリーンキャプチャ** — ワンクリックで画面全体を取得
- **ウィンドウキャプチャ** — 任意のウィンドウをクリックして取得
- **スクロールキャプチャ** — 長い Web ページ、チャット、ドキュメントを 1 枚の画像に結合
- **Quick Access** — コピー・保存・注釈・OCR・ピン留め・ドラッグ&ドロップに対応するフローティングプレビュー

### 画面録画
- **動画（MP4）** と **GIF** の録画
- **Webcam PiP** — 4 つの形状（円、正方形、縦長、横長）、ドラッグでリサイズ、角へスナップ
- **カメラプレゼンテーションモード** — PiP をクリックして全画面表示、もう一度クリックで元に戻る
- **システム音声 + マイク** の同時録音
- **録画コントロール** — 一時停止、停止、再開、削除、タイマー
- **カウントダウンオーバーレイ** — 録画開始前の 3-2-1 カウントダウン
- **書き出し品質プリセット** — Maximum / Social / Web
- **録画エディタ** — トリム、ズーム提案、カーソルスムージング、背景スタイル、MP4/GIF 書き出しを 1 つのフローで完結
- **ライブ合成プレビュー** — 書き出し前にズーム、カーソル、背景の変更結果を確認可能

### 注釈エディタ
- 矢印、矩形、楕円、テキスト、フリーハンド、ピクセル化/ぼかし、クロップ
- ハイライターとカウンター（番号付きマーカー）
- カラーピッカー、線幅調整、Undo/Redo
- **インライン編集モード** — 元のスクリーンショットを先に保存せず、範囲キャプチャをその場で注釈
- **スクリーンショット美化** — 背景色、余白、角丸、影

### OCR（文字認識）
- **Instant OCR** — 範囲選択後、テキストを即クリップボードへコピー
- **Visual OCR** — 認識領域をハイライト表示し、個別のテキストブロックを選択可能

### 翻訳
- **Capture & Translate** — 任意の画面範囲を選択し、OCR で文字を抽出して、翻訳結果をフローティングカードに表示
- **柔軟な言語設定** — 結果カードから翻訳先言語を変更し、カードを他のウィンドウの上に固定できます。Quick Access から直接翻訳することもできます

### スクリーンショット履歴
- **永続ライブラリ** — スクリーンショット、GIF、録画を 1 か所で閲覧
- **内蔵アクション** — フィルタ、コピー、保存、Finder で表示、削除を Capso 内で実行
- **保持期間の管理** — 履歴を自動保存し、保存期間を設定可能

### その他
- **Pin to Screen** — スクリーンショットを常に前面のウィンドウとして固定表示し、ロック/クリック透過にも対応
- **グローバルショートカット** — すべての操作を自由に設定可能
- **環境設定** — Apple Liquid Glass スタイルの包括的な設定画面
- **ローカライズ** — 英語、簡体字中国語、日本語、韓国語

### クラウド共有（オプション）
- **自前のストレージ** — あなた自身の Cloudflare R2 バケットに Capso をアップロードします。私たちはホスティングサービスを運営しません
- **ワンクリックでアップロード** — Quick Access のクラウドアイコンをクリック、または **⌥⇧0** ショートカットで撮影と共有を一度に完了
- **履歴との統合** — 履歴ウィンドウから過去の撮影をアップロード、または共有済みリンクをワンクリックでコピー
- **セットアップウィザード** — 環境設定 → クラウド共有で、約 5 分で R2 設定完了。「接続テスト」と「リセット」も対応
- **プロジェクトコストゼロ** — ファイル・ストレージ・料金、すべてあなたのもの（R2 は 10 GB 無料 + エグレス料金ゼロ）
- 今後対応予定: Backblaze B2、AWS S3、汎用 S3 互換ストレージ

<p align="center">
  <img src=".github/assets/annotation.jpeg" alt="注釈エディタ" width="600"><br>
  <em>描画ツール、カウンター、マーカーを備えた注釈エディタ</em>
</p>

<p align="center">
  <img src=".github/assets/beautify.jpeg" alt="スクリーンショット美化" width="600"><br>
  <em>背景、余白、角丸、影を使ったスクリーンショット美化</em>
</p>

<p align="center">
  <img src=".github/assets/recording-pip.jpeg" alt="Webcam PiP 付き画面録画" width="600"><br>
  <em>Webcam PiP と GIF/動画オプション付きの画面録画</em>
</p>

さらに多くのスクリーンショットや詳しい紹介は [**Capso 公式サイト →**](https://www.awesomemacapp.com/app/capso) をご覧ください。

---

## 比較

| | CleanShot X | Shottr | Cap | **Capso** |
|---|---|---|---|---|
| スクリーンショット | Full | Full | Basic | **Full** |
| オールインワン HUD | Yes | No | No | **Yes** |
| 録画 | Video + GIF | No | Video + GIF | **Video + GIF** |
| Webcam PiP | Yes | No | Yes | **Yes (4 shapes)** |
| OCR | Yes | Yes | No | **Yes** |
| 注釈 | Advanced | Advanced | Basic | **Advanced** |
| Pin to Screen | Yes | Yes | No | **Yes** |
| 美化 | Yes | No | Yes | **Yes** |
| ネイティブ Swift | Yes | Yes | No (Tauri) | **Yes (Swift 6)** |
| オープンソース | No | No | Partial | **Yes** |
| 価格 | $29 | $8 | $58 | **Free** |

---

## ソースからビルド

**必要環境:** Xcode 16+、macOS 15.0+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# XcodeGen をインストール
brew install xcodegen

# クローンしてビルド
git clone https://github.com/lzhgus/Capso.git
cd Capso
xcodegen generate
open Capso.xcodeproj
# Xcode で Cmd+R
```

コマンドラインからビルドすることもできます。

```bash
xcodegen generate
xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Release build
```

---

## アーキテクチャ

Capso はモジュール化された SPM（Swift Package Manager）構成を採用しています。アプリ本体は薄い SwiftUI + AppKit シェルで、主要機能は 12 個の独立したパッケージに分かれています。

```
Capso/
├── App/                     # メインアプリ（薄いシェル）
│   ├── CapsoApp.swift       # @main エントリポイント
│   ├── MenuBar/             # メニューバーコントローラ
│   ├── Capture/             # キャプチャオーバーレイ、オールインワン HUD、ピン留めスクリーンショット
│   ├── Recording/           # 録画コーディネータ、コントロール、ツールバー
│   ├── Editor/              # 録画エディタ、タイムライン、プレビュー、書き出し UI
│   ├── Camera/              # Webcam PiP ウィンドウ
│   ├── AnnotationEditor/    # 注釈エディタ、インライン注釈 + 美化
│   ├── OCR/                 # OCR コーディネータ、オーバーレイ、トースト
│   ├── Translation/         # キャプチャ翻訳フローと結果カード
│   ├── History/             # スクリーンショット履歴ウィンドウ
│   ├── QuickAccess/         # フローティングプレビュー
│   └── Preferences/         # 設定ウィンドウ
├── Packages/
│   ├── SharedKit/           # 設定、権限、ユーティリティ
│   ├── CaptureKit/          # ScreenCaptureKit ラッパー
│   ├── RecordingKit/        # 画面録画エンジン
│   ├── CameraKit/           # AVFoundation ベースのカメラキャプチャ
│   ├── AnnotationKit/       # 描画 / 注釈システム
│   ├── OCRKit/              # Vision ベースの OCR
│   ├── ExportKit/           # 動画 / GIF 書き出し + 録画エディタの合成書き出し
│   ├── EffectsKit/          # カーソルテレメトリ、クリックハイライト、エフェクト
│   ├── EditorKit/           # 録画エディタのモデル、コンポジタ、ズーム/カーソル処理
│   ├── HistoryKit/          # 永続化されたスクリーンショット / 録画履歴
│   ├── ShareKit/            # クラウド共有の送信先とアップロード
│   └── TranslationKit/      # OCR ベースの翻訳サービスモデル
└── project.yml              # XcodeGen プロジェクト定義
```

各パッケージは個別にテストできます。

```bash
swift test --package-path Packages/SharedKit
swift test --package-path Packages/AnnotationKit
# など
```

このパッケージ分割により、たとえば `CaptureKit` や `AnnotationKit` だけを自分のアプリに組み込むこともできます。Electron や Tauri ベースの代替製品では難しい構成です。

---

## ロードマップ

- スポットライト、拡大鏡、定規、画像オーバーレイなどの注釈ツール
- テキスト注釈での絵文字・カスタムフォント対応
- 自動化向け URL Scheme API
- Raycast / Shortcuts 連携

[オープン中の Issue](https://github.com/lzhgus/Capso/issues) で現在の優先事項を、[GitHub Releases](https://github.com/lzhgus/Capso/releases) でリリース履歴を確認できます。コントリビューション歓迎です。

---

## コントリビュート

開発環境やガイドラインについては [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

---

## ライセンス

Capso は [Business Source License 1.1](LICENSE) のもとで提供されています。

**要点:**

| やりたいこと | 可能? |
|---|---|
| 個人利用 | ✅ |
| 会社内での利用 | ✅ |
| ソースを読んで修正・ビルド | ✅ |
| Fork して無料の派生版を配布 | ✅ |
| Fork して競合する商用スクリーンキャプチャ製品を販売 | ❌ |
| 2029-04-08 以降のあらゆる利用 | ✅ Apache 2.0 に移行 |

各バージョンは公開から 3 年後に Apache 2.0 へ自動移行し、完全に寛容なオープンソースライセンスになります。

---

## サポート

- [バグを報告する](https://github.com/lzhgus/Capso/issues/new?template=bug_report.yml)
- [機能を提案する](https://github.com/lzhgus/Capso/issues/new?template=feature_request.yml)
- [X で @lzhgus をフォロー](https://x.com/lzhgus)して、リリース情報、開発の裏側、ほかの macOS ツールをチェック

Capso が作業時間を節約できたなら、ちょっとしたご支援が開発の糧になります。磨きをかけるほど、機能が増えるほど、バグが減るほどに。

<p align="center">
  <a href="https://x.com/lzhgus">
    <img src="https://img.shields.io/badge/Follow-@lzhgus-000000?style=for-the-badge&logo=x&logoColor=white" alt="Follow @lzhgus on X" />
  </a>
  &nbsp;
  <a href="https://github.com/sponsors/lzhgus">
    <img src="https://img.shields.io/badge/GitHub%20Sponsors-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor on GitHub" />
  </a>
  &nbsp;
  <a href="https://buymeacoffee.com/lzhgus">
    <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black" alt="Buy Me a Coffee" />
  </a>
</p>

<p align="center">
  <a href="https://www.awesomemacapp.com/">Awesome Mac Apps</a> により開発されています。ほかの macOS ツールもぜひご覧ください。
</p>
