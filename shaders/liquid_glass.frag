#include <flutter/runtime_effect.glsl>

// Uniforms
uniform vec2 resolution;        // 容器尺寸
uniform float cornerRadius;     // 圆角半径
uniform float time;             // 时间（用于动态效果）
uniform float refractionStrength; // 折射强度 (0.0 - 1.0)
uniform float highlightIntensity; // 高光强度 (0.0 - 1.0)
uniform float fresnelPower;     // 菲涅尔指数
uniform float isDark;           // 是否深色模式 (0.0 或 1.0)
uniform sampler2D backgroundTexture; // 背景纹理（已模糊）

out vec4 fragColor;

const float PI = 3.14159265359;

// 计算到圆角矩形边缘的距离
float roundedBoxSDF(vec2 centerPos, vec2 size, float radius) {
    vec2 q = abs(centerPos) - size + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

// 菲涅尔效果 - 边缘更亮
float fresnel(float cosTheta, float power) {
    return pow(1.0 - cosTheta, power);
}

// 生成伪随机噪声
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 平滑噪声
float smoothNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = noise(i);
    float b = noise(i + vec2(1.0, 0.0));
    float c = noise(i + vec2(0.0, 1.0));
    float d = noise(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    vec2 uv = FlutterFragCoord().xy;
    vec2 texCoord = uv / resolution;
    vec2 center = resolution * 0.5;
    vec2 pos = uv - center;

    // 计算到边缘的距离（用于圆角）
    float dist = roundedBoxSDF(pos, resolution * 0.5, cornerRadius);

    // 在容器外部完全透明
    if (dist > 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // 计算到边缘的归一化距离（0 = 边缘, 1 = 中心）
    float edgeDist = clamp(-dist / min(resolution.x, resolution.y) * 4.0, 0.0, 1.0);

    // ===== 折射效果 =====
    // 模拟玻璃球/水滴的折射 - 边缘弯曲更大
    float refractionAmount = (1.0 - edgeDist) * refractionStrength * 0.05;

    // 添加微妙的动态扭曲
    float dynamicOffset = smoothNoise(uv * 0.01 + time * 0.1) * 0.5;

    // 计算折射后的采样位置
    vec2 normal = normalize(pos);
    vec2 refractedUV = texCoord + normal * refractionAmount * (1.0 + dynamicOffset * 0.2);

    // 边界检查
    refractedUV = clamp(refractedUV, 0.0, 1.0);

    // ===== 采样背景 =====
    vec4 bgColor = texture(backgroundTexture, refractedUV);

    // ===== 色散效果 =====
    // RGB 轻微分离，模拟光的色散
    float chromaOffset = refractionAmount * 0.3;
    vec4 bgR = texture(backgroundTexture, refractedUV + vec2(chromaOffset, 0.0));
    vec4 bgB = texture(backgroundTexture, refractedUV - vec2(chromaOffset, 0.0));
    bgColor.r = mix(bgColor.r, bgR.r, 0.3);
    bgColor.b = mix(bgColor.b, bgB.b, 0.3);

    // ===== 菲涅尔高光 =====
    // 边缘反射更强
    float fresnelTerm = fresnel(edgeDist, fresnelPower);

    // 高光颜色
    vec3 highlightColor = isDark > 0.5
        ? vec3(1.0, 1.0, 1.0)
        : vec3(1.0, 1.0, 1.0);

    // ===== 边缘高光渐变 =====
    // 顶部和左上角更亮（模拟光源在左上方）
    vec2 lightDir = normalize(vec2(-1.0, -1.0));
    float lightAngle = dot(normal, lightDir);
    float directionalHighlight = max(0.0, lightAngle) * highlightIntensity * 0.5;

    // ===== 玻璃染色 =====
    // 轻微的颜色偏移，增加玻璃质感
    vec3 tintColor = isDark > 0.5
        ? vec3(0.6, 0.7, 0.8)   // 深色模式：冷色调
        : vec3(0.95, 0.97, 1.0); // 浅色模式：略带蓝调

    bgColor.rgb = mix(bgColor.rgb, bgColor.rgb * tintColor, 0.1);

    // ===== 合成 =====
    // 基础颜色
    vec3 finalColor = bgColor.rgb;

    // 添加菲涅尔边缘高光
    finalColor += highlightColor * fresnelTerm * highlightIntensity * 0.4;

    // 添加定向高光
    finalColor += highlightColor * directionalHighlight;

    // 添加微妙的内发光
    float innerGlow = smoothstep(0.0, 0.3, edgeDist) * 0.05;
    finalColor += highlightColor * innerGlow * highlightIntensity;

    // ===== 边缘柔化 =====
    float edgeAlpha = smoothstep(0.0, 2.0, -dist);

    // 最终透明度
    float alpha = bgColor.a * edgeAlpha;

    // 玻璃本身的半透明度
    float glassOpacity = isDark > 0.5 ? 0.85 : 0.9;
    alpha *= glassOpacity;

    fragColor = vec4(finalColor, alpha);
}
