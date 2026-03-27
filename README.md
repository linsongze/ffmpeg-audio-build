# ffmpeg-audio-build

用于构建音频专用版 `ffmpeg` / `ffprobe` 的 GitHub Actions 仓库。

当前目标：

- 先支持 `macOS arm64`
- 仅保留音频相关能力
- 明确关闭视频相关构建项
- 产出可直接下载的 artifact

当前 workflow：

- `.github/workflows/build-audio-mac-arm64.yml`

触发方式：

1. 打开 GitHub Actions
2. 选择 `build-audio-mac-arm64`
3. 手动触发 `workflow_dispatch`
4. 默认构建 `FFmpeg n8.1`

产物内容：

- `ffmpeg`
- `ffprobe`
- `BUILD_INFO.txt`
- `CONFIGURE_ARGS.txt`

说明：

- 当前配置优先保证“音频专用”和“可维护”，不是盲目追求最小体积。
- 为了支持 `mp3 / ogg / opus` 等常见音频能力，workflow 会安装 `lame / opus / libvorbis`。
- `m4a` 输入依赖 `mov` demuxer，`m4a` 输出使用 `ipod` muxer。
