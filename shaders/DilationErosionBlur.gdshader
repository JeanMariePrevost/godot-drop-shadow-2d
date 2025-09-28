shader_type canvas_item;
render_mode blend_mix, unshaded;

// --- Common controls ---
uniform bool erosion = true;   // 0 = dilating blur, 1 = erosion

// --- Blur controls ---
uniform float radius : hint_range(0.0, 64.0) = 8.0;
uniform float softness : hint_range(0.0, 1.0) = 0.5;
uniform int quality : hint_range(1, 3) = 2;

// --- Erosion controls ---
uniform float distance : hint_range(1.0, 64.0) = 16.0;
uniform int erosion_quality : hint_range(1, 12) = 4;
uniform float strength : hint_range(0.0, 2.0) = 0.5;
uniform float erosion_power : hint_range(1.0, 12.0) = 2.0;

void fragment() {
    vec4 base = texture(TEXTURE, UV);

    if (erosion == false) {
        // -----------------------------
        // DILATING BLUR BRANCH
        // -----------------------------
        vec3 accum_rgb = base.rgb * base.a;
        float accum_a = base.a;
        float total_w = 1.0;

        float ring_step = radius / float(quality);
        float sigma = radius * 0.5;
        float two_sigma2 = 2.0 * sigma * sigma;

        // Ring 1 (hexagon)
        const int R1_SAMPLES = 6;
        vec2 r1_dirs[R1_SAMPLES] = vec2[](
            vec2(1.0, 0.0),
            vec2(0.5, 0.866),
            vec2(-0.5, 0.866),
            vec2(-1.0, 0.0),
            vec2(-0.5, -0.866),
            vec2(0.5, -0.866)
        );
        float r1_dist = ring_step;
        if (quality >= 1) {
            for (int i = 0; i < R1_SAMPLES; i++) {
                vec2 uv = UV + r1_dirs[i] * TEXTURE_PIXEL_SIZE * r1_dist;
                vec4 s = texture(TEXTURE, uv);
                float w = exp(-(r1_dist * r1_dist) / two_sigma2);
                accum_rgb += s.rgb * s.a * w;
                accum_a   += s.a * w;
                total_w   += w;
            }
        }

        // Ring 2 (12 samples)
        const int R2_SAMPLES = 12;
        vec2 r2_dirs[R2_SAMPLES] = vec2[](
            vec2(1.0, 0.0), vec2(0.866, 0.5), vec2(0.5, 0.866),
            vec2(0.0, 1.0), vec2(-0.5, 0.866), vec2(-0.866, 0.5),
            vec2(-1.0, 0.0), vec2(-0.866, -0.5), vec2(-0.5, -0.866),
            vec2(0.0, -1.0), vec2(0.5, -0.866), vec2(0.866, -0.5)
        );
        float r2_dist = ring_step * 2.0;
        if (quality >= 2) {
            for (int i = 0; i < R2_SAMPLES; i++) {
                vec2 uv = UV + r2_dirs[i] * TEXTURE_PIXEL_SIZE * r2_dist;
                vec4 s = texture(TEXTURE, uv);
                float w = exp(-(r2_dist * r2_dist) / two_sigma2);
                accum_rgb += s.rgb * s.a * w;
                accum_a   += s.a * w;
                total_w   += w;
            }
        }

        // Ring 3 (16 samples)
        const int R3_SAMPLES = 16;
        vec2 r3_dirs[R3_SAMPLES] = vec2[](
            vec2(1.0, 0.0), vec2(0.9239, 0.3827), vec2(0.7071, 0.7071),
            vec2(0.3827, 0.9239), vec2(0.0, 1.0), vec2(-0.3827, 0.9239),
            vec2(-0.7071, 0.7071), vec2(-0.9239, 0.3827), vec2(-1.0, 0.0),
            vec2(-0.9239, -0.3827), vec2(-0.7071, -0.7071), vec2(-0.3827, -0.9239),
            vec2(0.0, -1.0), vec2(0.3827, -0.9239), vec2(0.7071, -0.7071),
            vec2(0.9239, -0.3827)
        );
        float r3_dist = ring_step * 3.0;
        if (quality >= 3) {
            for (int i = 0; i < R3_SAMPLES; i++) {
                vec2 uv = UV + r3_dirs[i] * TEXTURE_PIXEL_SIZE * r3_dist;
                vec4 s = texture(TEXTURE, uv);
                float w = exp(-(r3_dist * r3_dist) / two_sigma2);
                accum_rgb += s.rgb * s.a * w;
                accum_a   += s.a * w;
                total_w   += w;
            }
        }

        vec3 blur_rgb = accum_rgb / max(accum_a, 0.0001);
        float blur_a = accum_a / total_w;

        float out_a = mix(base.a, blur_a, softness);
        vec3 out_rgb = mix(base.rgb, blur_rgb, softness);

        COLOR = vec4(out_rgb, out_a);
    }

    else {
        // -----------------------------
        // EROSION BRANCH
        // -----------------------------
        vec2 pixel = 1.0 / vec2(textureSize(TEXTURE, 0));

        vec2 dirs[16] = vec2[](
            vec2(1.0, 0.0), vec2(0.9239, 0.3827), vec2(0.7071, 0.7071), vec2(0.3827, 0.9239),
            vec2(0.0, 1.0), vec2(-0.3827, 0.9239), vec2(-0.7071, 0.7071), vec2(-0.9239, 0.3827),
            vec2(-1.0, 0.0), vec2(-0.9239, -0.3827), vec2(-0.7071, -0.7071), vec2(-0.3827, -0.9239),
            vec2(0.0, -1.0), vec2(0.3827, -0.9239), vec2(0.7071, -0.7071), vec2(0.9239, -0.3827)
        );

        float accum = base.a;
        float total_w = 1.0;

        for (int q = 1; q <= erosion_quality; q++) {
            float dist = (distance * float(q)) / float(erosion_quality);

            float dir_accum = 0.0;
            for (int i = 0; i < 16; i++) {
                dir_accum += texture(TEXTURE, UV + dirs[i] * dist * pixel).a;
            }
            float neighbor = dir_accum / 16.0;

            float eroded = pow(neighbor, erosion_power);

            float w = 1.0 / float(q);
            accum += eroded * w;
            total_w += w;
        }

        float avg_eroded = accum / total_w;
        float out_a = mix(base.a, avg_eroded, strength);

        COLOR = vec4(base.rgb, out_a);
    }
}
