#version 460 core

#include <flutter/runtime_effect.glsl>

// Uniforms
uniform vec2 uResolution;      // 画布尺寸
uniform float uCurlPosition;   // 卷曲位置 (0.0 - 1.0，0=未卷曲，1=完全卷曲)
uniform float uCurlRadius;     // 卷曲半径
uniform float uShadowIntensity; // 阴影强度
uniform sampler2D uTexture;    // 当前页面纹理
uniform sampler2D uNextTexture; // 下一页纹理

out vec4 fragColor;

const float PI = 3.14159265359;

// 计算卷曲效果
void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;

    // 翻转 Y 坐标（Flutter 坐标系）
    uv.y = 1.0 - uv.y;

    // 卷曲线的位置（从右向左移动）
    float curlLine = 1.0 - uCurlPosition;

    // 卷曲半径
    float radius = uCurlRadius;

    // 计算到卷曲线的距离
    float distToCurl = uv.x - curlLine;

    // 卷曲区域的宽度
    float curlWidth = PI * radius;

    vec4 color;

    if (distToCurl < 0.0) {
        // 左侧：显示下一页
        color = texture(uNextTexture, uv);

        // 添加阴影效果
        float shadowDist = -distToCurl;
        if (shadowDist < radius * 2.0) {
            float shadowFactor = 1.0 - (shadowDist / (radius * 2.0));
            shadowFactor = shadowFactor * shadowFactor * uShadowIntensity;
            color.rgb *= (1.0 - shadowFactor * 0.5);
        }
    } else if (distToCurl < curlWidth) {
        // 卷曲区域：计算曲面上的位置
        float angle = distToCurl / radius;

        if (angle <= PI) {
            // 正在卷曲的部分
            // 计算原始纹理坐标
            float originalX = curlLine + radius * sin(angle);
            vec2 curledUV = vec2(originalX, uv.y);

            // 确保在有效范围内
            if (curledUV.x >= 0.0 && curledUV.x <= 1.0) {
                color = texture(uTexture, curledUV);

                // 添加卷曲光照效果
                float lightFactor = cos(angle) * 0.3 + 0.7;
                color.rgb *= lightFactor;

                // 添加高光
                if (angle > PI * 0.3 && angle < PI * 0.7) {
                    float highlight = sin((angle - PI * 0.3) / (PI * 0.4) * PI);
                    color.rgb += vec3(highlight * 0.15);
                }
            } else {
                color = texture(uNextTexture, uv);
            }
        } else {
            // 超出卷曲范围，显示下一页
            color = texture(uNextTexture, uv);
        }
    } else {
        // 右侧：显示当前页（未卷曲部分）
        color = texture(uTexture, uv);
    }

    // 添加边缘渐变效果
    float edgeFade = smoothstep(0.0, 0.02, uv.x) * smoothstep(0.0, 0.02, 1.0 - uv.x);
    edgeFade *= smoothstep(0.0, 0.02, uv.y) * smoothstep(0.0, 0.02, 1.0 - uv.y);

    fragColor = color * edgeFade + color * (1.0 - edgeFade) * 0.95;
}
