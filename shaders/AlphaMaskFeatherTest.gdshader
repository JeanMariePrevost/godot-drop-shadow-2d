shader_type canvas_item;

uniform float softness : hint_range(0.0, 1.0) = 0.2;
uniform float range : hint_range(0.0, 50.0) = 5.0;

void fragment() {
    vec2 uv = UV;
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 one_pixel = vec2(1.0) / tex_size;
    
    // Sample original texture
    vec4 original_color = texture(TEXTURE, uv);
    float original_alpha = original_color.a;
    

    
    // Calculate distance to nearest transparent pixel
    float distance_to_transparent = 1000.0;
    float max_search_distance = min(range * 2.0, max(tex_size.x, tex_size.y) * 0.5);
    
    // Search in concentric circles for transparent pixels
    for (float search_radius = 1.0; search_radius <= max_search_distance; search_radius += 1.0) {
        int samples = int(search_radius * 4.0); // More samples for larger radii
        float angle_step = 2.0 * 3.14159 / float(samples);
        
        for (float i = 0.0; i < float(samples); i++) {
            float angle = i * angle_step;
            vec2 offset = vec2(cos(angle), sin(angle)) * search_radius * one_pixel;
            
            float sample_alpha = texture(TEXTURE, uv + offset).a;
            
            // If we found a transparent pixel, update distance
            if (sample_alpha < 0.01) {
                distance_to_transparent = min(distance_to_transparent, search_radius);
                break;
            }
        }
        
        // Early exit if we've found a transparent pixel close enough
        if (distance_to_transparent < 1000.0) {
            break;
        }
    }
    

    
    // Create smooth alpha mask based on distance to transparent pixels
    float normalized_distance = min(distance_to_transparent / range, 1.0);
    float alpha_mask = smoothstep(0.0, 1.0, normalized_distance);
    
    // Apply softness by mixing original and blurred alpha
    float final_alpha = mix(original_alpha, original_alpha * alpha_mask, softness);
    
    COLOR = vec4(original_color.rgb, final_alpha);
}