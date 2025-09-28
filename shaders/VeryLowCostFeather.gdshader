shader_type canvas_item;

uniform float softness : hint_range(0.0, 1.0) = 0.2;
uniform float range : hint_range(0.0, 20.0) = 5.0;

void fragment() {
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    
    // Sample the original texture
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Calculate distance from center (0-1 range)
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    float max_dist = distance(vec2(0.0, 0.0), center);
    float normalized_dist = dist / max_dist;
    
    // Apply range control - determines where softening starts
    // Higher range = softening starts closer to center
    float soft_start = 1.0 - (range / 20.0);
    
    // Make the outer edge creep in at high softness values
    // This effectively shrinks the "solid" area of the sprite
    float edge_creep = softness * 0.2; // Maximum 20% creep at full softness
    float adjusted_soft_start = soft_start - edge_creep;
    
    // Create edge factor (0 at center, 1 at edge)
    float edge_factor = smoothstep(adjusted_soft_start, 1.0, normalized_dist);
    
    // Apply softness with additional effect at high values
    float alpha_factor = 1.0 - edge_factor * softness;
    
    // Apply to alpha
    float final_alpha = tex_color.a * alpha_factor;
    
    COLOR = vec4(tex_color.rgb, final_alpha);
}