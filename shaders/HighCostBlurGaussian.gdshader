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
    
    // Gaussian weights for circular sampling
    // These are pre-calculated for a 2D Gaussian distribution
    vec2 samples[12] = vec2[](
        vec2(0.0, 1.0),    // 12 o'clock
        vec2(0.866, 0.5),  // 2 o'clock
        vec2(0.866, -0.5), // 4 o'clock
        vec2(0.0, -1.0),   // 6 o'clock
        vec2(-0.866, -0.5),// 8 o'clock
        vec2(-0.866, 0.5), // 10 o'clock
        vec2(0.0, 2.0),    // 12 o'clock (farther)
        vec2(1.732, 1.0),  // 2 o'clock (farther)
        vec2(1.732, -1.0), // 4 o'clock (farther)
        vec2(0.0, -2.0),   // 6 o'clock (farther)
        vec2(-1.732, -1.0),// 8 o'clock (farther)
        vec2(-1.732, 1.0)  // 10 o'clock (farther)
    );
    
    // Weights for the samples (closer samples have higher weight)
    float weights[13] = float[](0.25, 0.1, 0.1, 0.1, 0.1, 0.1, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.0);
    
    // Calculate actual pixel radius based on range
    float pixel_radius = max(1.0, range);
    
    // Start with center sample
    float blurred_alpha = original_alpha * weights[0];
    float total_weight = weights[0];
    
    // Sample in circular pattern
    for (int i = 0; i < 12; i++) {
        // Scale sample by range
        vec2 offset = samples[i] * one_pixel * pixel_radius;
        
        // Sample texture
        float sample_alpha = texture(TEXTURE, uv + offset).a;
        
        // Apply weight and accumulate
        blurred_alpha += sample_alpha * weights[i+1];
        total_weight += weights[i+1];
    }
    
    // Normalize
    blurred_alpha /= total_weight;
    
    // Apply softness by mixing original and blurred alpha
    float final_alpha = mix(original_alpha, blurred_alpha, softness);
    
    // Keep original RGB but with blurred alpha
    COLOR = vec4(original_color.rgb, final_alpha);
}