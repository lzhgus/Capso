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

### 截图
- **区域截图**：拖拽选择，实时显示尺寸
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

### 标注编辑器
- 箭头、矩形、椭圆、文字、自由绘制、马赛克/模糊、裁剪
- 荧光笔和计数器（编号标记）工具
- 颜色选择器、描边控制、撤销/重做
- **截图美化**：背景色、内边距、圆角、阴影，一键出图

### OCR 文字识别
- **即时 OCR**：选择区域后文字自动复制到剪贴板
- **可视化 OCR**：高亮显示识别区域，点击选择单个文本块

### 截图历史
- **持久化记录**：在一个窗口中统一浏览截图、GIF 和录屏记录
- **内置快捷操作**：支持筛选、复制、保存、在 Finder 中显示、删除
- **保留策略控制**：可自动保存历史，并设置记录保留时长

### 更多
- **钉到屏幕**：将截图悬浮为置顶窗口，支持锁定和穿透点击模式
- **全局快捷键**：所有操作都可以自定义快捷键
- **偏好设置**：全面的设置面板，Apple Liquid Glass 风格
- **多语言支持**：英文、简体中文、日语、韩语

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

Capso 采用模块化的 SPM 架构。App 本身是一个很薄的 SwiftUI + AppKit 壳层，核心能力分布在 9 个独立的包中。

```
Capso/
├── App/                     # 主 App（薄壳层）
│   ├── CapsoApp.swift       # @main 入口
│   ├── MenuBar/             # 菜单栏
│   ├── Capture/             # 截图
│   ├── Recording/           # 录屏
│   ├── Camera/              # 摄像头画中画
│   ├── AnnotationEditor/    # 标注编辑器 + 美化
│   ├── OCR/                 # 文字识别
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
│   ├── ExportKit/           # 视频/GIF/图片导出
│   ├── EffectsKit/          # 光标特效
│   └── HistoryKit/          # 持久化截图/录屏历史
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
- 视频剪辑编辑器
- 光标平滑（弹簧物理）
- 录制视频的缩放动画
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
- [GitHub Sponsors](https://github.com/sponsors/lzhgus)：如果 Capso 对你有帮助，一杯咖啡的支持就是最大的鼓励

由 [Awesome Mac Apps](https://www.awesomemacapp.com/) 出品，欢迎了解我们的其他 macOS 工具。
