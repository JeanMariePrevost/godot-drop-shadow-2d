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
    
    // Skip processing for fully opaque or transparent pixels
    float should_process = step(0.01, original_alpha) * step(original_alpha, 0.99);
    

    
    // Poisson disk sample points (normalized to unit circle)
    vec2 samples[16] = vec2[](
        vec2(-0.267261, 0.112385),
        vec2(0.112385, -0.267261),
        vec2(0.449446, 0.449446),
        vec2(-0.449446, -0.449446),
        vec2(0.674169, -0.224723),
        vec2(-0.224723, 0.674169),
        vec2(0.898892, 0.0),
        vec2(0.0, -0.898892),
        vec2(-0.674169, 0.224723),
        vec2(0.224723, -0.674169),
        vec2(-0.898892, 0.0),
        vec2(0.0, 0.898892),
        vec2(0.561807, 0.749076),
        vec2(-0.749076, 0.561807),
        vec2(-0.561807, -0.749076),
        vec2(0.749076, -0.561807)
    );
    
    // Calculate edge strength by sampling at different distances
    float edge_strength = 0.0;
    float max_edge_strength = 0.0;
    
    // Test at multiple distances to find the edge
    for (float dist = 1.0; dist <= range; dist += 1.0) {
        float samples_at_distance = 0.0;
        float alpha_diff_at_distance = 0.0;
        
        for (int i = 0; i < 16; i++) {
            // Scale sample point by current distance
            vec2 offset = samples[i] * dist * one_pixel;
            float sample_alpha = texture(TEXTURE, uv + offset).a;
            
            // Calculate alpha difference
            float alpha_diff = abs(sample_alpha - original_alpha);
            alpha_diff_at_distance += alpha_diff;
            samples_at_distance += 1.0;
        }
        
        // Average alpha difference at this distance
        float avg_diff = alpha_diff_at_distance / samples_at_distance;
        
        // Track maximum edge strength found
        if (avg_diff > max_edge_strength) {
            max_edge_strength = avg_diff;
        }
        
        // Accumulate edge strength with distance falloff
        edge_strength += avg_diff * (1.0 - dist/range);
    }
    
    // If we found significant edge strength, apply blur
    if (edge_strength > 0.01) {
        // Apply Poisson blur with radius based on range
        vec4 blurred_color = vec4(0.0);
        float total_weight = 0.0;
        
        // Center sample (original pixel)
        blurred_color += original_color * 0.25;
        total_weight += 0.25;
        
        // Sample in Poisson disk pattern
        for (int i = 0; i < 16; i++) {
            // Calculate distance-based weight
            float sample_distance = length(samples[i]);
            float weight = exp(-sample_distance * sample_distance * 2.0) * 0.05;
            
            // Scale sample point by range
            vec2 offset = samples[i] * range * one_pixel;
            
            // Sample texture
            vec4 sample_color = texture(TEXTURE, uv + offset);
            
            // Accumulate weighted sample
            blurred_color += sample_color * weight;
            total_weight += weight;
        }
        
        // Normalize
        blurred_color /= total_weight;
        
        // Apply softness based on edge strength
        float blur_amount = min(edge_strength * 5.0, 1.0) * softness;
        original_color = mix(original_color, blurred_color, blur_amount);
    }
    
    // Set final color
    COLOR = original_color;
}