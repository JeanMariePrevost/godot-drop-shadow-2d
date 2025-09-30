# addons/dropshadow2d/DropShadow2D.gd
@tool
extends Sprite2D
class_name DropShadow2D

## ---------- Usage ----------
## First, add a new DropShadow2D node to the scene.
## OR,
## Create a separate Sprite2D node and attach this script to the shadow Sprite2D.
## (It can be placed anywhere in the tree, for example as a sibling or child of the target Sprite2D.)
##
## Select the new shadow now and assign the source Sprite2D to the `source_sprite` property in the inspector.
## Set `source_sprite` to the Sprite2D you want to shadow.
##
## NOTE: Due to a current bug in Godot, you might have to click the "Force Update" button in the inspector to see the changes,
## or refresh the scene or even reboot the editor in some cases.
## The error will be something like "The value of property "force_refresh_action" is Nil, but Callable was expected."
##
## You can now tweak the various parameters on the script to change how the "shadow" Sprite2D behaves.

# --- Source & syncing with source ---
## Set this to the Sprite2D you want to create a shadow for.
@export var source_sprite: Sprite2D:
    set(value):
        if source_sprite == value:
            return
        _disconnect_source_signals()
        source_sprite = value
        _connect_source_signals()
        _mark_all_dirty()

# --- Shadow Controls (mostly shader uniforms passthrough) ---
## The distance between the shadow and the source sprite
@export var distance: Vector2 = Vector2(3, 6):
    set = set_distance

## Scale multiplier for the shadow (1.0 = same size as source, >1.0 = larger shadow, <1.0 = smaller shadow)
@export_range(0.1, 3.0, 0.01, "or_less", "or_greater") var shadow_scale: float = 1.05:
    set = set_shadow_scale

## The opacity of the shadow (same as using alpha on the modulate property)
@export_range(0.0, 1.0, 0.01, "or_less", "or_greater") var opacity: float = 0.3:
    set = set_opacity

## Color override for the shadow (RGB=color, Alpha=strength 0.0-1.0)
@export var tint: Color = Color(0.0, 0.0, 0.0, 1.0):
    set = set_tint
const TINT_COLOR_UNIFORM_NAME: String = "tint_color"  # Name of the uniform in the shader itself
const TINT_STRENGTH_UNIFORM_NAME: String = "tint_strength"  # Name of the uniform in the shader itself

# --- Shader Controls (optional, forwarded if present) ---
## Erosion creates an "internal feathering" effect, making the shadow smaller.
## [br]Useful for when you have no breathing room on the edge of the sprite for the blur.
@export var erosion_mode: bool = false:
    set = set_erosion_mode
const EROSION_UNIFORM_NAME: String = "erosion"  # Name of the uniform in the shader itself

## The radius of the blur effect in pixels
@export_range(0, 50, 0.01, "or_less", "or_greater") var blur_radius: float = 4.0:
    set = set_blur_radius
const BLUR_RADIUS_UNIFORM_NAME: String = "radius"  # Name of the uniform in the shader itself

## The strength of the blur effect (0.0 = no blur, 1.0 = full blur)
@export_range(0.0, 1.0, 0.01, "or_less", "or_greater") var blur_strength: float = 0.5:
    set = set_blur_strength
const BLUR_STRENGTH_UNIFORM_NAME: String = "strength"  # Name of the uniform in the shader itself

## Quality level for blur effects.
## [br]0=Simple fade (fixed cost, scales well)
## [br]1=Low quality blur (2 rings: 4+6 taps)
## [br]2=Medium quality blur (3 rings: 4+6+12 taps)
## [br]3=High quality blur (4 rings: 4+6+12+16 taps)
## [br]4=Ultra quality blur (5 rings: 4+6+12+16+24 taps)
@export_range(0, 4, 1) var quality: int = 2:
    set = set_quality
const QUALITY_UNIFORM_NAME: String = "quality"  # Name of the uniform in the shader itself

## Click this to force a refresh in editor if the shadow is not showing
@export_tool_button("Force Refresh (Debug)", "Reload") var force_refresh_action: Callable = force_in_editor_refresh


func force_in_editor_refresh():
    if Engine.is_editor_hint():
        print("User triggered a refresh in editor for: ", name)
        _process(0.0)


@export_group("Extras Options")
## Whether to automatically copy the source sprite's z_index/sorting
@export var use_source_sorting: bool = true
## Whether to automatically mirror the source sprite's texture and frame
@export var mirror_texture: bool = true
## Whether to automatically mirror the source sprite's transform (position, rotation, scale)
@export var mirror_transform: bool = true
## Whether to automatically mirror the source sprite's visibility
@export var mirror_visibility: bool = true
## Whether to automatically follow the source sprite's horizontal and vertical flips
@export var follow_flips: bool = true  # hflip/vflip

# --- Layering / Sorting ---
@export var z_bias := -1  # place below source by default

# --- Internals ---
var _tex_dirty: bool = true
var _vis_dirty: bool = true
var _last_material: Material = null  # Used to detect materials changes
var _shader: Shader = preload("res://shaders/DilationErosionBlur.gdshader")
var _initialized: bool = false


func _ready() -> void:
    _initialize()


func _initialize() -> void:
    if _initialized:
        return
    _initialized = true

    if source_sprite == null and get_parent() is Sprite2D:
        source_sprite = get_parent() as Sprite2D

    if material == null:
        # The blur of the shadow comes from a shader, so we need to create a shader material if it's not already set
        var mat: ShaderMaterial = ShaderMaterial.new()
        mat.shader = _shader
        material = mat

    # Keep our own color separate from opacity; combine into modulate at apply time
    _apply_opacity()

    # Nudge initial z based on source, if any
    _sync_initial_z()
    _mark_all_dirty()


func _process(_delta: float) -> void:
    if not _initialized:
        print("Node: ", name, " was not initialized and has been initialized from _process")
        _initialize()
        return

    if not is_instance_valid(source_sprite):
        return

    if mirror_texture and _tex_dirty:
        _copy_texture_like()
        _tex_dirty = false

    if mirror_transform:
        _copy_transform_like()

    if mirror_visibility and _vis_dirty:
        visible = source_sprite.visible
        _vis_dirty = false

    if material != _last_material:
        _last_material = material

    # Always re-apply position offset after transform sync
    _apply_distance()

    # Forward all shader parameters directly (no dirty flags needed)
    if material is ShaderMaterial:
        var sm := material as ShaderMaterial
        sm.set_shader_parameter(EROSION_UNIFORM_NAME, erosion_mode)
        sm.set_shader_parameter(BLUR_RADIUS_UNIFORM_NAME, blur_radius)
        sm.set_shader_parameter(BLUR_STRENGTH_UNIFORM_NAME, blur_strength)
        sm.set_shader_parameter(QUALITY_UNIFORM_NAME, quality)
        sm.set_shader_parameter(TINT_COLOR_UNIFORM_NAME, Vector3(tint.r, tint.g, tint.b))
        sm.set_shader_parameter(TINT_STRENGTH_UNIFORM_NAME, tint.a)


func _get_configuration_warnings() -> PackedStringArray:
    var warnings: PackedStringArray = []
    if source_sprite == null:
        warnings.append("Assign a Source Sprite2D to cast a shadow.")
    if source_sprite and not (source_sprite is Sprite2D):
        warnings.append("Source must be a Sprite2D (AnimatedSprite2D is not supported in this version).")
    return warnings


# -- Dirty flags helpers (only for texture and visibility)
func _mark_all_dirty() -> void:
    _tex_dirty = true
    _vis_dirty = true


# -- Source signals (cheap + robust)
func _connect_source_signals() -> void:
    if not is_instance_valid(source_sprite):
        return
    source_sprite.visibility_changed.connect(_on_source_visibility_changed, CONNECT_DEFERRED)
    source_sprite.tree_exiting.connect(_on_source_tree_exiting, CONNECT_DEFERRED)


func _disconnect_source_signals() -> void:
    if not is_instance_valid(source_sprite):
        return
    if source_sprite.visibility_changed.is_connected(_on_source_visibility_changed):
        source_sprite.visibility_changed.disconnect(_on_source_visibility_changed)
    if source_sprite.tree_exiting.is_connected(_on_source_tree_exiting):
        source_sprite.tree_exiting.disconnect(_on_source_tree_exiting)


func _on_source_visibility_changed() -> void:
    _vis_dirty = true


func _on_source_tree_exiting() -> void:
    source_sprite = null


# -- Copy ops
func _copy_texture_like() -> void:
    if not is_instance_valid(source_sprite):
        return
    texture = source_sprite.texture
    centered = source_sprite.centered
    offset = offset  # keep our own offset; just mirroring flag names
    hframes = source_sprite.hframes
    vframes = source_sprite.vframes
    frame = source_sprite.frame
    region_enabled = source_sprite.region_enabled
    if region_enabled:
        region_rect = source_sprite.region_rect
    if follow_flips:
        flip_h = source_sprite.flip_h
        flip_v = source_sprite.flip_v


func _copy_transform_like() -> void:
    if not is_instance_valid(source_sprite):
        return

    # Check if we're a direct child of the source sprite
    var is_direct_child = get_parent() == source_sprite

    if is_direct_child:
        # When we're a direct child, we inherit the parent's scale automatically
        # So we only copy rotation, not scale or global_transform
        rotation = source_sprite.rotation
        # Apply shadow scale multiplier to the inherited scale
        scale = Vector2.ONE * shadow_scale
    else:
        # When we're not a direct child, copy everything normally and apply shadow scale
        global_transform = source_sprite.global_transform
        scale = source_sprite.scale * shadow_scale
        rotation = source_sprite.rotation

    _sync_initial_z()


func _sync_initial_z() -> void:
    if not is_instance_valid(source_sprite):
        return
    if use_source_sorting:
        z_index = source_sprite.z_index + z_bias
        z_as_relative = source_sprite.z_as_relative


# -- Offset / Opacity / Color
func _apply_distance() -> void:
    if not is_instance_valid(source_sprite):
        return

    # apply offset in world space (doesn't rotate with the sprite)
    global_position = source_sprite.global_position + distance


func _apply_opacity() -> void:
    # Only alpha is controlled here; tint handles RGB.
    var m := modulate
    m.a = clamp(opacity, 0.0, 1.0)
    modulate = m


# -- Setters
func set_distance(v: Vector2) -> void:
    distance = v
    # immediate position update
    _apply_distance()


func set_shadow_scale(v: float) -> void:
    shadow_scale = v


func set_opacity(v: float) -> void:
    opacity = v
    _apply_opacity()


func set_erosion_mode(v: bool) -> void:
    erosion_mode = v


func set_blur_radius(v: float) -> void:
    blur_radius = v


func set_blur_strength(v: float) -> void:
    blur_strength = v


func set_quality(v: int) -> void:
    quality = v


func set_tint(v: Color) -> void:
    tint = v


# Optional convenience if you want to set tint & opacity together
func set_shadow_color(c: Color, a: float) -> void:
    tint = c
    opacity = a
    _apply_opacity()
