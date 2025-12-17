# Chromaprint JNI CMakeLists.txt

cmake_minimum_required(VERSION 3.18.1)

project("chromaprint_jni")

# 设置 C++ 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Chromaprint 预编译库路径
# 需要将预编译的 libchromaprint.so 放在 jniLibs 目录下
set(CHROMAPRINT_DIR ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

# 添加 Chromaprint 库
add_library(chromaprint SHARED IMPORTED)
set_target_properties(chromaprint PROPERTIES
    IMPORTED_LOCATION ${CHROMAPRINT_DIR}/libchromaprint.so
)

# 添加头文件目录
include_directories(${CMAKE_SOURCE_DIR}/include)

# 创建 JNI 库
add_library(chromaprint_jni SHARED
    chromaprint_jni.cpp
)

# 链接库
target_link_libraries(chromaprint_jni
    chromaprint
    log
)
