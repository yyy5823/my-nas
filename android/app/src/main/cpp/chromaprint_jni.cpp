/**
 * Chromaprint JNI 封装
 *
 * 提供 Java/Kotlin 调用 Chromaprint 库的接口
 */

#include <jni.h>
#include <string>
#include <chromaprint.h>

extern "C" {

/**
 * 创建 Chromaprint 上下文
 */
JNIEXPORT jlong JNICALL
Java_com_kkape_nas_ChromaprintPlugin_nativeNew(
    JNIEnv *env,
    jobject thiz,
    jint sample_rate,
    jint channels
) {
    ChromaprintContext *ctx = chromaprint_new(CHROMAPRINT_ALGORITHM_DEFAULT);
    if (ctx == nullptr) {
        return 0;
    }

    chromaprint_set_option(ctx, "sample_rate", sample_rate);

    return reinterpret_cast<jlong>(ctx);
}

/**
 * 开始指纹计算
 */
JNIEXPORT jboolean JNICALL
Java_com_kkape_nas_ChromaprintPlugin_nativeStart(
    JNIEnv *env,
    jobject thiz,
    jlong ctx_ptr
) {
    auto *ctx = reinterpret_cast<ChromaprintContext *>(ctx_ptr);
    if (ctx == nullptr) {
        return JNI_FALSE;
    }

    int sample_rate = 44100;
    int channels = 2;

    return chromaprint_start(ctx, sample_rate, channels) == 1 ? JNI_TRUE : JNI_FALSE;
}

/**
 * 喂入音频数据
 */
JNIEXPORT jboolean JNICALL
Java_com_kkape_nas_ChromaprintPlugin_nativeFeed(
    JNIEnv *env,
    jobject thiz,
    jlong ctx_ptr,
    jshortArray data,
    jint size
) {
    auto *ctx = reinterpret_cast<ChromaprintContext *>(ctx_ptr);
    if (ctx == nullptr) {
        return JNI_FALSE;
    }

    jshort *samples = env->GetShortArrayElements(data, nullptr);
    if (samples == nullptr) {
        return JNI_FALSE;
    }

    int result = chromaprint_feed(ctx, samples, size);

    env->ReleaseShortArrayElements(data, samples, JNI_ABORT);

    return result == 1 ? JNI_TRUE : JNI_FALSE;
}

/**
 * 结束指纹计算
 */
JNIEXPORT jboolean JNICALL
Java_com_kkape_nas_ChromaprintPlugin_nativeFinish(
    JNIEnv *env,
    jobject thiz,
    jlong ctx_ptr
) {
    auto *ctx = reinterpret_cast<ChromaprintContext *>(ctx_ptr);
    if (ctx == nullptr) {
        return JNI_FALSE;
    }

    return chromaprint_finish(ctx) == 1 ? JNI_TRUE : JNI_FALSE;
}

/**
 * 获取指纹字符串
 */
JNIEXPORT jstring JNICALL
Java_com_kkape_nas_ChromaprintPlugin_nativeGetFingerprint(
    JNIEnv *env,
    jobject thiz,
    jlong ctx_ptr
) {
    auto *ctx = reinterpret_cast<ChromaprintContext *>(ctx_ptr);
    if (ctx == nullptr) {
        return nullptr;
    }

    char *fingerprint = nullptr;
    if (chromaprint_get_fingerprint(ctx, &fingerprint) != 1 || fingerprint == nullptr) {
        return nullptr;
    }

    jstring result = env->NewStringUTF(fingerprint);
    chromaprint_dealloc(fingerprint);

    return result;
}

/**
 * 释放上下文
 */
JNIEXPORT void JNICALL
Java_com_kkape_nas_ChromaprintPlugin_nativeFree(
    JNIEnv *env,
    jobject thiz,
    jlong ctx_ptr
) {
    auto *ctx = reinterpret_cast<ChromaprintContext *>(ctx_ptr);
    if (ctx != nullptr) {
        chromaprint_free(ctx);
    }
}

/**
 * 获取版本号
 */
JNIEXPORT jstring JNICALL
Java_com_kkape_nas_ChromaprintPlugin_nativeGetVersion(
    JNIEnv *env,
    jobject thiz
) {
    const char *version = chromaprint_get_version();
    return env->NewStringUTF(version);
}

} // extern "C"
