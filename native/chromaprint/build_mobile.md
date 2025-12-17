# 移动端 Chromaprint 构建指南

本文档说明如何为 Android 和 iOS 构建 Chromaprint 原生库。

## 概述

移动端音纹识别需要编译 Chromaprint 库：
- **Android**: 编译为 `libchromaprint.so` (通过 NDK)
- **iOS**: 编译为 `Chromaprint.framework` 或静态库

## Android 构建

### 方式 1: 使用预编译库 (推荐)

1. 下载预编译的 Android 库：
   - 从 [AcoustID](https://acoustid.org/chromaprint) 或 GitHub Releases
   - 或使用第三方打包：https://github.com/niclas3640/chromaprint-android

2. 将 `.so` 文件放入 `android/app/src/main/jniLibs/`:
   ```
   android/app/src/main/jniLibs/
   ├── arm64-v8a/
   │   └── libchromaprint.so
   ├── armeabi-v7a/
   │   └── libchromaprint.so
   └── x86_64/
       └── libchromaprint.so
   ```

3. 在 `android/app/build.gradle` 中添加 NDK 配置：
   ```groovy
   android {
       // ...
       externalNativeBuild {
           cmake {
               path "src/main/cpp/CMakeLists.txt"
               version "3.18.1"
           }
       }

       defaultConfig {
           // ...
           ndk {
               abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'
           }
       }
   }
   ```

### 方式 2: 从源码编译

1. 安装依赖：
   ```bash
   # macOS
   brew install cmake ninja

   # 下载 Android NDK
   # 可通过 Android Studio SDK Manager 安装
   ```

2. 下载 Chromaprint 源码：
   ```bash
   git clone https://github.com/acoustid/chromaprint.git
   cd chromaprint
   ```

3. 编译各架构：
   ```bash
   # 设置 NDK 路径
   export ANDROID_NDK=$HOME/Library/Android/sdk/ndk/25.1.8937393

   # arm64-v8a
   mkdir build-android-arm64 && cd build-android-arm64
   cmake .. \
       -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
       -DANDROID_ABI=arm64-v8a \
       -DANDROID_PLATFORM=android-21 \
       -DBUILD_SHARED_LIBS=ON \
       -DBUILD_TOOLS=OFF \
       -DBUILD_TESTS=OFF \
       -DFFT_LIB=kissfft
   make -j$(nproc)
   cd ..

   # armeabi-v7a
   mkdir build-android-armv7 && cd build-android-armv7
   cmake .. \
       -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
       -DANDROID_ABI=armeabi-v7a \
       -DANDROID_PLATFORM=android-21 \
       -DBUILD_SHARED_LIBS=ON \
       -DBUILD_TOOLS=OFF \
       -DBUILD_TESTS=OFF \
       -DFFT_LIB=kissfft
   make -j$(nproc)
   cd ..
   ```

4. 复制编译产物到项目。

## iOS 构建

### 方式 1: 使用 CocoaPods (如果可用)

检查是否有可用的 pod：
```ruby
# Podfile
pod 'Chromaprint', '~> 1.5'
```

### 方式 2: 从源码编译 (xcframework)

1. 安装依赖：
   ```bash
   brew install cmake
   ```

2. 下载源码：
   ```bash
   git clone https://github.com/niclas3640/AcoustID-iOS.git
   # 或
   git clone https://github.com/acoustid/chromaprint.git
   ```

3. 编译 xcframework：
   ```bash
   cd chromaprint

   # iOS Device (arm64)
   mkdir build-ios && cd build-ios
   cmake .. \
       -G Xcode \
       -DCMAKE_SYSTEM_NAME=iOS \
       -DCMAKE_OSX_ARCHITECTURES=arm64 \
       -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
       -DBUILD_SHARED_LIBS=OFF \
       -DBUILD_TOOLS=OFF \
       -DBUILD_TESTS=OFF \
       -DFFT_LIB=kissfft
   cmake --build . --config Release
   cd ..

   # iOS Simulator (arm64 + x86_64)
   mkdir build-ios-sim && cd build-ios-sim
   cmake .. \
       -G Xcode \
       -DCMAKE_SYSTEM_NAME=iOS \
       -DCMAKE_OSX_SYSROOT=iphonesimulator \
       -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
       -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
       -DBUILD_SHARED_LIBS=OFF \
       -DBUILD_TOOLS=OFF \
       -DBUILD_TESTS=OFF \
       -DFFT_LIB=kissfft
   cmake --build . --config Release
   cd ..

   # 创建 xcframework
   xcodebuild -create-xcframework \
       -library build-ios/Release-iphoneos/libchromaprint.a -headers src \
       -library build-ios-sim/Release-iphonesimulator/libchromaprint.a -headers src \
       -output Chromaprint.xcframework
   ```

4. 将 `Chromaprint.xcframework` 添加到 Xcode 项目：
   - 拖入 `ios/Frameworks/` 目录
   - 在 Xcode 中添加到 Target -> Frameworks

5. 创建 Bridging Header (`ios/Runner/Runner-Bridging-Header.h`)：
   ```c
   #import <chromaprint.h>
   ```

## 验证

### Android
```kotlin
// 在 MainActivity 或测试中
val available = ChromaprintPlugin.nativeLibraryLoaded
Log.d("Chromaprint", "Available: $available")
```

### iOS
```swift
// 在 AppDelegate 或测试中
let available = ChromaprintChannel.frameworkLoaded
print("Chromaprint available: \(available)")
```

## 替代方案

如果编译原生库太复杂，考虑以下替代方案：

### 1. 服务端处理
- 将音频文件上传到服务器
- 服务器使用 fpcalc 生成指纹
- 返回指纹结果给客户端

### 2. 使用 WebAssembly
- 将 Chromaprint 编译为 WASM
- 通过 WebView 调用
- 性能可能较差

### 3. 仅桌面端支持
- 移动端使用元数据搜索
- 桌面端使用 fpcalc

## 注意事项

1. **文件大小**: Chromaprint 库约 200-500KB
2. **依赖**: 需要 FFT 库 (FFTW3 或 KissFFT)
3. **许可证**: Chromaprint 使用 LGPL 2.1+ 许可证
4. **最低版本**:
   - Android: API 21+
   - iOS: 12.0+
