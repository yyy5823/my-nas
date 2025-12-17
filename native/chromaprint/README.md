# Chromaprint 音频指纹集成指南

音纹识别功能使用 Chromaprint 库生成音频指纹，通过 AcoustID 服务识别音乐。

## 平台支持

| 平台 | 方案 | 状态 |
|------|------|------|
| macOS | fpcalc 命令行工具 | ✅ 完整支持 |
| Windows | fpcalc.exe | ✅ 完整支持 |
| Linux | fpcalc | ✅ 完整支持 |
| Android | 原生库 (JNI) | ⚠️ 需编译 |
| iOS | 原生框架 | ⚠️ 需编译 |

---

## 桌面端集成

### 方式 1: 用户手动安装 (开发阶段)

#### macOS
```bash
brew install chromaprint
```

#### Windows
1. 下载 https://acoustid.org/chromaprint
2. 解压 `fpcalc.exe` 到 `C:\fpcalc\` 或添加到 PATH

#### Linux
```bash
# Ubuntu/Debian
sudo apt install libchromaprint-tools

# Fedora
sudo dnf install chromaprint-tools

# Arch
sudo pacman -S chromaprint
```

验证安装：
```bash
fpcalc -version
```

### 方式 2: 打包到应用中 (发布阶段)

使用提供的脚本自动下载并打包：

```bash
# 下载所有平台的 fpcalc
./native/chromaprint/bundle_fpcalc.sh all

# 安装到项目中
./native/chromaprint/bundle_fpcalc.sh install
```

这会将 fpcalc 放到：
- **macOS**: `macos/Runner/Resources/fpcalc`
- **Windows**: `windows/runner/data/fpcalc.exe`
- **Linux**: `linux/data/fpcalc`

构建应用时会自动打包这些文件。

---

## 移动端集成

移动端需要编译 Chromaprint 原生库。详见 [build_mobile.md](./build_mobile.md)。

### Android

1. 将预编译的 `.so` 放入 `android/app/src/main/jniLibs/`:
   ```
   jniLibs/
   ├── arm64-v8a/libchromaprint.so
   ├── armeabi-v7a/libchromaprint.so
   └── x86_64/libchromaprint.so
   ```

2. 在 `build.gradle` 启用 CMake：
   ```groovy
   android {
       externalNativeBuild {
           cmake {
               path "src/main/cpp/CMakeLists.txt"
           }
       }
   }
   ```

### iOS

1. 编译 `Chromaprint.xcframework`
2. 添加到 Xcode 项目
3. 创建 Bridging Header 导入头文件
4. 添加编译标志 `-DCHROMAPRINT_AVAILABLE`

---

## 文件结构

```
native/chromaprint/
├── README.md              # 本文件
├── build_mobile.md        # 移动端编译指南
├── bundle_fpcalc.sh       # 桌面端打包脚本
├── binaries/              # 下载的二进制文件 (gitignore)
│   ├── macos/fpcalc
│   ├── windows/fpcalc.exe
│   └── linux/fpcalc
└── downloads/             # 临时下载目录 (gitignore)

android/app/src/main/
├── kotlin/.../ChromaprintPlugin.kt  # Android 插件
├── cpp/
│   ├── CMakeLists.txt
│   ├── chromaprint_jni.cpp
│   └── include/chromaprint.h
└── jniLibs/                         # 原生库 (需手动添加)

ios/Runner/
└── ChromaprintChannel.swift         # iOS 插件
```

---

## 替代方案

如果不想编译移动端原生库：

1. **服务端处理**: 上传音频文件到服务器，服务器用 fpcalc 生成指纹
2. **仅桌面端**: 移动端使用元数据搜索，桌面端使用音纹识别
3. **元数据优先**: 默认使用标题/艺术家搜索，音纹作为备选

当前实现已支持自动回退：音纹识别失败时会自动使用元数据搜索。

---

## 相关链接

- [Chromaprint GitHub](https://github.com/acoustid/chromaprint)
- [AcoustID 官网](https://acoustid.org/)
- [AcoustID API 文档](https://acoustid.org/webservice)
