/* Chromaprint 头文件 (简化版)
 *
 * 原始文件来自 https://github.com/acoustid/chromaprint
 * 此处仅包含必要的声明供 JNI 使用
 */

#ifndef CHROMAPRINT_H_
#define CHROMAPRINT_H_

#ifdef __cplusplus
extern "C" {
#endif

typedef void *ChromaprintContext;

#define CHROMAPRINT_ALGORITHM_DEFAULT 0
#define CHROMAPRINT_ALGORITHM_TEST1 1
#define CHROMAPRINT_ALGORITHM_TEST2 2
#define CHROMAPRINT_ALGORITHM_TEST3 3
#define CHROMAPRINT_ALGORITHM_TEST4 4

/**
 * 获取库版本
 */
const char *chromaprint_get_version(void);

/**
 * 创建新的 Chromaprint 上下文
 */
ChromaprintContext *chromaprint_new(int algorithm);

/**
 * 释放 Chromaprint 上下文
 */
void chromaprint_free(ChromaprintContext *ctx);

/**
 * 设置选项
 */
int chromaprint_set_option(ChromaprintContext *ctx, const char *name, int value);

/**
 * 获取采样率
 */
int chromaprint_get_sample_rate(ChromaprintContext *ctx);

/**
 * 开始指纹计算
 */
int chromaprint_start(ChromaprintContext *ctx, int sample_rate, int num_channels);

/**
 * 喂入音频数据
 */
int chromaprint_feed(ChromaprintContext *ctx, const int16_t *data, int size);

/**
 * 结束指纹计算
 */
int chromaprint_finish(ChromaprintContext *ctx);

/**
 * 获取指纹字符串 (Base64)
 */
int chromaprint_get_fingerprint(ChromaprintContext *ctx, char **fingerprint);

/**
 * 获取原始指纹数据
 */
int chromaprint_get_raw_fingerprint(ChromaprintContext *ctx, uint32_t **fingerprint, int *size);

/**
 * 编码指纹
 */
int chromaprint_encode_fingerprint(const uint32_t *fp, int size, int algorithm,
                                    char **encoded_fp, int *encoded_size, int base64);

/**
 * 解码指纹
 */
int chromaprint_decode_fingerprint(const char *encoded_fp, int encoded_size,
                                    uint32_t **fp, int *size, int *algorithm, int base64);

/**
 * 释放内存
 */
void chromaprint_dealloc(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* CHROMAPRINT_H_ */
