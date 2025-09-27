# addons/dropshadow2d/DropShadow2D.gd
@tool
extends Sprite2D
class_name DropShadow2D

## ---------- Usage ----------
## Add a DropShadow2D as a sibling or child.
## Set `source_sprite` to the Sprite2D you want to shadow.
## Tweak `offset`, `opacity`; plug a blur shader later (uses `shadow_softness` uniform).
##
## Notes:
## - Offset is applied in GLOBAL space by default (so rotating the sprite
##   doesn't rotate the shadow direction). Toggle with `offset_uses_global_space`.
## - Opacity is applied via this node's modulate.a (cheap, predictable).
## - Softness is a shader uniform (optional). If the material has a "shadow_softness"
##   uniform, this node will set it; otherwise it’s harmlessly ignored.

# --- Source & Sync ---
@export var source_sprite: Sprite2D:
    set(value):
        if source_sprite == value:
            return
        _disconnect_source_signals()
        source_sprite = value
        _connect_source_signals()
        _mark_all_dirty()

# Mirror texture/frame/transform every frame (cheap) or only on change (later optimization)
@export var mirror_texture := true
@export var mirror_transform := true
@export var mirror_visibility := true
@export var follow_flips := true  # hflip/vflip

# --- Shadow Controls (node-level) ---
@export_group("Shadow Controls")
@export var distance: Vector2 = Vector2(6, 6):
    set = set_distance
@export var offset_uses_global_space := true  # true = offset not rotated with the sprite
@export_range(0.0, 1.0, 0.01) var opacity := 0.5:
    set = set_opacity
@export var color_tint := Color.BLACK  # allows tinted shadows; alpha is ignored (we use `opacity`)

# --- Shader Controls (optional, forwarded if present) ---
@export_group("Shader Controls")
@export var softness := 4.0:
    set = set_softness  # forwarded to "shadow_softness" if exists
const SOFTNESS_UNIFORM := "shadow_softness"

# --- Layering / Sorting ---
@export_group("Z & Sorting")
@export var z_bias := -1  # place below source by default
@export var use_source_sorting := true

@export var editor_jank_hack: bool:  # TODO: Use a proper button with inspector plugin instead of this hack
    set(value):
        if Engine.is_editor_hint() and value:
            print("User triggered a refresh in editor for: ", name)
            _process(0.0)
            editor_jank_hack = false  # reset

# --- Internals ---
var _tex_dirty := true
var _vis_dirty := true
var _soft_dirty := true
var _last_material: Material  # Used to detect materials changes
var _valid_shader: bool = false

var _initialized: bool = false


func _ready() -> void:
    _initialize()


func _notification(_what: int) -> void:
    if Engine.is_editor_hint() and _initialized == false:
        _initialize()  # Only force initialization in editor


func _initialize() -> void:
    if _initialized:
        return
    _initialized = true

    print("Node: ", name, " is initializing")

    if material == null:
        # The blur of the shadow comes from a shader, so we need to create a shader material if it's not already set
        var mat: ShaderMaterial = ShaderMaterial.new()
        mat.shader = load("res://shaders/BlurShader.gdshader")
        material = mat
        print("Node: ", name, " has been given a shader material")
        validate_shader_signature()

    # Keep our own color separate from opacity; combine into modulate at apply time
    _apply_opacity()
    _apply_color_tint()

    # Nudge initial z based on source, if any
    _sync_initial_z()
    _mark_all_dirty()


func validate_shader_signature() -> void:
    print("Node: ", name, " is validating shader signature")
    if material is ShaderMaterial:
        var sm: ShaderMaterial = material
        var params: Array = sm.shader.get_shader_uniform_list(false)
        _valid_shader = false
        for p in params:
            if p.name == "shadow_softness":
                _valid_shader = true
                _soft_dirty = true
                break
    if _valid_shader:
        print("Node: ", name, " has a valid shader signature")
    else:
        print("Node: ", name, " has an invalid shader signature")


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
        validate_shader_signature()

    # Always re-apply position offset after transform sync
    _apply_distance()

    # Forward softness to shader if available and dirty
    if _soft_dirty:
        _forward_softness_to_shader()
        _soft_dirty = false


func _get_configuration_warnings() -> PackedStringArray:
    var warnings: PackedStringArray = []
    if source_sprite == null:
        warnings.append("Assign a Source Sprite2D to cast a shadow.")
    if source_sprite and not (source_sprite is Sprite2D):
        warnings.append("Source must be a Sprite2D (AnimatedSprite2D is not supported in this version).")
    if material is ShaderMaterial and not _valid_shader:
        warnings.append("Shader does not expose the shadow_softness uniform.")
    return warnings


# -- Dirty flags helpers
func _mark_all_dirty() -> void:
    _tex_dirty = true
    _vis_dirty = true
    _soft_dirty = true


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
    # Copy scale/rotation from source
    global_transform = source_sprite.global_transform
    scale = source_sprite.scale
    rotation = source_sprite.rotation
    # print("Source sprite rotation: ", source_sprite.rotation, " | Shadow sprite rotation: ", rotation)
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
    if offset_uses_global_space:
        # apply offset in world space (doesn’t rotate with the sprite)
        global_position = source_sprite.global_position + distance
    else:
        # apply offset in the source’s local space (rotates with the sprite)
        var local_off := distance.rotated(source_sprite.global_rotation)
        global_position = source_sprite.global_position + local_off


func _apply_opacity() -> void:
    # Only alpha is controlled here; color_tint handles RGB.
    var m := modulate
    m.a = clamp(opacity, 0.0, 1.0)
    modulate = m


func _apply_color_tint() -> void:
    # Keep alpha from opacity; use only RGB from tint color.
    var m := modulate
    m.r = color_tint.r
    m.g = color_tint.g
    m.b = color_tint.b
    # alpha left to _apply_opacity()
    modulate = m


# -- Shader uniform forwarding (optional)
func _forward_softness_to_shader() -> void:
    if material == null:
        return
    if material is ShaderMaterial:
        var sm := material as ShaderMaterial
        # Only set if the uniform exists (safe no-op otherwise)
        if sm.shader.get_shader_uniform_list(false).has(SOFTNESS_UNIFORM):
            sm.set_shader_parameter(SOFTNESS_UNIFORM, softness)


# -- Setters
func set_distance(v: Vector2) -> void:
    distance = v
    # immediate position update
    _apply_distance()


func set_opacity(v: float) -> void:
    opacity = v
    _apply_opacity()


func set_softness(v: float) -> void:
    softness = v
    _soft_dirty = true


# Optional convenience if you want to set tint & opacity together
func set_shadow_color(c: Color, a: float) -> void:
    color_tint = c
    opacity = a
    _apply_color_tint()
    _apply_opacity()
