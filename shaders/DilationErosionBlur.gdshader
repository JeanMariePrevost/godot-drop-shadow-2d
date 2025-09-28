shader_type canvas_item;
render_mode blend_mix, unshaded;

// --- Mode ---
uniform bool erosion = false; // false = dilating blur, true = erosion

// --- Unified controls ---
uniform float radius   : hint_range(0.0, 64.0) = 8.0;   // max distance in pixels (both modes)
uniform int   quality  : hint_range(0, 3) = 2;          // 0 = simple fade, 1..3 = sampling
uniform float strength : hint_range(0.0, 1.0) = 0.5;    // blend original ↔ effect

// --- Erosion-only constants ---
const float EROSION_CURVE = 15.0;           // fixed steepness for erosion
const float EROSION_STRENGTH_MULT = 2.0;    // balance blur vs erosion strength
const float RADIUS_SCALE_Q0 = 1.8; // balance the quality 0 special case's radius effect

// Pass modulate from vertex → fragment so we can apply it once
varying vec4 modulate;

void vertex() {
    modulate = COLOR; // capture Sprite2D.modulate
}

// --- Direction sets ---
// Quality 1: 6 directions (hexagon)
const vec2 DIRS6[6] = vec2[](
    vec2(1.0, 0.0), vec2(0.5, 0.866),
    vec2(-0.5, 0.866), vec2(-1.0, 0.0),
    vec2(-0.5, -0.866), vec2(0.5, -0.866)
);

// Quality 2: 12 directions (dodecagon)
const vec2 DIRS12[12] = vec2[](
    vec2(1.0, 0.0), vec2(0.866, 0.5), vec2(0.5, 0.866),
    vec2(0.0, 1.0), vec2(-0.5, 0.866), vec2(-0.866, 0.5),
    vec2(-1.0, 0.0), vec2(-0.866, -0.5), vec2(-0.5, -0.866),
    vec2(0.0, -1.0), vec2(0.5, -0.866), vec2(0.866, -0.5)
);

// Quality 3: 16 directions (full circle, 22.5° steps)
const vec2 DIRS16[16] = vec2[](
    vec2(1.0, 0.0), vec2(0.9239, 0.3827), vec2(0.7071, 0.7071), vec2(0.3827, 0.9239),
    vec2(0.0, 1.0), vec2(-0.3827, 0.9239), vec2(-0.7071, 0.7071), vec2(-0.9239, 0.3827),
    vec2(-1.0, 0.0), vec2(-0.9239, -0.3827), vec2(-0.7071, -0.7071), vec2(-0.3827, -0.9239),
    vec2(0.0, -1.0), vec2(0.3827, -0.9239), vec2(0.7071, -0.7071), vec2(0.9239, -0.3827)
);

// Gaussian helper
float gauss_weight(float d, float sigma) {
    float two_sigma2 = 2.0 * sigma * sigma;
    return exp(-(d * d) / max(two_sigma2, 1e-6));
}

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    vec2 px = TEXTURE_PIXEL_SIZE;

    vec4 result;

	if (quality == 0) {
	    // -----------------------------
	    // SIMPLE CIRCULAR TAPER (Option B with adjustment)
		// Special case since this uses an entirely differnt approach, where "blur" and "erosion" are the same: a feathered alpha
		// O(1) so scales very well, _and_ is smooth for large sprites and large radius, unlike the other approaches
	    // -----------------------------
	    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	    vec2 center = vec2(0.5);

	    // Distance from sprite center in pixels
	    float dist_px = length((UV - center) * tex_size);

	    // Max circular radius in pixels (inscribed circle)
	    float max_r = 0.5 * min(tex_size.x, tex_size.y);

	    // How far inside the edge this pixel is
	    float dist_to_edge = max_r - dist_px;

	    // Fade band thickness scaled by constant
	    float effective_radius = radius * RADIUS_SCALE_Q0;

	    // Fade over the last `effective_radius` pixels
	    float fade = (effective_radius > 0.0)
	        ? clamp(dist_to_edge / effective_radius, 0.0, 1.0)
	        : 1.0;

	    // Shape curve to feel closer to Gaussian
	    fade = pow(fade, 1.5);

	    float out_a = mix(base.a, base.a * fade, strength);
	    result = vec4(base.rgb, out_a);
	}
    else if (!erosion) {
        // -----------------------------
        // DILATING BLUR
        // -----------------------------
        vec3 accum_rgb = base.rgb * base.a;
        float accum_a  = base.a;
        float total_w  = 1.0;

        int ring_count = quality;
        float ring_step = (quality > 0) ? radius / float(quality) : 0.0;
        float sigma = max(radius * 0.5, 1e-4);

        for (int r = 1; r <= 3; r++) {
            if (r > ring_count) break;
            float dist = ring_step * float(r);
            float w = gauss_weight(dist, sigma);

            if (quality == 1) {
                for (int i = 0; i < 6; i++) {
                    vec4 s = texture(TEXTURE, UV + DIRS6[i] * px * dist);
                    accum_rgb += s.rgb * s.a * w;
                    accum_a   += s.a * w;
                }
                total_w += 6.0 * w;
            } else if (quality == 2) {
                for (int i = 0; i < 12; i++) {
                    vec4 s = texture(TEXTURE, UV + DIRS12[i] * px * dist);
                    accum_rgb += s.rgb * s.a * w;
                    accum_a   += s.a * w;
                }
                total_w += 12.0 * w;
            } else {
                for (int i = 0; i < 16; i++) {
                    vec4 s = texture(TEXTURE, UV + DIRS16[i] * px * dist);
                    accum_rgb += s.rgb * s.a * w;
                    accum_a   += s.a * w;
                }
                total_w += 16.0 * w;
            }
        }

        vec3 blur_rgb = accum_rgb / max(accum_a, 1e-4);
        float blur_a  = accum_a / max(total_w, 1e-6);

        vec3 out_rgb = mix(base.rgb, blur_rgb, strength);
        float out_a  = mix(base.a,  blur_a,  strength);

        result = vec4(out_rgb, out_a);
    }
    else {
        // -----------------------------
        // EROSION
        // -----------------------------
        int ang = (quality == 1) ? 6 : ((quality == 2) ? 12 : 16);
        int radial_steps = quality * 4;

        float accum = base.a;
        float total_w = 1.0;

        for (int q = 1; q <= radial_steps; q++) {
            float t = float(q) / float(radial_steps);
            float dist = radius * t;

            float dir_accum = 0.0;
            if (quality == 1) {
                for (int i = 0; i < 6; i++) {
                    dir_accum += texture(TEXTURE, UV + DIRS6[i] * px * dist).a;
                }
            } else if (quality == 2) {
                for (int i = 0; i < 12; i++) {
                    dir_accum += texture(TEXTURE, UV + DIRS12[i] * px * dist).a;
                }
            } else {
                for (int i = 0; i < 16; i++) {
                    dir_accum += texture(TEXTURE, UV + DIRS16[i] * px * dist).a;
                }
            }

            float neighbor = dir_accum / float(ang);
            float eroded = pow(neighbor, EROSION_CURVE);

            float w = 1.0 / float(q);
            accum += eroded * w;
            total_w += w;
        }

        float avg_eroded = accum / max(total_w, 1e-6);
        float out_a = mix(base.a, avg_eroded, strength * EROSION_STRENGTH_MULT);

        result = vec4(base.rgb, out_a);
    }

    // Apply Sprite's modulate once at the end
    COLOR = result * modulate;
}
