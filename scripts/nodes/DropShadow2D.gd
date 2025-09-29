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

## Whether to automatically copy the source sprite's z_index/sorting
@export var use_source_sorting := true
## Whether to automatically mirror the source sprite's texture and frame
@export var mirror_texture := true
## Whether to automatically mirror the source sprite's transform (position, rotation, scale)
@export var mirror_transform := true
## Whether to automatically mirror the source sprite's visibility
@export var mirror_visibility := true
## Whether to automatically follow the source sprite's horizontal and vertical flips
@export var follow_flips := true  # hflip/vflip

## Click this to force a refresh in editor if the shadow is not showing
@export_tool_button("Force Refresh (Debug)", "Reload") var force_refresh_action = force_in_editor_refresh


func force_in_editor_refresh():
	if Engine.is_editor_hint():
		print("User triggered a refresh in editor for: ", name)
		_process(0.0)


# --- Shadow Controls (node-level) ---
@export_group("Shadow Controls")
## The distance between the shadow and the source sprite
@export var distance: Vector2 = Vector2(6, 6):
	set = set_distance

## The opacity of the shadow (same as using alpha on the modulate property)
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.5:
	set = set_opacity

## Color override for the shadow (RGB=color, Alpha=strength 0.0-1.0)
@export var tint: Color = Color(0.0, 0.0, 0.0, 1.0):
	set = set_tint
const TINT_COLOR_UNIFORM_NAME: String = "tint_color"  # Name of the uniform in the shader itself
const TINT_STRENGTH_UNIFORM_NAME: String = "tint_strength"  # Name of the uniform in the shader itself

# --- Shader Controls (optional, forwarded if present) ---
## The radius of the blur effect in pixels
@export_range(0, 50, 0.01) var blur_radius: float = 4.0:
	set = set_blur_radius
const BLUR_RADIUS_UNIFORM_NAME: String = "radius"  # Name of the uniform in the shader itself

## The strength of the blur effect (0.0 = no blur, 1.0 = full blur)
@export_range(0.0, 1.0, 0.01) var blur_strength: float = 0.5:
	set = set_blur_strength
const BLUR_STRENGTH_UNIFORM_NAME: String = "strength"  # Name of the uniform in the shader itself

## Quality level for blur effects. 0=Simple fade (O(1) cost, scales well), 1-3=Multi-sample blur (higher cost, better quality)
@export_range(0, 3, 1) var quality: int = 2:
	set = set_quality
const QUALITY_UNIFORM_NAME: String = "quality"  # Name of the uniform in the shader itself

# --- Layering / Sorting ---
@export_group("Z & Sorting")
@export var z_bias := -1  # place below source by default

# --- Internals ---
var _tex_dirty: bool = true
var _vis_dirty: bool = true
var _blur_radius_dirty: bool = true
var _blur_strength_dirty: bool = true
var _quality_dirty: bool = true
var _tint_dirty: bool = true
var _last_material: Material = null  # Used to detect materials changes
var _shader: Shader = preload("res://shaders/DilationErosionBlur.gdshader")
var _initialized: bool = false

# --- Shader Validation ---
var _shader_has_blur_radius_uniform: bool = false
var _shader_has_blur_strength_uniform: bool = false
var _shader_has_quality_uniform: bool = false
var _shader_has_tint_color_uniform: bool = false
var _shader_has_tint_strength_uniform: bool = false
var _valid_shader: bool = false


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
		mat.shader = _shader
		material = mat
		print("Node: ", name, " has been given a shader material")
		validate_shader_signature()

	# Keep our own color separate from opacity; combine into modulate at apply time
	_apply_opacity()

	# Nudge initial z based on source, if any
	_sync_initial_z()
	_mark_all_dirty()


func validate_shader_signature() -> void:
	print("Node: ", name, " is validating shader signature")
	if material is ShaderMaterial:
		var params: Array = material.shader.get_shader_uniform_list(false)
		print("Node: ", name, " - Found ", params.size(), " uniforms in shader")
		_shader_has_blur_radius_uniform = false
		_shader_has_blur_strength_uniform = false
		_shader_has_quality_uniform = false
		_shader_has_tint_color_uniform = false
		_shader_has_tint_strength_uniform = false
		for p in params:
			if p.name == BLUR_RADIUS_UNIFORM_NAME:
				_shader_has_blur_radius_uniform = true
				_blur_radius_dirty = true
			if p.name == BLUR_STRENGTH_UNIFORM_NAME:
				_shader_has_blur_strength_uniform = true
				_blur_strength_dirty = true
			if p.name == QUALITY_UNIFORM_NAME:
				_shader_has_quality_uniform = true
				_quality_dirty = true
			if p.name == TINT_COLOR_UNIFORM_NAME:
				_shader_has_tint_color_uniform = true
				_tint_dirty = true
			if p.name == TINT_STRENGTH_UNIFORM_NAME:
				_shader_has_tint_strength_uniform = true
				_tint_dirty = true
	if _shader_has_blur_radius_uniform and _shader_has_quality_uniform:
		_valid_shader = true
		print("Node: ", name, " has a valid shader signature")
	else:
		print("Node: ", name, " has an invalid shader signature - blur_radius: ", _shader_has_blur_radius_uniform, ", quality: ", _shader_has_quality_uniform)


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

	# Forward blur radius to shader if available and dirty
	if _blur_radius_dirty:
		_forward_blur_radius_to_shader()
		_blur_radius_dirty = false

	# Forward blur strength to shader if available and dirty
	if _blur_strength_dirty:
		_forward_blur_strength_to_shader()
		_blur_strength_dirty = false

	# Forward quality to shader if available and dirty
	if _quality_dirty:
		_apply_quality_to_shader()
		_quality_dirty = false

	# Forward tint to shader if available and dirty
	if _tint_dirty:
		_apply_tint_to_shader()
		_tint_dirty = false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if source_sprite == null:
		warnings.append("Assign a Source Sprite2D to cast a shadow.")
	if source_sprite and not (source_sprite is Sprite2D):
		warnings.append("Source must be a Sprite2D (AnimatedSprite2D is not supported in this version).")
	if material is ShaderMaterial and not _valid_shader:
		warnings.append("Shader does not expose the required blur uniforms.")
	return warnings


# -- Dirty flags helpers
func _mark_all_dirty() -> void:
	_tex_dirty = true
	_vis_dirty = true
	_blur_radius_dirty = true
	_blur_strength_dirty = true
	_quality_dirty = true
	_tint_dirty = true


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

	# apply offset in world space (doesn’t rotate with the sprite)
	global_position = source_sprite.global_position + distance


func _apply_opacity() -> void:
	# Only alpha is controlled here; tint handles RGB.
	var m := modulate
	m.a = clamp(opacity, 0.0, 1.0)
	modulate = m


# -- Shader uniform forwarding (optional)
func _forward_blur_radius_to_shader() -> void:
	if material == null:
		return
	if material is ShaderMaterial:
		var sm := material as ShaderMaterial
		if _shader_has_blur_radius_uniform:
			sm.set_shader_parameter(BLUR_RADIUS_UNIFORM_NAME, blur_radius)


func _forward_blur_strength_to_shader() -> void:
	if material == null:
		return
	if material is ShaderMaterial:
		var sm := material as ShaderMaterial
		if _shader_has_blur_strength_uniform:
			sm.set_shader_parameter(BLUR_STRENGTH_UNIFORM_NAME, blur_strength)


func _apply_quality_to_shader() -> void:
	if material == null:
		return
	if material is ShaderMaterial:
		if _shader_has_quality_uniform:
			material.set_shader_parameter(QUALITY_UNIFORM_NAME, quality)


func _apply_tint_to_shader() -> void:
	if material == null:
		return
	if material is ShaderMaterial:
		var sm := material as ShaderMaterial
		if _shader_has_tint_color_uniform:
			# Extract RGB from tint color
			var tint_rgb = Vector3(tint.r, tint.g, tint.b)
			sm.set_shader_parameter(TINT_COLOR_UNIFORM_NAME, tint_rgb)
		if _shader_has_tint_strength_uniform:
			# Extract strength from tint alpha
			sm.set_shader_parameter(TINT_STRENGTH_UNIFORM_NAME, tint.a)


# -- Setters
func set_distance(v: Vector2) -> void:
	distance = v
	# immediate position update
	_apply_distance()


func set_opacity(v: float) -> void:
	opacity = v
	_apply_opacity()


func set_blur_radius(v: float) -> void:
	blur_radius = v
	_blur_radius_dirty = true
	_forward_blur_radius_to_shader()


func set_blur_strength(v: float) -> void:
	blur_strength = v
	_blur_strength_dirty = true
	_forward_blur_strength_to_shader()


func set_quality(v: int) -> void:
	quality = v
	_quality_dirty = true
	_apply_quality_to_shader()


func set_tint(v: Color) -> void:
	tint = v
	_tint_dirty = true
	_apply_tint_to_shader()


# Optional convenience if you want to set tint & opacity together
func set_shadow_color(c: Color, a: float) -> void:
	tint = c
	opacity = a
	_apply_opacity()
