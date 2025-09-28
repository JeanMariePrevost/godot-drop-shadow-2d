shader_type canvas_item;

// Blur mode selection (using enum hint for dropdown)
uniform int blur_mode : hint_enum("Cheap:0,Mobile:1,Quality:2") = 1;

// Shared parameters
uniform float softness : hint_range(0.0, 10.0) = 0.2;
uniform float range : hint_range(0.1, 5.0) = 1.0;  // Range parameter
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;

// Mode-specific parameters
uniform int quality : hint_enum("Low", "Medium", "High") = 1;

// Function to apply tint color
vec3 apply_tint(vec3 original_color, vec3 tint_color_val, float tint_strength_val) {
    if (tint_strength_val > 0.0) {
        return mix(original_color, tint_color_val, tint_strength_val);
    }
    return original_color;
}

// Improved mobile feathering mode with original sample count
float mobile_feather_edges(vec2 uv, vec2 tex_size, float softness_val, float range_val, float original_alpha, sampler2D tex) {
    vec2 one_pixel = vec2(1.0) / tex_size;

    // Skip processing if completely transparent using conditional math
    float should_process = step(0.01, original_alpha);
    if (should_process < 0.5) {
        return 0.0;
    }

    // Base distances to sample (original count, will be scaled by range)
    float base_distances[4] = float[](1.0, 3.0, 7.0, 15.0);

    // Calculate distance to nearest transparent pixel (edge)
    float distance_to_edge = 1000.0;

    // Sample in 4 cardinal directions (same as original)
    vec2 dirs[4] = vec2[](
        vec2(1.0, 0.0),
        vec2(0.0, 1.0),
        vec2(-1.0, 0.0),
        vec2(0.0, -1.0)
    );

    for (int i = 0; i < 4; i++) {
        vec2 direction = dirs[i];

        // Check pre-defined distances, scaled by range
        for (int s = 0; s < 4; s++) {
            // Scale the distance by the range parameter
            float scaled_distance = base_distances[s] * range_val;
            vec2 offset = direction * scaled_distance * one_pixel;
            float sample_alpha = texture(tex, uv + offset).a;

            if (sample_alpha < 0.5) {
                // If we found an edge, use interpolation between distances
                float prev_distance = s > 0 ? base_distances[s-1] * range_val : 0.0;
                // Smooth interpolation between previous and current distance
                float edge_distance = mix(prev_distance, scaled_distance, 0.5);
                distance_to_edge = min(distance_to_edge, edge_distance * length(one_pixel));
                break;
            }
        }
    }

    // If no edge was found, keep original alpha
    float no_edge_found = step(1000.0, distance_to_edge);
    if (no_edge_found > 0.5) {
        return original_alpha;
    }

    // Apply feathering with improved falloff
    // Scale max feather distance by range as well
    float max_feather_distance = softness_val * 0.1 * range_val;
    float feather_factor = clamp(distance_to_edge / max_feather_distance, 0.0, 1.0);
    // Smoother cubic falloff instead of quadratic
    feather_factor = feather_factor * feather_factor * (3.0 - 2.0 * feather_factor);

    // Apply the feathered alpha
    return original_alpha * feather_factor;
}

// Placeholder functions for other modes (to be implemented later)
float cheap_feather_edges(vec2 uv, vec2 tex_size, float softness_val, float range_val, float original_alpha, sampler2D tex) {
    // Placeholder for now - just return original alpha
    return original_alpha;
}

float quality_feather_edges(vec2 uv, vec2 tex_size, float softness_val, float range_val, int quality_val, float original_alpha, sampler2D tex) {
    // Placeholder for now - just return original alpha
    return original_alpha;
}

void fragment() {
    vec2 uv = UV;
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));

    // Get the original texture alpha
    float original_alpha = texture(TEXTURE, uv).a;

    // Skip processing if completely transparent
    if (original_alpha < 0.01) {
        COLOR = vec4(0.0);
    } else {
        // Pipeline step 1: Apply selected feathering mode
        float feathered_alpha;

        if (blur_mode == 0) {
            // Cheap mode (placeholder)
            feathered_alpha = cheap_feather_edges(uv, tex_size, softness, range, original_alpha, TEXTURE);
        } else if (blur_mode == 1) {
            // Mobile mode (currently implemented)
            feathered_alpha = mobile_feather_edges(uv, tex_size, softness, range, original_alpha, TEXTURE);
        } else {
            // Quality mode (placeholder)
            feathered_alpha = quality_feather_edges(uv, tex_size, softness, range, quality, original_alpha, TEXTURE);
        }

        // Pipeline step 2: Get the modulated color (COLOR already contains texture * modulate)
        vec4 modulated_color = COLOR;

        // Pipeline step 3: Apply tint
        vec3 final_rgb = apply_tint(modulated_color.rgb, tint_color, tint_strength);

        // Pipeline step 4: Combine RGB with feathered alpha
        COLOR = vec4(final_rgb, feathered_alpha * modulated_color.a);
    }
}