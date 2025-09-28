shader_type canvas_item;

uniform bool is_dilation = true;  // Toggle: true for dilation, false for erosion
uniform int quality : hint_range(1, 5) = 2;  // Number of rings (quality level)
uniform float distance : hint_range(0.1, 20.0) = 5.0;  // Total distance covered by all rings
uniform float strength : hint_range(0.0, 1.0) = 0.8;  // Overall strength of the effect

void fragment() {
    // Start with the center pixel
    vec4 center_color = texture(TEXTURE, UV);
    vec4 result = center_color;
    float total_weight = 1.0;  // Start with weight 1.0 for center pixel
    
    // Calculate the step size between rings based on total distance and quality
    float ring_step = distance / float(quality);
    
    // Predefined offsets for circular sampling pattern (normalized to unit distance)
    // Ring 1 (4 samples)
    const vec2 ring1_norm[4] = vec2[](vec2(1, 0), vec2(-1, 0), vec2(0, 1), vec2(0, -1));
    
    // Ring 2 (8 samples)
    const vec2 ring2_norm[8] = vec2[](vec2(1, 1), vec2(1, -1), vec2(-1, 1), vec2(-1, -1),
                                      vec2(2, 0), vec2(-2, 0), vec2(0, 2), vec2(0, -2));
    
    // Ring 3 (12 samples)
    const vec2 ring3_norm[12] = vec2[](vec2(2, 1), vec2(2, -1), vec2(-2, 1), vec2(-2, -1),
                                       vec2(1, 2), vec2(1, -2), vec2(-1, 2), vec2(-1, -2),
                                       vec2(3, 0), vec2(-3, 0), vec2(0, 3), vec2(0, -3));
    
    // Ring 4 (16 samples)
    const vec2 ring4_norm[16] = vec2[](vec2(2, 2), vec2(2, -2), vec2(-2, 2), vec2(-2, -2),
                                       vec2(3, 1), vec2(3, -1), vec2(-3, 1), vec2(-3, -1),
                                       vec2(1, 3), vec2(1, -3), vec2(-1, 3), vec2(-1, -3),
                                       vec2(4, 0), vec2(-4, 0), vec2(0, 4), vec2(0, -4));
    
    // Ring 5 (20 samples)
    const vec2 ring5_norm[20] = vec2[](vec2(3, 2), vec2(3, -2), vec2(-3, 2), vec2(-3, -2),
                                       vec2(2, 3), vec2(2, -3), vec2(-2, 3), vec2(-2, -3),
                                       vec2(4, 1), vec2(4, -1), vec2(-4, 1), vec2(-4, -1),
                                       vec2(1, 4), vec2(1, -4), vec2(-1, 4), vec2(-1, -4),
                                       vec2(5, 0), vec2(-5, 0), vec2(0, 5), vec2(0, -5));
    
    // Sample based on quality level, scaling each ring's distance
    // Ring 1
    if (quality >= 1) {
        float current_ring_distance = ring_step;
        // Calculate weight for this ring (closer to center = higher weight)
        float ring_weight = strength * (1.0 - (1.0 / float(quality + 1)));
        
        for (int i = 0; i < 4; i++) {
            vec2 offset = ring1_norm[i] * current_ring_distance * TEXTURE_PIXEL_SIZE;
            vec4 sample = texture(TEXTURE, UV + offset);
            
            if (is_dilation) {
                // For dilation blur: blend based on weight
                result = mix(result, max(result, sample), ring_weight);
            } else {
                // For erosion blur: blend based on weight
                result = mix(result, min(result, sample), ring_weight);
            }
        }
        total_weight += ring_weight * 4.0;
    }
    
    // Ring 2
    if (quality >= 2) {
        float current_ring_distance = ring_step * 2.0;
        // Calculate weight for this ring (progressively lower)
        float ring_weight = strength * (1.0 - (2.0 / float(quality + 1)));
        
        for (int i = 0; i < 8; i++) {
            vec2 offset = ring2_norm[i] * (current_ring_distance / 2.0) * TEXTURE_PIXEL_SIZE;
            vec4 sample = texture(TEXTURE, UV + offset);
            
            if (is_dilation) {
                result = mix(result, max(result, sample), ring_weight);
            } else {
                result = mix(result, min(result, sample), ring_weight);
            }
        }
        total_weight += ring_weight * 8.0;
    }
    
    // Ring 3
    if (quality >= 3) {
        float current_ring_distance = ring_step * 3.0;
        // Calculate weight for this ring (progressively lower)
        float ring_weight = strength * (1.0 - (3.0 / float(quality + 1)));
        
        for (int i = 0; i < 12; i++) {
            vec2 offset = ring3_norm[i] * (current_ring_distance / 3.0) * TEXTURE_PIXEL_SIZE;
            vec4 sample = texture(TEXTURE, UV + offset);
            
            if (is_dilation) {
                result = mix(result, max(result, sample), ring_weight);
            } else {
                result = mix(result, min(result, sample), ring_weight);
            }
        }
        total_weight += ring_weight * 12.0;
    }
    
    // Ring 4
    if (quality >= 4) {
        float current_ring_distance = ring_step * 4.0;
        // Calculate weight for this ring (progressively lower)
        float ring_weight = strength * (1.0 - (4.0 / float(quality + 1)));
        
        for (int i = 0; i < 16; i++) {
            vec2 offset = ring4_norm[i] * (current_ring_distance / 4.0) * TEXTURE_PIXEL_SIZE;
            vec4 sample = texture(TEXTURE, UV + offset);
            
            if (is_dilation) {
                result = mix(result, max(result, sample), ring_weight);
            } else {
                result = mix(result, min(result, sample), ring_weight);
            }
        }
        total_weight += ring_weight * 16.0;
    }
    
    // Ring 5
    if (quality >= 5) {
        float current_ring_distance = ring_step * 5.0;
        // Calculate weight for this ring (progressively lower)
        float ring_weight = strength * (1.0 - (5.0 / float(quality + 1)));
        
        for (int i = 0; i < 20; i++) {
            vec2 offset = ring5_norm[i] * (current_ring_distance / 5.0) * TEXTURE_PIXEL_SIZE;
            vec4 sample = texture(TEXTURE, UV + offset);
            
            if (is_dilation) {
                result = mix(result, max(result, sample), ring_weight);
            } else {
                result = mix(result, min(result, sample), ring_weight);
            }
        }
        total_weight += ring_weight * 20.0;
    }
    
    // Normalize the result
    COLOR = result / total_weight;
}