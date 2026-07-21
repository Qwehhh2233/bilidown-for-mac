<p align="center">
  <img src="assets/AppIcon.png" width="128" alt="Bilidown for Mac 图标">
</p>

# Bilidown for Mac

Bilidown for Mac 是基于 [iuroc/bilidown](https://github.com/iuroc/bilidown) 后端制作的原生 macOS 客户端。界面使用 SwiftUI 重写，保留视频解析、分集选择、下载任务、登录状态和下载目录管理等功能，并针对 macOS 的窗口、程序坞、菜单栏和文件选择体验进行了适配。

## 功能

- 原生 SwiftUI 界面，支持浅色、深色及跟随系统
- 支持 BV、EP、SS、b23.tv、合集和收藏夹链接
- 视频、音频及音视频合并下载
- 下载中与已完成任务分类
- 原生文件夹选择、文件定位和视频预览
- 哔哩哔哩扫码登录及用户信息展示
- 菜单栏显示登录状态与下载进度
- Apple Silicon 原生运行

## 下载与安装

1. 从 [Releases](https://github.com/Qwehhh2233/bilidown-for-mac/releases) 下载最新版 `Bilidown.app.zip`。
2. 解压后将 `Bilidown.app` 拖入“应用程序”。
3. 安装 FFmpeg：

   ```bash
   brew install ffmpeg
   ```

4. 如果 macOS 阻止首次启动，可在“系统设置 → 隐私与安全性”中选择仍要打开。

当前发布包使用临时代码签名，尚未进行 Apple Developer ID 签名与公证。

## 从源码构建

需要：

- macOS 13 或更高版本
- Apple Silicon Mac
- Xcode Command Line Tools
- Go 1.23 或更高版本
- FFmpeg

执行：

```bash
git clone https://github.com/Qwehhh2233/bilidown-for-mac.git
cd bilidown-for-mac
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

构建结果位于 `build/Bilidown.app` 和 `build/Bilidown.app.zip`。

## 项目结构

```text
native/       SwiftUI 原生前端
backend/      Bilidown Go 后端及 API
packaging/    macOS App 元数据与辅助资源
assets/       应用图标
scripts/      构建与打包脚本
```

## 数据位置

应用数据默认保存在：

```text
~/Library/Application Support/Bilidown
```

视频下载位置可在应用设置中修改。

## 上游项目与许可证

后端源自 [iuroc/bilidown](https://github.com/iuroc/bilidown)，原项目由 iuroc 开发并以 Apache License 2.0 发布。本仓库保留原许可证和署名，并在其基础上加入原生 macOS 前端、后台运行模式、文件处理与 macOS 集成功能。详情见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。

本项目与哔哩哔哩官方无关。请仅下载你有权保存的内容，并遵守当地法律、平台服务条款及著作权规定。
