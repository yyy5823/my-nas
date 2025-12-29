# FFmpeg for Windows

此目录用于存放 FFmpeg 静态编译版本，用于 Windows 客户端视频转码。

## 下载 FFmpeg

1. 访问 https://www.gyan.dev/ffmpeg/builds/
2. 下载 `ffmpeg-release-essentials.zip`（约 80MB）
3. 解压后，将 `bin` 目录下的以下文件复制到此目录：
   - `ffmpeg.exe`（必需）
   - `ffprobe.exe`（可选，用于探测媒体信息）

## 目录结构

```
windows/ffmpeg/
├── README.md      (本文件)
├── ffmpeg.exe     (FFmpeg 主程序)
└── ffprobe.exe    (可选)
```

## 注意事项

- FFmpeg 二进制文件（.exe）已在 .gitignore 中排除，不会提交到仓库
- 构建时 CMake 会自动将此目录的内容复制到应用目录
- 如果此目录为空，应用会尝试使用系统 PATH 中的 FFmpeg
