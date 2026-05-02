<p align="right">
  <a href="README.md">English</a> | <strong>简体中文</strong> | <a href="README.ja.md">日本語</a> | <a href="README.ko.md">한국어</a>
</p>

# Capso

**开源的 macOS 截图与录屏工具**

一个免费、原生的 CleanShot X 替代品，使用 Swift 6.0 和 SwiftUI 构建，支持 macOS 15.0+。

[![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-blue)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![License: BSL 1.1](https://img.shields.io/badge/License-BSL%201.1-green.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/lzhgus/Capso?style=social)](https://github.com/lzhgus/Capso/stargazers)

<p align="center">
  <a href="https://www.producthunt.com/products/capso?embed=true&utm_source=badge-top-post-badge&utm_medium=badge&utm_campaign=badge-capso" target="_blank" rel="noopener noreferrer"><img alt="Capso - Free open-source screenshot &amp; screen recorder for Mac | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/top-post-badge.svg?post_id=1120330&theme=light&period=daily&t=1776201173308"></a>
</p>

<p align="center">
  <img src=".github/assets/hero.gif" alt="Capso 演示" width="720">
</p>

<p align="center">
  <a href="https://github.com/lzhgus/Capso/releases/latest"><strong>下载 &rarr;</strong></a> &nbsp;&bull;&nbsp;
  <a href="https://www.awesomemacapp.com/app/capso">官网</a> &nbsp;&bull;&nbsp;
  <a href="https://x.com/lzhgus">关注 @lzhgus</a> &nbsp;&bull;&nbsp;
  <a href="#功能特性">功能</a> &nbsp;&bull;&nbsp;
  <a href="#从源码构建">源码构建</a>
</p>

---

## 下载

从 [**GitHub Releases →**](https://github.com/lzhgus/Capso/releases/latest) 下载最新的签名公证版 DMG，开箱即用。

或通过 Homebrew 安装：

```bash
brew tap lzhgus/tap
brew install --cask capso
```

也可以[从源码构建](#从源码构建)。

> 首次使用时需要授予屏幕录制、摄像头和麦克风权限，App 会自动弹窗引导。

---

## 为什么要做这个？

市面上好用的 macOS 截图工具都需要付费，CleanShot X 卖 $29，Cap 要 $58。它们确实做得很好，但我们觉得截图录屏这样的基础功能，不应该被付费墙挡住。

所以我们做了 Capso：一个功能完整的免费替代品，完全开源。底层的 CaptureKit、AnnotationKit、OCRKit 等模块都是独立的 SPM 包，你完全可以拿去用在自己的项目里。

我们通过[其他产品](https://www.awesomemacapp.com/)赚钱，Capso 是我们送给 macOS 社区的礼物。也希望它能成为一个现代 Swift 6 模块化应用的参考。

欢迎大家来试用、提 issue、贡献代码，一起把它做得更好！

---

## 功能特性

### All-in-One 全能截图
- **CleanShot 风格截图 HUD**：在同一个浮动工具栏中选择区域、全屏、窗口、滚动、计时器、OCR 或录屏
- **可调整选区**：截图前可以拖拽移动、放大或缩小选区，周围变暗、选中区域保持明亮
- **比例与固定尺寸预设**：快速切换自由比例、1:1、4:3、16:9 以及自定义固定像素尺寸
- **原位标注**：直接在截取区域上添加箭头、形状、文字、荧光笔和马赛克，最后再保存或复制

### 截图
- **区域截图**：拖拽选择，实时显示尺寸；按 **R** 键切换宽高比与固定尺寸预设（1:1、16:9、1920×1080、自定义）
- **全屏截图**：一键捕获整个屏幕
- **窗口截图**：点击任意窗口即可捕获
- **滚动截图**：将长网页、聊天记录、文档内容拼接成一张完整长图
- **快速操作**：浮动预览窗口，支持复制、保存、标注、OCR、钉住、拖放

### 录屏
- **视频（MP4）和 GIF** 两种格式录制
- **摄像头画中画**：4 种形状（圆形、方形、竖屏、横屏），可拖动调整大小，自动吸附角落
- **摄像头演示模式**：点击画中画全屏展示，再点击恢复
- **系统音频 + 麦克风**同时录制
- **录制控制**：暂停、停止、重新开始、删除、计时器
- **倒计时提示**：录制前 3-2-1 倒计时
- **导出质量预设**：最高画质、社交媒体、网页三挡可选
- **录屏编辑器**：在一个流程里完成裁剪、缩放建议、光标平滑、背景样式和 MP4/GIF 导出
- **实时合成预览**：导出前即可预览缩放、光标和背景效果

### 标注编辑器
- 箭头、矩形、椭圆、文字、自由绘制、马赛克/模糊、裁剪
- 荧光笔和计数器（编号标记）工具
- 颜色选择器、描边控制、撤销/重做
- **原位编辑模式**：区域截图后可以直接在原位置标注，不需要先保存原始截图
- **截图美化**：背景色、内边距、圆角、阴影，一键出图

### OCR 文字识别
- **即时 OCR**：选择区域后文字自动复制到剪贴板
- **可视化 OCR**：高亮显示识别区域，点击选择单个文本块

### 截图翻译
- **截图并翻译**：选择任意屏幕区域，先用 OCR 提取文字，再用系统翻译显示结果
- **灵活的语言控制**：在结果卡片中切换目标语言、将卡片钉在其他窗口上方，也可以从快速操作里直接翻译

### 截图历史
- **持久化记录**：在一个窗口中统一浏览截图、GIF 和录屏记录
- **内置快捷操作**：支持筛选、复制、保存、在 Finder 中显示、删除
- **保留策略控制**：可自动保存历史，并设置记录保留时长

### 更多
- **钉到屏幕**：将截图悬浮为置顶窗口，支持锁定和穿透点击模式
- **全局快捷键**：所有操作都可以自定义快捷键
- **偏好设置**：全面的设置面板，Apple Liquid Glass 风格
- **多语言支持**：英文、简体中文、日语、韩语

### 云端分享（可选）
- **自带存储** — 让 Capso 上传到你自己的 Cloudflare R2 桶，我们从不运营托管服务
- **一键上传** — 截图后点击 Quick Access 中的云图标，或用 **⌥⇧0** 快捷键一步完成"截图并分享"
- **历史记录集成** — 在历史窗口中可以上传旧截图，或一键复制任意已分享过的链接
- **设置向导** —— 偏好设置 → 云端分享，约 5 分钟完成 R2 配置，自带"测试连接"和"重置配置"
- **零项目成本** — 文件归你，存储归你，账单归你（R2 提供 10 GB 免费额度 + 零出口流量费）
- 即将支持：Backblaze B2、AWS S3、通用 S3 兼容存储

<p align="center">
  <img src=".github/assets/annotation.jpeg" alt="标注编辑器" width="600"><br>
  <em>标注编辑器：绘图工具、计数器和标记</em>
</p>

<p align="center">
  <img src=".github/assets/beautify.jpeg" alt="截图美化" width="600"><br>
  <em>截图美化：背景、内边距、圆角、阴影</em>
</p>

<p align="center">
  <img src=".github/assets/recording-pip.jpeg" alt="摄像头画中画录屏" width="600"><br>
  <em>录屏 + 摄像头画中画 + GIF/视频选项</em>
</p>

更多截图请访问 [**Capso 官网 →**](https://www.awesomemacapp.com/app/capso)

---

## 功能对比

| | CleanShot X | Shottr | Cap | **Capso** |
|---|---|---|---|---|
| 截图 | 完整 | 完整 | 基础 | **完整** |
| All-in-One HUD | 有 | 无 | 无 | **有** |
| 录屏 | 视频 + GIF | 无 | 视频 + GIF | **视频 + GIF** |
| 摄像头画中画 | 有 | 无 | 有 | **有（4 种形状）** |
| OCR | 有 | 有 | 无 | **有** |
| 标注 | 高级 | 高级 | 基础 | **高级** |
| 钉到屏幕 | 有 | 有 | 无 | **有** |
| 截图美化 | 有 | 无 | 有 | **有** |
| 原生 Swift | 是 | 是 | 否（Tauri） | **是（Swift 6）** |
| 开源 | 否 | 否 | 部分 | **是** |
| 价格 | $29 | $8 | $58 | **免费** |

---

## 从源码构建

**环境要求：** Xcode 16+、macOS 15.0+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# 安装 XcodeGen
brew install xcodegen

# 克隆并构建
git clone https://github.com/lzhgus/Capso.git
cd Capso
xcodegen generate
open Capso.xcodeproj
# 在 Xcode 中运行 Cmd+R
```

也可以通过命令行构建：

```bash
xcodegen generate
xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Release build
```

---

## 架构

Capso 采用模块化的 SPM 架构。App 本身是一个很薄的 SwiftUI + AppKit 壳层，核心能力分布在 12 个独立的包中。

```
Capso/
├── App/                     # 主 App（薄壳层）
│   ├── CapsoApp.swift       # @main 入口
│   ├── MenuBar/             # 菜单栏
│   ├── Capture/             # 截图、All-in-One HUD、钉到屏幕
│   ├── Recording/           # 录屏
│   ├── Editor/              # 录屏编辑器、时间线、预览、导出 UI
│   ├── Camera/              # 摄像头画中画
│   ├── AnnotationEditor/    # 标注编辑器、原位标注 + 美化
│   ├── OCR/                 # 文字识别
│   ├── Translation/         # 截图翻译流程与结果卡片
│   ├── History/             # 截图历史窗口
│   ├── QuickAccess/         # 快速操作浮窗
│   └── Preferences/         # 设置
├── Packages/
│   ├── SharedKit/           # 设置、权限、工具类
│   ├── CaptureKit/          # ScreenCaptureKit 封装
│   ├── RecordingKit/        # 录屏引擎
│   ├── CameraKit/           # AVFoundation 摄像头
│   ├── AnnotationKit/       # 绘制/标注系统
│   ├── OCRKit/              # Vision 框架 OCR
│   ├── ExportKit/           # 视频/GIF 导出 + 录屏编辑器合成导出
│   ├── EffectsKit/          # 光标遥测、点击高亮、特效
│   ├── EditorKit/           # 录屏编辑器模型、合成器、缩放/光标逻辑
│   ├── HistoryKit/          # 持久化截图/录屏历史
│   ├── ShareKit/            # 云端分享目标与上传
│   └── TranslationKit/      # 基于 OCR 的翻译服务模型
└── project.yml              # XcodeGen 项目定义
```

每个包可以独立测试：

```bash
swift test --package-path Packages/SharedKit
swift test --package-path Packages/AnnotationKit
# ...
```

这种模块化设计意味着你可以把 `CaptureKit` 或 `AnnotationKit` 单独嵌入自己的 App 里，不需要依赖整个 Capso。这是 Electron 和 Tauri 方案做不到的。

---

## 路线图

- 聚光灯、放大镜、标尺、图片叠加等标注工具
- 文字标注支持 Emoji 和自定义字体
- URL Scheme API
- Raycast / 快捷指令集成

查看 [Issues](https://github.com/lzhgus/Capso/issues) 了解当前进展，查看 [GitHub Releases](https://github.com/lzhgus/Capso/releases) 了解版本历史。非常欢迎 PR 和建议！

---

## 参与贡献

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

无论是修个 typo 还是贡献一个新功能，我们都非常欢迎。如果你有任何想法，开个 issue 聊一聊就好。

---

## 许可证

Capso 采用 [Business Source License 1.1](LICENSE) 许可。

**简单来说：**

| 你想做的事 | 可以吗？ |
|---|---|
| 个人使用 | ✅ |
| 公司内部使用 | ✅ |
| 阅读、修改、从源码构建 | ✅ |
| Fork 后发布免费版 | ✅ |
| Fork 后做成商业截图产品出售 | ❌ |
| 2029-04-08 之后的任何用途 | ✅ 转为 Apache 2.0 |

每个版本在发布三年后都会自动转为 Apache 2.0 开源许可。

---

## 支持我们

- [报告 Bug](https://github.com/lzhgus/Capso/issues/new?template=bug_report.yml)
- [功能建议](https://github.com/lzhgus/Capso/issues/new?template=feature_request.yml)
- [在 X 上关注 @lzhgus](https://x.com/lzhgus)，获取版本更新、开发幕后和更多 macOS 工具

如果 Capso 为你节省了时间，一点小小的支持就能让它持续打磨 — 更多细节，更多功能，更少 Bug。

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
  由 <a href="https://www.awesomemacapp.com/">Awesome Mac Apps</a> 出品，欢迎了解我们的其他 macOS 工具。
</p>
