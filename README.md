# ffmpeg-audio-build

用于构建音频专用版 `ffmpeg` / `ffprobe` 的 GitHub Actions 仓库。

当前目标：

- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `x86_64-unknown-linux-gnu`
- `aarch64-unknown-linux-gnu`
- `x86_64-pc-windows-msvc`
- `aarch64-pc-windows-msvc`

目标特性：

- 仅保留音频相关能力
- 第三方音频依赖静态链接
- 构建产物运行时不依赖第三方动态库
- 每个目标在对应平台 runner 上自动校验

当前 workflows：

- `.github/workflows/build-audio-mac-arm64.yml`
- `.github/workflows/build-audio-mac-x86_64.yml`
- `.github/workflows/build-audio-linux-x86_64.yml`
- `.github/workflows/build-audio-linux-aarch64.yml`
- `.github/workflows/build-audio-windows-x86_64.yml`
- `.github/workflows/build-audio-windows-aarch64.yml`

内部复用 workflow：

- `.github/workflows/reusable-build-audio-target.yml`

触发方式：

1. 打开 GitHub Actions
2. 选择对应目标 triple 的 workflow
3. 手动触发 `workflow_dispatch`
4. 默认构建 `FFmpeg n8.1`

产物内容：

- `ffmpeg` 或 `ffmpeg.exe`
- `ffprobe` 或 `ffprobe.exe`
- `BUILD_INFO.txt`
- `CONFIGURE_ARGS.txt`

校验内容：

- 检查二进制架构和最低系统版本
- 检查是否仍然依赖第三方动态库
- 检查 `ffmpeg` / `ffprobe` 是否能正常启动
- 验证音频转码：
  `wav -> mp3`
  `wav -> m4a`
  `m4a -> mp3`
- 验证音频截取：
  `wav -> clip.wav`，并校验裁剪后时长

说明：

- macOS / Linux 目标会先从源码静态编译 `lame / libogg / libvorbis / opus`，再构建 `ffmpeg / ffprobe`。
- Windows 目标会使用 MSVC 工具链和静态依赖前缀来构建，校验运行时不引入第三方 DLL。
- 目标是保持“音频转码 + 音频截取”可用，而不是构建通用多媒体全功能版 FFmpeg。
- `m4a` 输入依赖 `mov` demuxer，`m4a` 输出使用 `ipod` muxer。
