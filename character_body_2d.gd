extends CharacterBody2D

signal light_changed(new_light: float)
signal player_died

@export var speed: float = 450.0
@export var max_light: float = 100.0
@export var light_drain_per_second: float = 5.0

var light: float = 100.0
var can_launch: bool = true
var is_dead: bool = false


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	light = max_light
	light_changed.emit(light)


func _unhandled_input(event: InputEvent) -> void:
	# R restarts the current scene.
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_R:
				get_tree().reload_current_scene()
				return

	if is_dead or not can_launch:
		return

	# Click anywhere to launch toward the mouse.
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			launch(get_global_mouse_position() - global_position)
			return

	# Arrow keys or WASD launch in four directions.
	if event is InputEventKey:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_W, KEY_UP:
					launch(Vector2.UP)
				KEY_S, KEY_DOWN:
					launch(Vector2.DOWN)
				KEY_A, KEY_LEFT:
					launch(Vector2.LEFT)
				KEY_D, KEY_RIGHT:
					launch(Vector2.RIGHT)


func _physics_process(delta: float) -> void:
	if is_dead or can_launch:
		return

	light = maxf(light - light_drain_per_second * delta, 0.0)
	light_changed.emit(light)

	if light <= 0.0:
		die()
		return

	# Move, detect a collision, and reflect the velocity.
	var collision := move_and_collide(velocity * delta)

	if collision:
		velocity = velocity.bounce(collision.get_normal()).normalized() * speed


func launch(direction: Vector2) -> void:
	if is_dead or not can_launch:
		return

	if direction.length_squared() < 0.001:
		return

	velocity = direction.normalized() * speed
	can_launch = false


func add_light(amount: float = 25.0) -> void:
	if is_dead:
		return

	light = clampf(light + amount, 0.0, max_light)
	light_changed.emit(light)


func die() -> void:
	if is_dead:
		return

	is_dead = true
	velocity = Vector2.ZERO
	player_died.emit()

	# Brief pause, then restart.
	await get_tree().create_timer(0.6).timeout
	get_tree().reload_current_scene()
