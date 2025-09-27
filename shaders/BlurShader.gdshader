shader_type canvas_item;

uniform float softness : hint_range(0.0, 10.0) = 0.2;
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 uv = UV;
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 one_pixel = vec2(1.0) / tex_size;

    // Get the original texture alpha
    float original_alpha = texture(TEXTURE, uv).a;

    // Skip processing if completely transparent
    if (original_alpha < 0.01) {
        COLOR = vec4(0.0);
    } else {
        // Simple 4-direction sampling for performance
        vec2 dirs[4] = vec2[](
            vec2(1.0, 0.0),
            vec2(0.0, 1.0),
            vec2(-1.0, 0.0),
            vec2(0.0, -1.0)
        );

        // Calculate distance to nearest transparent pixel (edge)
        float distance_to_edge = 1000.0;

        // Sample in 4 cardinal directions
        for (int i = 0; i < 4; i++) {
            vec2 direction = dirs[i];
            float step_size = 1.0;

            // Check increasing distances until we find transparency
            for (int step = 0; step < 20; step++) {
                vec2 offset = direction * step_size * one_pixel;
                float sample_alpha = texture(TEXTURE, uv + offset).a;

                if (sample_alpha < 0.5) {
                    distance_to_edge = min(distance_to_edge, step_size * length(one_pixel));
                    break;
                }

                step_size += 1.0;
            }
        }

        // Get the original texture color
        vec4 texture_color = texture(TEXTURE, uv);

        // COLOR already contains texture * modulate, so we can use it directly
        vec4 modulated_color = COLOR;

        // Apply tint if strength > 0
        vec4 final_color;
        if (tint_strength > 0.0) {
            // Mix between modulated color and tint color based on strength
            vec3 tinted_rgb = mix(modulated_color.rgb, tint_color, tint_strength);
            final_color = vec4(tinted_rgb, modulated_color.a);
        } else {
            final_color = modulated_color;
        }

        // If no edge was found
        if (distance_to_edge > 999.0) {
            COLOR = final_color;
        } else {
            // Apply feathering
            float max_feather_distance = softness * 0.1;
            float feather_factor = clamp(distance_to_edge / max_feather_distance, 0.0, 1.0);
            feather_factor = feather_factor * feather_factor; // Quadratic falloff

            // Apply the feathered alpha, preserving the final color
            float feathered_alpha = original_alpha * feather_factor;

            // Apply final color with feathered alpha
            COLOR = vec4(final_color.rgb, feathered_alpha * final_color.a);
        }
    }
}