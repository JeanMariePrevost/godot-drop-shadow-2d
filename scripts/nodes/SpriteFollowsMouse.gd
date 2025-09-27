extends Sprite2D

var tween: Tween
var scale_tween: Tween

var _target_rotation_degrees: float = 0.0
var _target_scale: float = 1.0


func _ready():
    # Optional: Hide the system cursor to only show our sprite
    # Input.set_default_cursor_shape(Input.CURSOR_BLANK)
    pass


func _process(_delta):
    # Get the global mouse position
    var mouse_pos = get_global_mouse_position()

    # Set this sprite's global position to follow the mouse
    global_position = mouse_pos


func _input(event):
    if event is InputEventMouseButton and event.pressed:
        print("Event: ", event)
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            if Input.is_key_pressed(KEY_CTRL):
                # If CTRL is pressed, scale the sprite
                scale_sprite(0.25)
            else:
                # If CTRL is not pressed, rotate the sprite
                rotate_sprite(90.0)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            if Input.is_key_pressed(KEY_CTRL):
                # If CTRL is pressed, scale the sprite
                scale_sprite(-0.25)
            else:
                # If CTRL is not pressed, rotate the sprite
                rotate_sprite(-90.0)


func rotate_sprite(angle_degrees: float):
    # Kill any existing tween
    if tween:
        tween.kill()

    _target_rotation_degrees = _target_rotation_degrees + angle_degrees

    print("Current rotation: ", rotation_degrees, " | Target rotation: ", _target_rotation_degrees)

    # Create new tween
    tween = create_tween()
    tween.tween_property(self, "rotation_degrees", _target_rotation_degrees, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)


func scale_sprite(scale_increment: float):
    # Kill any existing scale tween
    if scale_tween:
        scale_tween.kill()

    _target_scale = _target_scale + scale_increment
    # Clamp scale to reasonable bounds
    _target_scale = clampf(_target_scale, 0.1, 8.0)

    print("Current scale: ", scale.x, " | Target scale: ", _target_scale)

    # Create new scale tween
    scale_tween = create_tween()
    scale_tween.tween_property(self, "scale", Vector2(_target_scale, _target_scale), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
