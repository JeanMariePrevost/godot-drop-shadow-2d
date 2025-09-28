shader_type canvas_item;

uniform float softness : hint_range(0.0, 1.0) = 0.25;
uniform float range_px : hint_range(0.0, 50.0) = 6.0;
uniform float dither_levels : hint_range(2.0, 64.0) = 16.0;
uniform float dither_mix : hint_range(0.0, 1.0) = 0.5;

// 4×4 Bayer matrix thresholds in [0..1]
const float bayer4[16] = float[](
    0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
   12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
    3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
   15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
);

float bayer_threshold(vec2 fragcoord) {
    ivec2 p4 = ivec2(mod(fragcoord, 4.0));
    float t4 = bayer4[p4.y * 4 + p4.x];
    ivec2 p2 = ivec2(mod(fragcoord, 2.0));
    float t2 = float(p2.x + p2.y * 2) / 4.0;
    return mix(t4, t2, dither_mix);
}

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    float a = col.a;

    bool do_process = (a > 0.01) && (range_px > 0.0) && (softness > 0.0);

    vec2 texel = TEXTURE_PIXEL_SIZE;
    const vec2 DIRS[8] = vec2[](
        vec2( 1.0,  0.0), vec2( 0.0,  1.0), vec2(-1.0,  0.0), vec2( 0.0, -1.0),
        vec2( 0.70710678,  0.70710678), vec2(-0.70710678,  0.70710678),
        vec2(-0.70710678, -0.70710678), vec2( 0.70710678, -0.70710678)
    );

    float best = range_px;
    if (do_process) {
        const int N_RINGS = 3;
        for (int r = 1; r <= N_RINGS; r++) {
            float radius = (float(r) / float(N_RINGS)) * range_px;
            vec2 delta = radius * texel;
            for (int d = 0; d < 8; d++) {
                float sa = texture(TEXTURE, UV + DIRS[d] * delta).a;
                if (sa < 0.01) {
                    best = min(best, radius);
                }
            }
        }
    }

    float t = do_process ? clamp(best / max(range_px, 1e-4), 0.0, 1.0) : 1.0;

    // --- TRUE DEBANDING DITHER ---
    float steps = dither_levels;
    float v = t * steps;
    float b = bayer_threshold(FRAGCOORD.xy);
    float mask = floor(v + b) / steps;

    float out_a = mix(a, a * mask, softness);
    COLOR = vec4(col.rgb, out_a);
}
