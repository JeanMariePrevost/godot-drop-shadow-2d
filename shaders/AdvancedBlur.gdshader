shader_type canvas_item;
render_mode blend_mix, unshaded;

// --- Mode ---
uniform bool erosion = false; // false = dilating blur, true = erosion

// --- Unified controls ---
uniform float radius   : hint_range(0.0, 64.0) = 8.0;   // max distance in pixels (both modes)
uniform int   quality  : hint_range(0, 4) = 2;          // 0 = simple fade, 1..4 = sampling
uniform float strength : hint_range(0.0, 1.0) = 0.5;    // blend original ↔ effect

// --- Tint controls ---
uniform vec3  tint_color : source_color = vec3(1.0, 1.0, 1.0);  // color picker for tinting
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;       // strength of tint (0.0-1.0)

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
// First ring: 4 directions (diamond - cardinal directions for cost reduction and better sampling diversity)
const vec2 DIRS4[4] = vec2[](
    vec2(1.0, 0.0),   // Right
    vec2(0.0, 1.0),   // Up  
    vec2(-1.0, 0.0),  // Left
    vec2(0.0, -1.0)   // Down
);

// Second ring: 6 directions (hexagon)
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

// Quality 4: 24 directions (full circle, 15° steps)
const vec2 DIRS24[24] = vec2[](
    vec2(1.0, 0.0), vec2(0.9659, 0.2588), vec2(0.8660, 0.5000), vec2(0.7071, 0.7071),
    vec2(0.5000, 0.8660), vec2(0.2588, 0.9659), vec2(0.0, 1.0), vec2(-0.2588, 0.9659),
    vec2(-0.5000, 0.8660), vec2(-0.7071, 0.7071), vec2(-0.8660, 0.5000), vec2(-0.9659, 0.2588),
    vec2(-1.0, 0.0), vec2(-0.9659, -0.2588), vec2(-0.8660, -0.5000), vec2(-0.7071, -0.7071),
    vec2(-0.5000, -0.8660), vec2(-0.2588, -0.9659), vec2(0.0, -1.0), vec2(0.2588, -0.9659),
    vec2(0.5000, -0.8660), vec2(0.7071, -0.7071), vec2(0.8660, -0.5000), vec2(0.9659, -0.2588)
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
	    // DYNAMIC ROUNDED RECTANGLE TAPER
		// Special case that creates a rounded rectangle shadow effect with dynamic corner rounding
		// O(1) so scales very well, _and_ is smooth for large sprites and large radius
	    // -----------------------------
	    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	    vec2 uv_px = UV * tex_size;  // Convert UV to pixel coordinates
	    
	    // Calculate distance to each edge in pixels
	    float dist_to_left = uv_px.x;
	    float dist_to_right = tex_size.x - uv_px.x;
	    float dist_to_top = uv_px.y;
	    float dist_to_bottom = tex_size.y - uv_px.y;
	    
	    // Dynamic corner radius based on texture dimensions (half the smallest side)
	    float min_side = min(tex_size.x, tex_size.y);
	    float corner_radius = min_side * 0.5;
	    
	    // For rounded rectangle: distance to nearest edge, but with corner rounding
	    vec2 dist_to_edges = vec2(
	        min(dist_to_left, dist_to_right),
	        min(dist_to_top, dist_to_bottom)
	    );
	    
	    // Apply corner rounding: if we're near a corner, use circular distance
	    vec2 corner_center = vec2(
	        dist_to_left < corner_radius && dist_to_right < corner_radius ? 0.0 : 0.0,
	        dist_to_top < corner_radius && dist_to_bottom < corner_radius ? 0.0 : 0.0
	    );
	    
	    // Distance to nearest edge (with corner rounding)
	    float dist_to_edge;
	    if (dist_to_edges.x < corner_radius && dist_to_edges.y < corner_radius) {
	        // In corner region - use circular distance
	        vec2 corner_dist = dist_to_edges - corner_radius;
	        dist_to_edge = corner_radius - length(corner_dist);
	    } else {
	        // In edge region - use rectangular distance
	        dist_to_edge = min(dist_to_edges.x, dist_to_edges.y);
	    }

	    // Fade band thickness scaled by constant
	    float effective_radius = radius * RADIUS_SCALE_Q0;

	    // Fade over the last `effective_radius` pixels from the edges
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
        // DILATING BLUR WITH PROGRESSIVE TAPS
        // -----------------------------
        vec3 accum_rgb = base.rgb * base.a;
        float accum_a  = base.a;
        float total_w  = 1.0;

        // Dynamic ring counts: Low=2, Medium=3, High=4, Ultra=5 rings
        int ring_count = quality + 1;  // quality 1→2 rings, quality 2→3 rings, quality 3→4 rings, quality 4→5 rings
        
        // Total radius stays the same regardless of ring count
        float ring_step = radius / float(ring_count);
        float sigma = max(radius * 0.5, 1e-4);

        for (int r = 1; r <= 5; r++) {
            if (r > ring_count) break;
            float dist = ring_step * float(r);
            float w = gauss_weight(dist, sigma);

            // Progressive tap counts: diamond first ring, then hexagon, then higher quality
            int taps;
            if (r == 1) {
                // First ring: 4 taps (diamond) for cost reduction and sampling diversity
                taps = 4;
                for (int i = 0; i < 4; i++) {
                    vec4 s = texture(TEXTURE, UV + DIRS4[i] * px * dist);
                    accum_rgb += s.rgb * s.a * w;
                    accum_a   += s.a * w;
                }
            } else if (r == 2) {
                // Second ring: 6 taps (hexagon) for performance
                taps = 6;
                for (int i = 0; i < 6; i++) {
                    vec4 s = texture(TEXTURE, UV + DIRS6[i] * px * dist);
                    accum_rgb += s.rgb * s.a * w;
                    accum_a   += s.a * w;
                }
            } else if (r == 3) {
                // Third ring: 12 taps (dodecagon) for better quality
                taps = 12;
                for (int i = 0; i < 12; i++) {
                    vec4 s = texture(TEXTURE, UV + DIRS12[i] * px * dist);
                    accum_rgb += s.rgb * s.a * w;
                    accum_a   += s.a * w;
                }
            } else if (r == 4) {
                // Fourth ring: 16 taps 
                taps = 16;
                for (int i = 0; i < 16; i++) {
                    vec4 s = texture(TEXTURE, UV + DIRS16[i] * px * dist);
                    accum_rgb += s.rgb * s.a * w;
                    accum_a   += s.a * w;
                }
            } else {
                // Fifth ring: 24 taps 
                taps = 24;
                for (int i = 0; i < 24; i++) {
                    vec4 s = texture(TEXTURE, UV + DIRS24[i] * px * dist);
                    accum_rgb += s.rgb * s.a * w;
                    accum_a   += s.a * w;
                }
            }
            total_w += float(taps) * w;
        }

        vec3 blur_rgb = accum_rgb / max(accum_a, 1e-4);
        float blur_a  = accum_a / max(total_w, 1e-6);

        vec3 out_rgb = mix(base.rgb, blur_rgb, strength);
        float out_a  = mix(base.a,  blur_a,  strength);

        result = vec4(out_rgb, out_a);
    }
    else {
        // -----------------------------
        // EROSION (updated to use diamond for first ring)
        // -----------------------------
        int ang = (quality == 1) ? 4 : ((quality == 2) ? 6 : ((quality == 3) ? 12 : ((quality == 4) ? 16 : 24)));
        int radial_steps = quality * 4;

        float accum = base.a;
        float total_w = 1.0;

        for (int q = 1; q <= radial_steps; q++) {
            float t = float(q) / float(radial_steps);
            float dist = radius * t;

            float dir_accum = 0.0;
            if (quality == 1) {
                for (int i = 0; i < 4; i++) {
                    dir_accum += texture(TEXTURE, UV + DIRS4[i] * px * dist).a;
                }
            } else if (quality == 2) {
                for (int i = 0; i < 6; i++) {
                    dir_accum += texture(TEXTURE, UV + DIRS6[i] * px * dist).a;
                }
            } else if (quality == 3) {
                for (int i = 0; i < 12; i++) {
                    dir_accum += texture(TEXTURE, UV + DIRS12[i] * px * dist).a;
                }
            } else if (quality == 4) {
                for (int i = 0; i < 16; i++) {
                    dir_accum += texture(TEXTURE, UV + DIRS16[i] * px * dist).a;
                }
            } else {
                for (int i = 0; i < 24; i++) {
                    dir_accum += texture(TEXTURE, UV + DIRS24[i] * px * dist).a;
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
    vec4 final_result = result * modulate;
    
    // Apply tint as straight color addition (not multiplicative)
    // Tint is applied on top of the fully modulated result
    vec3 tinted_rgb = mix(final_result.rgb, tint_color, tint_strength);
    
    COLOR = vec4(tinted_rgb, final_result.a);
}