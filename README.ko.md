<p align="right">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | <a href="README.ja.md">日本語</a> | <strong>한국어</strong>
</p>

# Capso

**macOS를 위한 오픈소스 스크린샷 및 화면 녹화 도구**

Swift 6.0과 SwiftUI로 만든 무료 네이티브 CleanShot X 대안입니다. macOS 15.0 이상을 지원합니다.

[![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-blue)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![License: BSL 1.1](https://img.shields.io/badge/License-BSL%201.1-green.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/lzhgus/Capso?style=social)](https://github.com/lzhgus/Capso/stargazers)

<p align="center">
  <a href="https://www.producthunt.com/products/capso?embed=true&utm_source=badge-top-post-badge&utm_medium=badge&utm_campaign=badge-capso" target="_blank" rel="noopener noreferrer"><img alt="Capso - Free open-source screenshot &amp; screen recorder for Mac | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/top-post-badge.svg?post_id=1120330&theme=light&period=daily&t=1776201173308"></a>
</p>

<p align="center">
  <img src=".github/assets/hero.gif" alt="Capso 데모" width="720">
</p>

<p align="center">
  <a href="https://github.com/lzhgus/Capso/releases/latest"><strong>다운로드 &rarr;</strong></a> &nbsp;&bull;&nbsp;
  <a href="https://www.awesomemacapp.com/app/capso">웹사이트</a> &nbsp;&bull;&nbsp;
  <a href="https://x.com/lzhgus">@lzhgus 팔로우</a> &nbsp;&bull;&nbsp;
  <a href="#기능">기능</a> &nbsp;&bull;&nbsp;
  <a href="#소스에서-빌드하기">소스에서 빌드하기</a>
</p>

---

## 다운로드

[**GitHub Releases →**](https://github.com/lzhgus/Capso/releases/latest) 에서 최신 서명 및 공증 완료 DMG를 내려받을 수 있습니다.

또는 Homebrew로 설치할 수 있습니다.

```bash
brew tap lzhgus/tap
brew install --cask capso
```

또는 [소스에서 직접 빌드](#소스에서-빌드하기) 할 수 있습니다.

> 화면 녹화, 카메라, 마이크 권한이 필요합니다. 처음 사용할 때 앱이 안내합니다.

---

## 왜 오픈소스인가요?

쓸 만한 macOS 스크린샷 도구는 대부분 유료입니다. CleanShot X는 $29, Cap은 $58입니다. 둘 다 훌륭한 앱이지만, 이런 핵심 생산성 기능이 꼭 유료여야 할 이유는 없다고 생각했습니다.

Capso는 그에 대한 우리의 답입니다. **완전한 네이티브 경험과 풍부한 기능을 제공하는 무료 대안**이며, 공개적으로 개발됩니다. CaptureKit, AnnotationKit, OCRKit 같은 핵심 기능은 독립적인 SPM 패키지로 구성되어 있어 여러분의 앱에도 그대로 가져다 쓸 수 있습니다.

우리는 [다른 도구들](https://www.awesomemacapp.com/) 로 수익을 얻고 있습니다. Capso는 macOS 커뮤니티에 대한 환원이자, 현대적인 Swift 6 모듈형 앱이 어떤 모습일 수 있는지 보여주는 예시입니다.

---

## 기능

### 올인원 캡처
- **CleanShot 스타일 캡처 HUD** — 하나의 플로팅 툴바에서 영역, 전체 화면, 윈도우, 스크롤, 타이머, OCR, 녹화를 선택
- **조정 가능한 선택 영역** — 확정하기 전에 캡처 영역을 이동하거나 리사이즈하고, 주변은 어둡게 선택 영역은 밝게 표시
- **화면 비율 및 고정 크기 프리셋** — Freeform, 1:1, 4:3, 16:9, 사용자 지정 고정 픽셀 크기를 빠르게 전환
- **인라인 주석** — 저장 또는 복사하기 전에 캡처 영역 위에 화살표, 도형, 텍스트, 하이라이트, 픽셀화를 바로 추가

### 스크린샷
- **영역 캡처** — 드래그로 영역 선택, 크기 실시간 표시. **R** 키로 화면 비율과 고정 크기 프리셋(1:1, 16:9, 1920×1080, 사용자 지정) 전환
- **전체 화면 캡처** — 한 번의 클릭으로 전체 화면 캡처
- **윈도우 캡처** — 원하는 윈도우를 클릭해 캡처
- **스크롤 캡처** — 긴 웹페이지, 채팅 스레드, 문서를 한 장의 이미지로 이어 붙이기
- **Quick Access** — 복사, 저장, 주석, OCR, 핀 고정, 드래그 앤 드롭을 지원하는 플로팅 미리보기

### 화면 녹화
- **비디오(MP4)** 및 **GIF** 녹화
- **웹캠 PiP** — 4가지 형태(원형, 사각형, 세로형, 가로형), 드래그 리사이즈, 모서리 스냅
- **카메라 프레젠테이션 모드** — PiP를 클릭해 전체 화면으로 확장하고 다시 클릭해 복원
- **시스템 오디오 + 마이크** 동시 녹음
- **녹화 컨트롤** — 일시정지, 정지, 다시 시작, 삭제, 타이머
- **카운트다운 오버레이** — 녹화 시작 전 3-2-1 카운트다운
- **내보내기 품질 프리셋** — Maximum, Social, Web
- **녹화 편집기** — 트림, 줌 제안, 커서 스무딩, 배경 스타일, MP4/GIF 내보내기를 하나의 흐름에서 처리
- **실시간 합성 미리보기** — 내보내기 전에 줌, 커서, 배경 변경 결과를 바로 확인

### 주석 편집기
- 화살표, 사각형, 타원, 텍스트, 자유 그리기, 픽셀화/블러, 자르기
- 하이라이터와 카운터(번호 마커) 도구
- 색상 선택기, 선 두께 조절, 실행 취소/다시 실행
- **인라인 편집 모드** — 원본 스크린샷을 먼저 저장하지 않고 영역 캡처 위에 바로 주석 추가
- **스크린샷 꾸미기** — 배경색, 여백, 둥근 모서리, 그림자

### OCR(텍스트 인식)
- **Instant OCR** — 영역 선택 후 텍스트를 즉시 클립보드로 복사
- **Visual OCR** — 인식된 텍스트 영역을 하이라이트하고 개별 블록을 선택 가능

### 번역
- **Capture & Translate** — 원하는 화면 영역을 선택하고 OCR로 텍스트를 추출한 뒤 번역 결과를 플로팅 카드로 표시
- **유연한 언어 설정** — 결과 카드에서 대상 언어를 바꾸고, 카드를 다른 창 위에 고정하거나 Quick Access에서 바로 번역 가능

### 스크린샷 히스토리
- **영구 라이브러리** — 스크린샷, GIF, 녹화본을 한 곳에서 탐색
- **내장 액션** — 필터링, 복사, 저장, Finder에서 보기, 삭제를 Capso 안에서 바로 수행
- **보관 정책 제어** — 히스토리를 자동 저장하고 보관 기간을 설정 가능

### 기타
- **Pin to Screen** — 스크린샷을 항상 위에 떠 있는 창으로 고정하고 잠금/클릭 통과도 지원
- **전역 단축키** — 모든 작업을 자유롭게 설정 가능
- **환경설정** — Apple Liquid Glass 스타일의 종합 설정 화면
- **현지화** — 영어, 중국어 간체, 일본어, 한국어

### 클라우드 공유 (선택)
- **자체 저장소 사용** — 자신의 Cloudflare R2 버킷에 Capso가 업로드합니다. 호스팅 서비스를 운영하지 않습니다
- **원클릭 업로드** — Quick Access의 클라우드 아이콘 클릭, 또는 **⌥⇧0** 단축키로 캡처와 공유를 한 번에
- **히스토리 통합** — 히스토리 창에서 과거 캡처를 업로드하거나 이미 공유된 링크를 원클릭으로 복사
- **설정 마법사** — 환경설정 → 클라우드 공유에서 약 5분 만에 R2 구성, "연결 테스트"와 "재설정" 포함
- **프로젝트 비용 제로** — 파일도 저장소도 청구서도 모두 사용자 소유 (R2는 10 GB 무료 + 송신 수수료 0원)
- 향후 지원 예정: Backblaze B2, AWS S3, 일반 S3 호환 스토리지

<p align="center">
  <img src=".github/assets/annotation.jpeg" alt="주석 편집기" width="600"><br>
  <em>그리기 도구, 카운터, 마커를 갖춘 주석 편집기</em>
</p>

<p align="center">
  <img src=".github/assets/beautify.jpeg" alt="스크린샷 꾸미기" width="600"><br>
  <em>배경, 여백, 모서리, 그림자를 이용한 스크린샷 꾸미기</em>
</p>

<p align="center">
  <img src=".github/assets/recording-pip.jpeg" alt="웹캠 PiP 화면 녹화" width="600"><br>
  <em>웹캠 PiP와 GIF/비디오 옵션을 지원하는 화면 녹화</em>
</p>

더 많은 스크린샷과 전체 소개는 [**Capso 웹사이트 →**](https://www.awesomemacapp.com/app/capso) 에서 확인할 수 있습니다.

---

## 비교

| | CleanShot X | Shottr | Cap | **Capso** |
|---|---|---|---|---|
| 스크린샷 | Full | Full | Basic | **Full** |
| 올인원 HUD | Yes | No | No | **Yes** |
| 녹화 | Video + GIF | No | Video + GIF | **Video + GIF** |
| Webcam PiP | Yes | No | Yes | **Yes (4 shapes)** |
| OCR | Yes | Yes | No | **Yes** |
| 주석 | Advanced | Advanced | Basic | **Advanced** |
| Pin to Screen | Yes | Yes | No | **Yes** |
| 꾸미기 | Yes | No | Yes | **Yes** |
| 네이티브 Swift | Yes | Yes | No (Tauri) | **Yes (Swift 6)** |
| 오픈소스 | No | No | Partial | **Yes** |
| 가격 | $29 | $8 | $58 | **Free** |

---

## 소스에서 빌드하기

**요구 사항:** Xcode 16+, macOS 15.0+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# XcodeGen 설치
brew install xcodegen

# 클론 후 빌드
git clone https://github.com/lzhgus/Capso.git
cd Capso
xcodegen generate
open Capso.xcodeproj
# Xcode에서 Cmd+R
```

명령줄에서도 빌드할 수 있습니다.

```bash
xcodegen generate
xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Release build
```

---

## 아키텍처

Capso는 모듈형 SPM(Swift Package Manager) 아키텍처를 사용합니다. 앱 자체는 얇은 SwiftUI + AppKit 셸이고, 핵심 기능은 12개의 독립 패키지에 들어 있습니다.

```
Capso/
├── App/                     # 메인 앱 타깃(얇은 셸)
│   ├── CapsoApp.swift       # @main 엔트리 포인트
│   ├── MenuBar/             # 메뉴바 컨트롤러
│   ├── Capture/             # 캡처 오버레이, 올인원 HUD, 핀 고정 스크린샷
│   ├── Recording/           # 녹화 코디네이터, 컨트롤, 툴바
│   ├── Editor/              # 녹화 편집기, 타임라인, 미리보기, 내보내기 UI
│   ├── Camera/              # 웹캠 PiP 창
│   ├── AnnotationEditor/    # 주석 편집기, 인라인 주석 + 꾸미기
│   ├── OCR/                 # OCR 코디네이터, 오버레이, 토스트
│   ├── Translation/         # 캡처 번역 흐름과 결과 카드
│   ├── History/             # 스크린샷 히스토리 창
│   ├── QuickAccess/         # 플로팅 미리보기 창
│   └── Preferences/         # 설정 창
├── Packages/
│   ├── SharedKit/           # 설정, 권한, 유틸리티
│   ├── CaptureKit/          # ScreenCaptureKit 래퍼
│   ├── RecordingKit/        # 화면 녹화 엔진
│   ├── CameraKit/           # AVFoundation 웹캠 캡처
│   ├── AnnotationKit/       # 그리기/주석 시스템
│   ├── OCRKit/              # Vision 기반 OCR
│   ├── ExportKit/           # 비디오/GIF 내보내기 + 녹화 편집기 합성 내보내기
│   ├── EffectsKit/          # 커서 텔레메트리, 클릭 하이라이트, 효과
│   ├── EditorKit/           # 녹화 편집기 모델, 컴포지터, 줌/커서 로직
│   ├── HistoryKit/          # 영구 스크린샷/녹화 히스토리
│   ├── ShareKit/            # 클라우드 공유 대상과 업로드
│   └── TranslationKit/      # OCR 기반 번역 서비스 모델
└── project.yml              # XcodeGen 프로젝트 정의
```

각 패키지는 독립적으로 테스트할 수 있습니다.

```bash
swift test --package-path Packages/SharedKit
swift test --package-path Packages/AnnotationKit
# 등등
```

이런 패키지 분리는 `CaptureKit`이나 `AnnotationKit`만 별도로 여러분의 앱에 넣을 수 있게 해 줍니다. 이는 Electron이나 Tauri 기반 대안과 차별화되는 점입니다.

---

## 로드맵

- 스포트라이트, 돋보기, 자, 이미지 오버레이 등 추가 주석 도구
- 텍스트 주석에서 이모지와 사용자 지정 폰트 지원
- 자동화를 위한 URL 스킴 API
- Raycast / Shortcuts 연동

[오픈 이슈](https://github.com/lzhgus/Capso/issues) 에서 현재 우선순위를, [GitHub Releases](https://github.com/lzhgus/Capso/releases) 에서 버전 히스토리를 확인할 수 있습니다. 기여를 환영합니다.

---

## 기여하기

개발 환경과 가이드라인은 [CONTRIBUTING.md](CONTRIBUTING.md) 를 참고하세요.

---

## 라이선스

Capso는 [Business Source License 1.1](LICENSE) 로 배포됩니다.

**요약:**

| 하고 싶은 일 | 가능 여부 |
|---|---|
| 개인적으로 사용 | ✅ |
| 회사 내부에서 사용 | ✅ |
| 소스를 읽고 수정하고 빌드 | ✅ |
| 포크해서 무료 파생판 배포 | ✅ |
| 포크해서 경쟁 상용 캡처 제품 판매 | ❌ |
| 2029-04-08 이후 모든 사용 | ✅ Apache 2.0으로 전환 |

각 버전은 공개 후 3년이 지나면 Apache 2.0으로 자동 전환되어 완전한 퍼미시브 오픈소스가 됩니다.

---

## 지원

- [버그 신고](https://github.com/lzhgus/Capso/issues/new?template=bug_report.yml)
- [기능 요청](https://github.com/lzhgus/Capso/issues/new?template=feature_request.yml)
- [X에서 @lzhgus 팔로우](https://x.com/lzhgus)하고 릴리스 소식, 개발 비하인드, 다른 macOS 도구를 확인하세요

Capso가 시간을 아껴줬다면, 작은 후원이 개발의 큰 힘이 됩니다 — 더 많은 다듬음, 더 많은 기능, 더 적은 버그로 이어집니다.

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
  <a href="https://www.awesomemacapp.com/">Awesome Mac Apps</a> 에서 만들었습니다. 다른 macOS 도구도 확인해 보세요.
</p>
