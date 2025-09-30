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

# --- Shadow Controls (mostly shader uniforms passthrough) ---
## The distance between the shadow and the source sprite
@export var distance: Vector2 = Vector2(3, 6):
    set = set_distance

## Scale multiplier for the shadow (1.0 = same size as source, >1.0 = larger shadow, <1.0 = smaller shadow)
@export_range(0.1, 3.0, 0.01, "or_less", "or_greater") var shadow_scale: float = 1.05:
    set = set_shadow_scale

## The opacity of the shadow (same as using alpha on the modulate property)
@export_range(0.0, 1.0, 0.01, "or_less", "or_greater") var opacity: float = 0.45:
    set = set_opacity

## Color override for the shadow
## [br]Unlike Modulate which multiplies the color, this directly sets the color.
## [br]Useful to make the shadow a single color, e.g. all grey.
## [br]Alpha channel defines the strength of the tint.
@export var tint: Color = Color(0.0, 0.0, 0.0, 1.0):
    set = set_tint
const TINT_COLOR_UNIFORM_NAME: String = "tint_color"  # Name of the uniform in the shader itself
const TINT_STRENGTH_UNIFORM_NAME: String = "tint_strength"  # Name of the uniform in the shader itself

# --- Shader Controls (optional, forwarded if present) ---
## Turns the blur into an internal feathering effect, making the blurring "erode" the texture instead of dilate it.
@export var internal_feather: bool = false:
    set = set_internal_feather
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

## Relative padding around the texture (0.0 = no padding, 0.2 = 20% more space around edges).
## [br]Useful if the blur effect is getting clipped by the edge of the texture.
@export_range(0.0, 1.0, 0.01, "or_less", "or_greater") var texture_padding: float = 0.0:
    set = set_texture_padding

## Click this to force a refresh in editor if the shadow is not showing
@export_tool_button("Force Refresh (Debug)", "Reload") var force_refresh_action: Callable = force_in_editor_refresh


func force_in_editor_refresh():
    if Engine.is_editor_hint():
        print("User triggered a refresh in editor for: ", name)
        _process(0.0)


@export_group("Extras Options")
## Whether to automatically follow the source sprite's transform (position, rotation, scale)
## [br]Disable if you want to handle the transform manually
## [br]Not that distance will have no effect if this is disabled
@export var sync_transform: bool = true
## Whether to automatically follow the source sprite's visibility
## [br]E.g. hide the shadow when the source sprite is not visible
@export var sync_visibility: bool = true
## Whether to automatically follow the source sprite's horizontal and vertical flips
@export var sync_flip: bool = true  # hflip/vflip
## Whether to automatically follow the source sprite's z_index/sorting (with a customizable z-offset)
@export var auto_z_index: bool = true
## The offset to apply to the z_index of the shadow (e.g. "always 1 below the source sprite")
@export var z_offset := -1  # place below source by default

# --- Internals ---
var _last_material: Material = null  # Used to detect materials changes
var _shader: Shader = preload("res://addons/lbg/godottools/dropshadow2d/advanced_blur.gdshader")
var _initialized: bool = false


func _ready() -> void:
    _initialize()


func _initialize() -> void:
    if _initialized:
        return
    _initialized = true

    if source_sprite == null and get_parent() is Sprite2D:
        source_sprite = get_parent() as Sprite2D

    update_texture_from_source_sprite()

    if material == null:
        # The blur of the shadow comes from a shader, so we need to create a shader material if it's not already set
        var mat: ShaderMaterial = ShaderMaterial.new()
        mat.shader = _shader
        material = mat

    # Keep our own color separate from opacity; combine into modulate at apply time
    _apply_opacity()

    # Nudge initial z based on source, if any
    _sync_z_index()


func _process(_delta: float) -> void:
    if not _initialized:
        print("Node: ", name, " was not initialized and has been initialized from _process")
        _initialize()
        return

    if not is_instance_valid(source_sprite):
        return

    if sync_transform:
        _update_transform_based_on_source_sprite()

    if material != _last_material:
        _last_material = material

    if sync_visibility:
        _on_source_visibility_changed()

    if auto_z_index:
        _sync_z_index()

    # Forward all shader parameters directly
    if material is ShaderMaterial:
        var sm := material as ShaderMaterial
        sm.set_shader_parameter(EROSION_UNIFORM_NAME, internal_feather)
        sm.set_shader_parameter(BLUR_RADIUS_UNIFORM_NAME, blur_radius)
        sm.set_shader_parameter(BLUR_STRENGTH_UNIFORM_NAME, blur_strength)
        sm.set_shader_parameter(QUALITY_UNIFORM_NAME, quality)
        sm.set_shader_parameter(TINT_COLOR_UNIFORM_NAME, Vector3(tint.r, tint.g, tint.b))
        sm.set_shader_parameter(TINT_STRENGTH_UNIFORM_NAME, tint.a)


## This is used to show a warning in the Scene tree/inspector if the source sprite is not assigned
func _get_configuration_warnings() -> PackedStringArray:
    var warnings: PackedStringArray = []
    if source_sprite == null:
        warnings.append("Assign a Source Sprite2D to cast a shadow.")
    if source_sprite and not (source_sprite is Sprite2D):
        warnings.append("Source must be a Sprite2D (AnimatedSprite2D is not supported in this version).")
    return warnings


## Hooks to the source sprite's signals  that are available
func _connect_source_signals() -> void:
    if not is_instance_valid(source_sprite):
        return
    source_sprite.visibility_changed.connect(_on_source_visibility_changed, CONNECT_DEFERRED)
    source_sprite.tree_exiting.connect(_on_source_tree_exiting, CONNECT_DEFERRED)


## Disconnects the source sprite's signals
## Used when replacing the source sprite with an other
func _disconnect_source_signals() -> void:
    if not is_instance_valid(source_sprite):
        return
    if source_sprite.visibility_changed.is_connected(_on_source_visibility_changed):
        source_sprite.visibility_changed.disconnect(_on_source_visibility_changed)
    if source_sprite.tree_exiting.is_connected(_on_source_tree_exiting):
        source_sprite.tree_exiting.disconnect(_on_source_tree_exiting)


func _on_source_visibility_changed() -> void:
    if sync_visibility:
        visible = source_sprite.visible


func _on_source_tree_exiting() -> void:
    source_sprite = null


## Updates the texture based on the source sprite's texture, adjusting for padding and centering
func update_texture_from_source_sprite() -> void:
    if not is_instance_valid(source_sprite):
        return

    # Copy basic texture properties
    texture = source_sprite.texture
    hframes = source_sprite.hframes
    vframes = source_sprite.vframes
    frame = source_sprite.frame
    if sync_flip:
        flip_h = source_sprite.flip_h
        flip_v = source_sprite.flip_v

    # Handle padding and centering
    if texture_padding > 0.0:
        # Get the original texture size
        var original_size = texture.get_size()

        # Calculate padding amount based on average of width and height
        var avg_dimension = (original_size.x + original_size.y) * 0.5
        var padding_amount = avg_dimension * texture_padding

        # Create padded region rect with negative coordinates to expand the area
        var padded_region = Rect2(Vector2(-padding_amount, -padding_amount), original_size + Vector2(padding_amount * 2, padding_amount * 2))

        # Enable region and set the padded rect
        region_enabled = true
        region_rect = padded_region

        # Copy centering and offset from source (region rect handles the positioning)
        centered = source_sprite.centered
        offset = source_sprite.offset
    else:
        # No padding - copy normally
        region_enabled = source_sprite.region_enabled
        if region_enabled:
            region_rect = source_sprite.region_rect
        centered = source_sprite.centered
        offset = source_sprite.offset


## Updates the transform based on the source sprite's transform
func _update_transform_based_on_source_sprite() -> void:
    if not is_instance_valid(source_sprite):
        return

    # Check if we're a descendant of the source sprite
    var is_descendant = source_sprite.is_ancestor_of(self)

    if is_descendant:
        # When we're a descendant, we inherit the parent's scale and rotation automatically
        # So we don't copy them - just apply our shadow scale multiplier
        scale = Vector2.ONE * shadow_scale
    else:
        # When we're not a descendant, copy everything normally and apply shadow scale
        global_transform = source_sprite.global_transform
        scale = source_sprite.scale * shadow_scale
        rotation = source_sprite.rotation

    # Apply the distance offset
    global_position = source_sprite.global_position + distance

    _sync_z_index()


## Syncs the initial z-index based on the source sprite's z-index
## This will for example make the shadow "always right below" the source sprite
func _sync_z_index() -> void:
    if not is_instance_valid(source_sprite):
        return
    if auto_z_index:
        z_index = source_sprite.z_index + z_offset
        z_as_relative = source_sprite.z_as_relative


func _apply_opacity() -> void:
    # Only alpha is controlled here; tint handles RGB, and the user can also opt to use regular color modulation directly.
    var m := modulate
    m.a = clamp(opacity, 0.0, 1.0)
    modulate = m


# -- Setters
func set_distance(v: Vector2) -> void:
    distance = v
    if sync_transform:
        # immediate position update
        _update_transform_based_on_source_sprite()


func set_shadow_scale(v: float) -> void:
    shadow_scale = v


func set_opacity(v: float) -> void:
    opacity = v
    _apply_opacity()


func set_internal_feather(v: bool) -> void:
    internal_feather = v


func set_blur_radius(v: float) -> void:
    blur_radius = v


func set_blur_strength(v: float) -> void:
    blur_strength = v


func set_quality(v: int) -> void:
    quality = v


func set_tint(v: Color) -> void:
    tint = v


func set_texture_padding(v: float) -> void:
    texture_padding = v
    update_texture_from_source_sprite()


# Optional convenience if you want to set tint & opacity together
func set_shadow_color(c: Color, a: float) -> void:
    tint = c
    opacity = a
    _apply_opacity()
