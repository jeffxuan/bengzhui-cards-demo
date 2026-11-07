shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

uniform vec4 cloud_color : source_color = vec4(0.035, 0.052, 0.090, 0.96);
uniform vec4 rim_color : source_color = vec4(0.12, 0.19, 0.28, 1.0);
uniform vec4 core_color : source_color = vec4(0.56, 0.76, 0.88, 1.0);
uniform float intensity = 1.0;
uniform float flash = 0.0;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    // Quantized coordinates keep the silhouette graphic while the noise prevents rectangles.
    vec2 q = floor(uv * 34.0) / 34.0;
    float n = noise(q * 3.7 + vec2(TIME * 0.10, -TIME * 0.07));
    float n2 = noise(q * 8.0 - vec2(TIME * 0.16, TIME * 0.11));
    float body = 1.0 - smoothstep(0.55 + n * 0.18, 0.98, length(vec2(uv.x * 0.94, uv.y * 0.72)));
    body *= smoothstep(-0.80, -0.58, uv.y) * smoothstep(0.92, 0.30, uv.y);
    body *= smoothstep(0.16, 0.72, n * 0.65 + n2 * 0.35 + 0.30);
    float edge = smoothstep(0.02, 0.22, body) * (1.0 - smoothstep(0.30, 0.90, body));
    float core = smoothstep(0.42, 0.92, n2) * smoothstep(0.25, 0.9, body);
    float alpha = clamp(body * (0.88 + flash * 0.20) + edge * 0.24, 0.0, 1.0);
    vec3 color = mix(cloud_color.rgb, rim_color.rgb, edge * 0.34);
    color = mix(color, core_color.rgb, core * (0.20 + flash * 0.65));
    color += core_color.rgb * flash * 0.28;
    ALBEDO = color * intensity;
    EMISSION = color * (0.35 + flash * 2.4);
    ALPHA = alpha;
}
