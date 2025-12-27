#include <flutter/runtime_effect.glsl>

// Uniforms
uniform vec2 resolution;      // 画布尺寸
uniform float progress;       // 翻页进度 (0.0 - 1.0)
uniform float direction;      // 翻页方向: 1.0 = 向左翻(下一页), -1.0 = 向右翻(上一页)
uniform float dragStartY;     // 拖动起始 Y 位置比例 (0.0 - 1.0)
uniform vec4 backgroundColor; // 背景颜色
uniform sampler2D currentPage; // 当前页面
uniform sampler2D nextPage;    // 下一页面

// 常量
const float PI = 3.14159265359;
const float CURL_RADIUS = 80.0;      // 卷曲半径
const float SHADOW_INTENSITY = 0.4;  // 阴影强度

out vec4 fragColor;

// 计算折线位置（带角度）
vec2 getFoldLine(float y, float foldX, float angle) {
    float centerY = resolution.y * 0.5;
    float offsetX = (y - centerY) * tan(angle);
    return vec2(foldX + offsetX, y);
}

void main() {
    vec2 uv = FlutterFragCoord().xy;
    vec2 texCoord = uv / resolution;

    // 根据方向计算折线位置
    float foldX;
    if (direction > 0.0) {
        // 向左翻：折线从右边向左移动
        foldX = resolution.x * (1.0 - progress);
    } else {
        // 向右翻：折线从左边向右移动
        foldX = resolution.x * progress;
    }

    // 根据拖动起始位置计算折线角度
    float angleIntensity = 0.12;
    float angle = (dragStartY - 0.5) * angleIntensity;

    // 获取当前像素对应的折线 X 位置
    vec2 foldPoint = getFoldLine(uv.y, foldX, angle);
    float localFoldX = foldPoint.x;

    // 计算到折线的水平距离
    float d = uv.x - localFoldX;

    if (direction > 0.0) {
        // 向左翻页（下一页）
        if (d < -CURL_RADIUS) {
            // 未翻起的部分 - 显示当前页
            fragColor = texture(currentPage, texCoord);
        }
        else if (d < 0.0) {
            // 卷曲过渡区域
            float theta = acos(-d / CURL_RADIUS);
            float arc = theta * CURL_RADIUS;

            // 计算卷曲后的纹理坐标
            vec2 curledCoord = vec2((localFoldX - arc) / resolution.x, texCoord.y);

            if (curledCoord.x >= 0.0 && curledCoord.x <= 1.0) {
                vec4 pageColor = texture(currentPage, curledCoord);

                // 添加卷曲阴影
                float shadow = 1.0 - (1.0 - cos(theta)) * SHADOW_INTENSITY;
                pageColor.rgb *= shadow;

                fragColor = pageColor;
            } else {
                fragColor = backgroundColor;
            }
        }
        else if (d < CURL_RADIUS) {
            // 翻起页面的背面 + 下一页可见
            float theta = asin(d / CURL_RADIUS);

            // 计算圆弧上的点
            float arc1 = theta * CURL_RADIUS;
            float arc2 = (PI - theta) * CURL_RADIUS;

            // 翻起页面背面的纹理坐标
            vec2 backCoord = vec2((localFoldX + arc2) / resolution.x, texCoord.y);

            // 下一页的纹理坐标
            vec2 nextCoord = texCoord;

            if (backCoord.x >= 0.0 && backCoord.x <= 1.0) {
                // 显示翻起页面的背面（略微变暗模拟纸张背面）
                vec4 backColor = texture(currentPage, backCoord);

                // 纸张背面颜色调整
                backColor.rgb *= 0.85;

                // 内侧阴影
                float innerShadow = 1.0 - sin(theta) * 0.3;
                backColor.rgb *= innerShadow;

                fragColor = backColor;
            } else {
                // 显示下一页
                vec4 nextColor = texture(nextPage, nextCoord);

                // 添加翻页投射的阴影
                float shadowDist = d / CURL_RADIUS;
                float pageShadow = 1.0 - (1.0 - shadowDist) * SHADOW_INTENSITY * 0.5;
                nextColor.rgb *= pageShadow;

                fragColor = nextColor;
            }
        }
        else {
            // 完全翻过去的部分 - 显示下一页
            vec4 nextColor = texture(nextPage, texCoord);
            fragColor = nextColor;
        }
    }
    else {
        // 向右翻页（上一页）- 镜像处理
        d = -d; // 反转距离计算

        if (d < -CURL_RADIUS) {
            // 未翻起的部分 - 显示当前页
            fragColor = texture(currentPage, texCoord);
        }
        else if (d < 0.0) {
            // 卷曲过渡区域
            float theta = acos(-d / CURL_RADIUS);
            float arc = theta * CURL_RADIUS;

            vec2 curledCoord = vec2((localFoldX + arc) / resolution.x, texCoord.y);

            if (curledCoord.x >= 0.0 && curledCoord.x <= 1.0) {
                vec4 pageColor = texture(currentPage, curledCoord);
                float shadow = 1.0 - (1.0 - cos(theta)) * SHADOW_INTENSITY;
                pageColor.rgb *= shadow;
                fragColor = pageColor;
            } else {
                fragColor = backgroundColor;
            }
        }
        else if (d < CURL_RADIUS) {
            // 翻起页面的背面 + 上一页可见
            float theta = asin(d / CURL_RADIUS);
            float arc2 = (PI - theta) * CURL_RADIUS;

            vec2 backCoord = vec2((localFoldX - arc2) / resolution.x, texCoord.y);

            if (backCoord.x >= 0.0 && backCoord.x <= 1.0) {
                vec4 backColor = texture(currentPage, backCoord);
                backColor.rgb *= 0.85;
                float innerShadow = 1.0 - sin(theta) * 0.3;
                backColor.rgb *= innerShadow;
                fragColor = backColor;
            } else {
                vec4 nextColor = texture(nextPage, texCoord);
                float shadowDist = d / CURL_RADIUS;
                float pageShadow = 1.0 - (1.0 - shadowDist) * SHADOW_INTENSITY * 0.5;
                nextColor.rgb *= pageShadow;
                fragColor = nextColor;
            }
        }
        else {
            fragColor = texture(nextPage, texCoord);
        }
    }
}
