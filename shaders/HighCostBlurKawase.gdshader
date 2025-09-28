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
    
    // Calculate kernel size based on range
    float kernel_size = max(1.0, range * 0.5);
    
    // Kawase blur samples four corners at increasing distances
    // First level samples
    vec2 offset1 = vec2(kernel_size, kernel_size) * one_pixel;
    vec2 offset2 = vec2(kernel_size, -kernel_size) * one_pixel;
    vec2 offset3 = vec2(-kernel_size, kernel_size) * one_pixel;
    vec2 offset4 = vec2(-kernel_size, -kernel_size) * one_pixel;
    
    // Sample at four corners
    float sample1 = texture(TEXTURE, uv + offset1).a;
    float sample2 = texture(TEXTURE, uv + offset2).a;
    float sample3 = texture(TEXTURE, uv + offset3).a;
    float sample4 = texture(TEXTURE, uv + offset4).a;
    
    // Average the four corner samples
    float level1 = (sample1 + sample2 + sample3 + sample4) * 0.25;
    
    // Second level samples (larger kernel)
    float kernel_size2 = kernel_size * 2.0;
    vec2 offset5 = vec2(kernel_size2, kernel_size2) * one_pixel;
    vec2 offset6 = vec2(kernel_size2, -kernel_size2) * one_pixel;
    vec2 offset7 = vec2(-kernel_size2, kernel_size2) * one_pixel;
    vec2 offset8 = vec2(-kernel_size2, -kernel_size2) * one_pixel;
    
    // Sample at four corners with larger kernel
    float sample5 = texture(TEXTURE, uv + offset5).a;
    float sample6 = texture(TEXTURE, uv + offset6).a;
    float sample7 = texture(TEXTURE, uv + offset7).a;
    float sample8 = texture(TEXTURE, uv + offset8).a;
    
    // Average the four corner samples
    float level2 = (sample5 + sample6 + sample7 + sample8) * 0.25;
    
    // Third level samples (even larger kernel)
    float kernel_size3 = kernel_size * 4.0;
    vec2 offset9 = vec2(kernel_size3, kernel_size3) * one_pixel;
    vec2 offset10 = vec2(kernel_size3, -kernel_size3) * one_pixel;
    vec2 offset11 = vec2(-kernel_size3, kernel_size3) * one_pixel;
    vec2 offset12 = vec2(-kernel_size3, -kernel_size3) * one_pixel;
    
    // Sample at four corners with even larger kernel
    float sample9 = texture(TEXTURE, uv + offset9).a;
    float sample10 = texture(TEXTURE, uv + offset10).a;
    float sample11 = texture(TEXTURE, uv + offset11).a;
    float sample12 = texture(TEXTURE, uv + offset12).a;
    
    // Average the four corner samples
    float level3 = (sample9 + sample10 + sample11 + sample12) * 0.25;
    
    // Combine levels with weights (more weight to closer samples)
    float blurred_alpha = original_alpha * 0.4 + level1 * 0.3 + level2 * 0.2 + level3 * 0.1;
    
    // Apply softness by mixing original and blurred alpha
    float final_alpha = mix(original_alpha, blurred_alpha, softness);
    
    // Keep original RGB but with blurred alpha
    COLOR = vec4(original_color.rgb, final_alpha);
}