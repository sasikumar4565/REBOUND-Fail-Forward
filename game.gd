extends Node2D

# ============================================================
# LAST SPARK: RISE AGAIN — HARD MODE
#
# SEASON 1: 6 levels
#   1 Horror, 2 Jungle, 3 Horror,
#   4 Jungle, 5 Horror, 6 Jungle
#
# SEASON 2: 6 levels
#   1 Summer, 2 Winter, 3 Spring,
#   4 Autumn, 5 City, 6 Ocean
#
# HARD FROM LEVEL 1:
#   5 golden lights per level
#   3 enemies on Level 1, up to 6 enemies
#   More blocks and hazards
#   Faster enemies and shorter warnings
#
# 3 hearts. Each enemy/hazard hit removes 1 heart.
# Losing all hearts restarts the current level.
# ============================================================

const SEASON_1_LEVELS: int = 6
const SEASON_2_LEVELS: int = 6
const TOTAL_LEVELS: int = 12

const POINT_COUNT: int = 5

const SAVE_PATH: String = "user://last_spark_hard_mode.cfg"

const START := Vector2(110, 600)
const GOAL := Vector2(990, 185)

const PLAYER_SPEED: float = 330.0
const PLAYER_RADIUS: float = 13.0

const SAMPLE_INTERVAL: float = 0.04
const MAX_HISTORY: int = 100

var mode: String = "title"
var previous_mode: String = "aim"

var selected_level: int = 1
var current_level: int = 1
var background_level: int = 1

var unlocked_level: int = 1
var continue_level: int = 1

var season_complete: bool = false
var campaign_complete: bool = false

var save_data := ConfigFile.new()

var sfx_enabled: bool = true
var bgm_enabled: bool = true

var player: CharacterBody2D
var world: Node2D
var menu_layer: CanvasLayer

var hud: Label
var message: Label

var sounds: Dictionary = {}

var clock: float = 0.0
var elapsed: float = 0.0

var hearts: int = 3
var retries: int = 0

var click_cooldown: float = 0.0
var protection: float = 0.0
var boost_cooldown: float = 0.0
var rewind_cooldown: float = 0.0

var state_timer: float = 0.0
var restoration: float = 0.0

var unlock_delay: float = -1.0
var exit_announced: bool = false

var spawn_point: Vector2 = START
var last_safe: Vector2 = START

var checkpoint := Vector2.ZERO
var checkpoint_active: bool = false

var walls: Array[Rect2] = []
var hazards: Array[Rect2] = []

var points: Array[Vector2] = []
var point_taken: Array[bool] = []

var seals: Array[Vector2] = []
var seal_active: Array[bool] = []

var crystals: Array[Vector2] = []

var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var particles: Array[Dictionary] = []

var history: Array[Vector2] = []
var trail: Array[Vector2] = []
var sample_timer: float = 0.0

var echo_path: Array[Vector2] = []
var echo_active: bool = false
var echo_position := Vector2.ZERO
var echo_index: int = 0
var echo_timer: float = 0.0
var rewind_cursor: float = 0.0


# ============================================================
# STARTUP
# ============================================================

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#080d1b"))
	load_progress()
	create_player()
	create_hud()
	create_audio()
	show_title()


func create_player() -> void:
	player = CharacterBody2D.new()
	player.name = "Ember"

	player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	player.collision_layer = 2
	player.collision_mask = 1
	player.position = START

	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()

	shape.radius = PLAYER_RADIUS
	collider.shape = shape

	player.add_child(collider)
	add_child(player)


func create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)

	hud = Label.new()
	hud.position = Vector2(25, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	message = Label.new()
	message.position = Vector2(25, 688)
	message.add_theme_font_size_override("font_size", 15)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(message)


# ============================================================
# CAMPAIGN HELPERS
# ============================================================

func campaign_season(number: int) -> int:
	return 1 if number <= SEASON_1_LEVELS else 2


func season_level(number: int) -> int:
	if number <= SEASON_1_LEVELS:
		return number

	return number - SEASON_1_LEVELS


func season_level_count(number: int) -> int:
	if number <= SEASON_1_LEVELS:
		return SEASON_1_LEVELS

	return SEASON_2_LEVELS


func level_is_horror(number: int) -> bool:
	return (
		number >= 1
		and number <= SEASON_1_LEVELS
		and number % 2 == 1
	)


func theme_name(number: int) -> String:
	if number > SEASON_1_LEVELS:
		return season_2_theme(number)

	return "HORROR" if level_is_horror(number) else "JUNGLE"


func season_2_theme(number: int) -> String:
	var themes: Array[String] = [
		"SUMMER",
		"WINTER",
		"SPRING",
		"AUTUMN",
		"CITY",
		"OCEAN"
	]

	var index: int = clampi(
		number - SEASON_1_LEVELS - 1,
		0,
		SEASON_2_LEVELS - 1
	)

	return themes[index]


func campaign_level_title(number: int) -> String:
	return (
		"SEASON %d — LEVEL %d/%d — %s"
		% [
			campaign_season(number),
			season_level(number),
			season_level_count(number),
			theme_name(number)
		]
	)


func enemy_attack_speed() -> float:
	# Very fast enemies, hard from Level 1.
	return 190.0 + float(current_level - 1) * 16.0


func enemy_warning_time() -> float:
	# Short warning before attacks.
	return maxf(
		0.9 - float(current_level - 1) * 0.05,
		0.45
	)


# ============================================================
# SAVE / LOAD
# ============================================================

func load_progress() -> void:
	if save_data.load(SAVE_PATH) != OK:
		return

	unlocked_level = clampi(
		int(save_data.get_value("progress", "unlocked", 1)),
		1,
		TOTAL_LEVELS
	)

	continue_level = clampi(
		int(save_data.get_value("progress", "continue", 1)),
		1,
		unlocked_level
	)

	season_complete = bool(
		save_data.get_value(
			"progress",
			"season_complete",
			false
		)
	)

	campaign_complete = bool(
		save_data.get_value(
			"progress",
			"campaign_complete",
			false
		)
	)

	if season_complete:
		unlocked_level = maxi(
			unlocked_level,
			SEASON_1_LEVELS + 1
		)

		if continue_level <= SEASON_1_LEVELS:
			continue_level = SEASON_1_LEVELS + 1

	if campaign_complete:
		unlocked_level = TOTAL_LEVELS

	sfx_enabled = bool(
		save_data.get_value("settings", "sfx", true)
	)

	bgm_enabled = bool(
		save_data.get_value("settings", "bgm", true)
	)


func save_progress() -> void:
	save_data.set_value(
		"progress",
		"unlocked",
		unlocked_level
	)

	save_data.set_value(
		"progress",
		"continue",
		continue_level
	)

	save_data.set_value(
		"progress",
		"season_complete",
		season_complete
	)

	save_data.set_value(
		"progress",
		"campaign_complete",
		campaign_complete
	)

	save_data.set_value("settings", "sfx", sfx_enabled)
	save_data.set_value("settings", "bgm", bgm_enabled)

	var error: int = save_data.save(SAVE_PATH)

	if error != OK:
		push_warning(
			"Could not save progress. Error: %d" % error
		)


# ============================================================
# GENERATED AUDIO
# ============================================================

func create_audio() -> void:
	make_effect("launch", [420.0, 560.0], 0.05, -22.0)
	make_effect("bounce", [190.0, 125.0], 0.035, -25.0)

	make_effect("coin_1", [659.25, 987.77], 0.075, -15.0)
	make_effect("coin_2", [783.99, 1174.66], 0.075, -15.0)

	make_effect(
		"coin_3",
		[987.77, 1318.51, 1567.98],
		0.075,
		-15.0
	)

	make_effect(
		"unlock",
		[523.25, 659.25, 783.99, 1046.50],
		0.12,
		-17.0
	)

	make_effect(
		"checkpoint",
		[392.0, 523.25, 659.25],
		0.10,
		-19.0
	)

	make_effect(
		"rewind",
		[740.0, 587.33, 440.0, 293.66],
		0.065,
		-20.0
	)

	make_effect(
		"seal",
		[587.33, 880.0, 1174.66],
		0.08,
		-19.0
	)

	make_effect("hurt", [160.0, 110.0], 0.085, -20.0)

	make_effect(
		"death",
		[220.0, 164.81, 110.0, 73.42],
		0.10,
		-20.0
	)

	make_effect("strike", [220.0, 330.0], 0.06, -19.0)

	make_effect(
		"win",
		[523.25, 659.25, 783.99, 1046.50, 1318.51],
		0.14,
		-17.0
	)

	var horror_music := AudioStreamPlayer.new()
	horror_music.stream = generate_bgm(true)
	horror_music.volume_db = -23.0
	add_child(horror_music)
	sounds["horror_bgm"] = horror_music

	var jungle_music := AudioStreamPlayer.new()
	jungle_music.stream = generate_bgm(false)
	jungle_music.volume_db = -23.0
	add_child(jungle_music)
	sounds["jungle_bgm"] = jungle_music


func make_effect(
	key: String,
	notes: Array,
	note_duration: float,
	volume: float
) -> void:
	var rate: int = 22050
	var note_frames: int = int(float(rate) * note_duration)
	var frame_count: int = note_frames * notes.size()

	var data := PackedByteArray()
	data.resize(frame_count * 2)

	for frame in range(frame_count):
		var note_index: int = int(
			float(frame) / float(note_frames)
		)

		var local_frame: int = frame % note_frames
		var time: float = float(local_frame) / float(rate)
		var progress: float = float(local_frame) / float(note_frames)

		var frequency: float = float(notes[note_index])

		var envelope: float = (
			minf(progress * 30.0, 1.0)
			* pow(1.0 - progress, 2.0)
		)

		var wave: float = (
			sin(TAU * frequency * time)
			+ 0.25 * sin(TAU * frequency * 2.0 * time)
		)

		var value: int = int(
			clampf(wave * envelope * 0.38, -1.0, 1.0)
			* 32767.0
		)

		data[frame * 2] = value & 255
		data[frame * 2 + 1] = (value >> 8) & 255

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data

	var sound := AudioStreamPlayer.new()
	sound.stream = stream
	sound.volume_db = volume
	sound.max_polyphony = 3

	add_child(sound)
	sounds[key] = sound


func generate_bgm(horror: bool) -> AudioStreamWAV:
	var rate: int = 11025
	var frame_count: int = rate * 8

	var data := PackedByteArray()
	data.resize(frame_count * 2)

	var roots: Array[float] = [
		130.8128, 110.0, 87.3071, 97.9989
	]

	if horror:
		roots = [110.0, 103.8262, 87.3071, 97.9989]

	var jungle_notes: Array[int] = [
		0, 7, 12, 7, 4, 7, 12, 16,
		0, 7, 12, 7, 4, 2, 7, 12
	]

	var horror_notes: Array[int] = [
		0, 0, 7, 3, 0, 6, 3, 0,
		0, 7, 3, 6, 0, 3, 1, 0
	]

	for frame in range(frame_count):
		var time: float = float(frame) / float(rate)

		var chord_index: int = mini(int(time / 2.0), 3)
		var root: float = roots[chord_index]
		var chord_time: float = fmod(time, 2.0)

		var chord_envelope: float = pow(
			sin(PI * chord_time / 2.0),
			2.0
		)

		var third: float = pow(
			2.0,
			(3.0 if horror else 4.0) / 12.0
		)

		var pad: float = (
			sin(TAU * root * chord_time) * 0.12
			+ sin(TAU * root * third * chord_time) * 0.06
			+ sin(TAU * root * 1.5 * chord_time) * 0.05
		) * chord_envelope

		var beat: int = mini(int(time / 0.5), 15)
		var beat_time: float = fmod(time, 0.5)

		var note: int = (
			horror_notes[beat]
			if horror
			else jungle_notes[beat]
		)

		var frequency: float = (
			root * 2.0 * pow(2.0, float(note) / 12.0)
		)

		var note_envelope: float = (
			minf(beat_time * 70.0, 1.0)
			* exp(-beat_time * (7.0 if horror else 12.0))
		)

		var melody: float = (
			sin(TAU * frequency * beat_time)
			* note_envelope
			* (0.035 if horror else 0.08)
		)

		var bass: float = (
			sin(TAU * root * 0.5 * chord_time)
			* chord_envelope
			* 0.08
		)

		var wave: float = pad + melody + bass

		if horror:
			wave *= 0.7 + sin(TAU * 0.5 * time) * 0.3
		else:
			var drum_time: float = fmod(time, 0.25)

			wave += (
				sin(TAU * 170.0 * drum_time)
				* minf(drum_time * 300.0, 1.0)
				* exp(-drum_time * 45.0)
				* 0.045
			)

		var value: int = int(
			clampf(wave, -0.8, 0.8) * 32767.0
		)

		data[frame * 2] = value & 255
		data[frame * 2 + 1] = (value >> 8) & 255

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data

	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count

	return stream


func play_sfx(key: String) -> void:
	if not sfx_enabled:
		return

	var sound: AudioStreamPlayer = sounds.get(key) as AudioStreamPlayer

	if sound != null:
		sound.play()


func update_bgm() -> void:
	var gameplay: bool = mode in [
		"aim", "move", "rewind", "dead"
	]

	var desired: String = (
		"horror_bgm"
		if level_is_horror(current_level)
		else "jungle_bgm"
	)

	for key in ["horror_bgm", "jungle_bgm"]:
		var music: AudioStreamPlayer = sounds.get(key) as AudioStreamPlayer

		if music == null:
			continue

		if bgm_enabled and gameplay and key == desired:
			music.stream_paused = false

			if not music.playing:
				music.play()
		else:
			music.stream_paused = true


func stop_bgm() -> void:
	for key in ["horror_bgm", "jungle_bgm"]:
		var music: AudioStreamPlayer = sounds.get(key) as AudioStreamPlayer

		if music != null:
			music.stop()
			music.stream_paused = false


# ============================================================
# UI HELPERS
# ============================================================

func close_menu() -> void:
	if is_instance_valid(menu_layer):
		menu_layer.hide()
		menu_layer.queue_free()


func make_page(width: float = 900.0) -> VBoxContainer:
	close_menu()

	menu_layer = CanvasLayer.new()
	menu_layer.layer = 20
	add_child(menu_layer)

	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.36)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_layer.add_child(shade)

	shade.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	var center := CenterContainer.new()
	shade.add_child(center)

	center.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)

	var style := StyleBoxFlat.new()

	style.bg_color = (
		Color(0.07, 0.04, 0.12, 0.92)
		if level_is_horror(background_level)
		else Color(0.025, 0.13, 0.08, 0.92)
	)

	style.border_color = (
		Color("#85639d")
		if level_is_horror(background_level)
		else Color("#69ac75")
	)

	style.set_border_width_all(2)
	style.set_corner_radius_all(14)

	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()

	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override(
			"margin_" + side,
			22
		)

	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	return box


func add_text(
	parent: Node,
	text: String,
	size: int = 20,
	centered: bool = false,
	color: Color = Color.WHITE
) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)

	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	parent.add_child(label)
	return label


func add_button(
	parent: Node,
	text: String,
	action: Callable,
	disabled: bool = false
) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size = Vector2(0, 40)
	item.disabled = disabled
	item.add_theme_font_size_override("font_size", 19)
	item.pressed.connect(action)

	parent.add_child(item)
	return item


# ============================================================
# TITLE SCREEN
# ============================================================

func show_title() -> void:
	mode = "title"
	background_level = 1
	restoration = 0.0

	clear_echo()
	stop_bgm()
	unlock_delay = -1.0

	var box := make_page(920.0)

	add_text(
		box,
		"LAST SPARK",
		60,
		true,
		Color("#ffd28c")
	)

	add_text(
		box,
		"RISE AGAIN — HARD MODE",
		36,
		true,
		Color("#ff9d57")
	)

	add_text(
		box,
		"SEASON 1: 6 LEVELS\n"
		+ "SEASON 2: 6 LEVELS\n\n"
		+ "Collect 5 golden lights on every level.\n"
		+ "You have only 3 hearts.\n"
		+ "Every enemy hit removes one heart.",
		21,
		true
	)

	box.add_child(HSeparator.new())

	var start := add_button(
		box,
		"CHOOSE LEVEL",
		show_level_select
	)

	start.grab_focus()

	add_button(
		box,
		"CONTINUE — S%d LEVEL %d: %s"
		% [
			campaign_season(continue_level),
			season_level(continue_level),
			theme_name(continue_level)
		],
		show_get_started.bind(continue_level)
	)

	add_button(
		box,
		"BGM: " + ("ON" if bgm_enabled else "OFF"),
		toggle_bgm
	)

	add_button(
		box,
		"SOUND EFFECTS: "
		+ ("ON" if sfx_enabled else "OFF"),
		toggle_sfx
	)

	if campaign_complete:
		add_text(
			box,
			"BOTH SEASONS COMPLETE!",
			21,
			true,
			Color("#a7efb4")
		)
	elif season_complete:
		add_text(
			box,
			"SEASON 2 UNLOCKED",
			21,
			true,
			Color("#a7efb4")
		)

	add_button(box, "QUIT", quit_game)


func toggle_bgm() -> void:
	bgm_enabled = not bgm_enabled
	save_progress()
	show_title()


func toggle_sfx() -> void:
	sfx_enabled = not sfx_enabled
	save_progress()
	show_title()


func quit_game() -> void:
	save_progress()
	get_tree().quit()


# ============================================================
# LEVEL SELECT
# ============================================================

func show_level_select() -> void:
	mode = "select"
	restoration = 0.0

	clear_echo()
	stop_bgm()
	unlock_delay = -1.0

	var box := make_page(940.0)

	add_text(
		box,
		"CHOOSE YOUR LEVEL",
		31,
		true,
		Color("#ffd28c")
	)

	add_text(
		box,
		"SEASON 1 — HORROR AND JUNGLE",
		21,
		true
	)

	var first_grid := GridContainer.new()
	first_grid.columns = 3
	first_grid.add_theme_constant_override(
		"h_separation",
		10
	)
	first_grid.add_theme_constant_override(
		"v_separation",
		8
	)
	box.add_child(first_grid)

	for number in range(1, SEASON_1_LEVELS + 1):
		var completed: bool = (
			save_data.has_section_key(
				"best",
				str(number)
			)
		)

		var item := add_button(
			first_grid,
			"%d: %s%s"
			% [
				number,
				theme_name(number),
				" *" if completed else ""
			],
			show_get_started.bind(number),
			number > unlocked_level
		)

		item.custom_minimum_size = Vector2(280, 42)
		item.add_theme_font_size_override(
			"font_size",
			16
		)

	box.add_child(HSeparator.new())

	add_text(
		box,
		"SEASON 2 — THE CHANGING WORLD",
		21,
		true,
		Color("#a6e8ff")
	)

	var second_grid := GridContainer.new()
	second_grid.columns = 3
	second_grid.add_theme_constant_override(
		"h_separation",
		10
	)
	second_grid.add_theme_constant_override(
		"v_separation",
		8
	)
	box.add_child(second_grid)

	for number in range(
		SEASON_1_LEVELS + 1,
		TOTAL_LEVELS + 1
	):
		var completed: bool = (
			save_data.has_section_key(
				"best",
				str(number)
			)
		)

		var item := add_button(
			second_grid,
			"%d: %s%s"
			% [
				season_level(number),
				theme_name(number),
				" *" if completed else ""
			],
			show_get_started.bind(number),
			number > unlocked_level
		)

		item.custom_minimum_size = Vector2(280, 42)
		item.add_theme_font_size_override(
			"font_size",
			16
		)

	add_text(
		box,
		"* Completed. Finish Season 1 to enter Season 2.",
		15,
		true
	)

	add_button(box, "BACK TO TITLE", show_title)


# ============================================================
# GET STARTED
# ============================================================

func show_get_started(number: int) -> void:
	mode = "brief"

	selected_level = clampi(
		number,
		1,
		unlocked_level
	)

	background_level = selected_level
	restoration = 0.0

	var box := make_page(940.0)

	add_text(
		box,
		"GET READY TO RISE",
		35,
		true,
		Color("#ffd28c")
	)

	add_text(
		box,
		campaign_level_title(selected_level),
		23,
		true,
		Color("#a6e8ff")
	)

	var instructions: String = (
		"HARD MODE\n"
		+ "You have 3 hearts. Each enemy hit removes 1 heart.\n"
		+ "Losing all 3 hearts restarts the current level.\n\n"
		+ "MISSION\n"
		+ "Collect all 5 golden lights to unlock the beacon.\n"
		+ "Enter the golden ring in the upper-right corner.\n\n"
		+ "CONTROLS\n"
		+ "LEFT CLICK: launch toward your mouse.\n"
		+ "CLICK AGAIN: redirect while moving.\n"
		+ "SPACE: rewind and create an Echo.\n"
		+ "R: restart level. ESC: pause.\n\n"
		+ "Enemies are dangerous and fast.\n"
		+ "Lure attacks into your Echo to stun enemies purple.\n"
		+ "Bounce into a purple enemy to strike it."
	)

	add_text(box, instructions, 17)

	var start := add_button(
		box,
		"GET STARTED",
		start_selected_level
	)

	start.custom_minimum_size.y = 48
	start.grab_focus()

	add_button(
		box,
		"BACK TO LEVELS",
		show_level_select
	)


func start_selected_level() -> void:
	if mode == "brief":
		load_level(selected_level)


# ============================================================
# LEVEL LOADING — HARD FROM LEVEL 1
# ============================================================

func load_level(number: int) -> void:
	close_menu()
	stop_bgm()

	current_level = clampi(
		number,
		1,
		unlocked_level
	)

	background_level = current_level
	continue_level = current_level
	save_progress()

	clear_echo()

	particles.clear()
	bullets.clear()
	enemies.clear()

	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()

	world = Node2D.new()
	world.name = "LevelWorld"
	add_child(world)

	walls.clear()
	hazards.clear()
	points.clear()
	point_taken.clear()
	seals.clear()
	seal_active.clear()
	crystals.clear()

	walls = [
		Rect2(20, 100, 1060, 30),
		Rect2(20, 650, 1060, 30),
		Rect2(20, 100, 30, 580),
		Rect2(1050, 100, 30, 580)
	]

	var rng := RandomNumberGenerator.new()
	rng.seed = 7351 + current_level * 7919

	var horizontal_shift: float = (
		float((current_level - 1) % 4) * 4.0
	)

	var vertical_shift: float = (
		float((current_level - 1) % 3) * 4.0
	)

	# 16 construction positions.
	var slots: Array[Vector2] = []

	for row in range(4):
		for column in range(4):
			slots.append(
				Vector2(
					250.0 + float(column) * 190.0
					+ horizontal_shift,
					215.0 + float(row) * 115.0
					+ vertical_shift
				)
			)

	var order: Array[int] = []

	for i in range(slots.size()):
		order.append(i)

	for i in range(order.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, i)
		var temporary: int = order[i]

		order[i] = order[other]
		order[other] = temporary

	# HARD: Level 1 has 7 blocks, Level 12 has 10.
	var block_count: int = mini(
		6 + current_level,
		10
	)

	# HARD: Level 1 has 3 hazards, Level 12 has 6.
	var hazard_count: int = mini(
		3 + int(float(current_level - 1) / 2.0),
		6
	)

	for i in range(block_count):
		var center: Vector2 = slots[order[i]]

		var horizontal: bool = (
			(i + current_level) % 3 != 0
		)

		if horizontal:
			walls.append(
				Rect2(
					center - Vector2(70, 10),
					Vector2(140, 20)
				)
			)
		else:
			walls.append(
				Rect2(
					center - Vector2(10, 50),
					Vector2(20, 100)
				)
			)

	for i in range(hazard_count):
		var slot_index: int = order[block_count + i]
		var center: Vector2 = slots[slot_index]

		hazards.append(
			Rect2(
				center - Vector2(23, 22),
				Vector2(46, 44)
			)
		)

	build_wall_bodies()

	# 5 golden lights per level.
	create_level_points()

	seals = [points[0], points[1]]
	seal_active = [false, false]

	crystals = [
		find_clear(Vector2(350, 600), 28.0),
		find_clear(Vector2(760, 590), 28.0)
	]

	checkpoint = find_clear(Vector2(625, 590), 35.0)
	checkpoint_active = false
	spawn_point = START
	last_safe = START

	# HARD: Level 1 has 3 enemies, Level 12 has 6.
	var enemy_count: int = mini(
		2 + current_level,
		6
	)

	var enemy_slots: Array[Vector2] = [
		Vector2(360, 535),
		Vector2(740, 285),
		Vector2(900, 565),
		Vector2(240, 280),
		Vector2(560, 430),
		Vector2(830, 430)
	]

	for i in range(enemy_count):
		var kind: String = "stalker"

		if i == 1:
			kind = "watcher"
		elif i == 2:
			kind = "wisp"
		elif i == 3:
			kind = "stalker"
		elif i == 4:
			kind = "watcher"
		elif i == 5:
			kind = "wisp"

		add_enemy(
			find_clear(enemy_slots[i], 35.0),
			kind,
			false
		)

	# Optional boss on the final level of each season.
	if current_level == SEASON_1_LEVELS or current_level == TOTAL_LEVELS:
		add_enemy(
			find_clear(Vector2(900, 240), 44.0),
			"stalker",
			true
		)

	retries = 0
	elapsed = 0.0
	restoration = 0.0
	exit_announced = false
	unlock_delay = -1.0

	reset_player()

	message.text = (
		"%s. Collect all %d golden lights."
		% [
			campaign_level_title(current_level),
			POINT_COUNT
		]
	)


func build_wall_bodies() -> void:
	for rect in walls:
		var body := StaticBody2D.new()
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()

		shape.size = rect.size
		collider.shape = shape

		body.position = rect.get_center()
		body.collision_layer = 1
		body.collision_mask = 0

		body.add_child(collider)
		world.add_child(body)


# ============================================================
# FIVE GOLDEN LIGHTS PER LEVEL
# ============================================================

func create_level_points() -> void:
	points.clear()
	point_taken.clear()

	for index in range(POINT_COUNT):
		var point: Vector2 = choose_point_position(index)

		points.append(point)
		point_taken.append(false)


func choose_point_position(index: int) -> Vector2:
	var lane_centers: Array[float] = [
		150.0,
		350.0,
		550.0,
		750.0,
		950.0
	]

	var preferred := Vector2(
		lane_centers[index]
		+ sin(float(current_level * 3 + index)) * 20.0,

		185.0
		+ float(
			(current_level * 61 + index * 137) % 390
		)
	)

	if point_position_valid(preferred):
		return preferred

	for distance in range(20, 301, 20):
		for angle in range(0, 360, 30):
			var candidate: Vector2 = (
				preferred
				+ Vector2.from_angle(
					deg_to_rad(float(angle))
				) * float(distance)
			)

			if point_position_valid(candidate):
				return candidate

	for y in range(180, 611, 25):
		for x in range(100, 1001, 25):
			var candidate := Vector2(float(x), float(y))

			if point_position_valid(candidate):
				return candidate

	return find_clear(preferred, 35.0)


func point_position_valid(point: Vector2) -> bool:
	if not position_clear(point, 35.0):
		return false

	if point.distance_to(START) < 75.0:
		return false

	if point.distance_to(GOAL) < 75.0:
		return false

	for existing in points:
		if point.distance_to(existing) < 110.0:
			return false

	return true


func position_clear(point: Vector2, radius: float) -> bool:
	if point.x < 50.0 + radius or point.x > 1050.0 - radius:
		return false

	if point.y < 130.0 + radius or point.y > 650.0 - radius:
		return false

	for rect in walls:
		if rect.grow(radius).has_point(point):
			return false

	for rect in hazards:
		if rect.grow(radius).has_point(point):
			return false

	return true


func find_clear(preferred: Vector2, radius: float) -> Vector2:
	if position_clear(preferred, radius):
		return preferred

	for distance in range(20, 321, 20):
		for angle in range(0, 360, 30):
			var point: Vector2 = (
				preferred
				+ Vector2.from_angle(
					deg_to_rad(float(angle))
				) * float(distance)
			)

			if position_clear(point, radius):
				return point

	return START


# ============================================================
# ENEMIES
# ============================================================

func add_enemy(point: Vector2, kind: String, boss: bool) -> void:
	var body := CharacterBody2D.new()
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	body.collision_layer = 4
	body.collision_mask = 1
	body.position = point

	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()

	shape.radius = 22.0 if boss else 15.0
	collider.shape = shape

	body.add_child(collider)
	world.add_child(body)

	enemies.append({
		"body": body,
		"spawn": point,
		"kind": kind,
		"boss": boss,
		"hp": 3 if boss else 1,
		"phase": "roam",
		"timer": 1.0,
		"direction": Vector2.RIGHT,
		"alive": true,
		"angle": float(enemies.size())
	})


func update_enemies(delta: float) -> void:
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]

		if not bool(enemy["alive"]):
			continue

		var body: CharacterBody2D = enemy["body"]
		var phase: String = enemy["phase"]
		var kind: String = enemy["kind"]

		var timer: float = float(enemy["timer"]) - delta
		enemy["timer"] = timer

		var target: Vector2 = player.position

		if echo_active:
			if body.position.distance_to(echo_position) < 420.0:
				target = echo_position

		match phase:
			"stunned":
				if timer <= 0.0:
					enemy["phase"] = "recover"
					enemy["timer"] = 1.0

			"windup":
				if timer <= 0.0:
					enemy["direction"] = (
						target - body.position
					).normalized()

					if kind == "watcher":
						var direction: Vector2 = enemy["direction"]

						bullets.append({
							"position": body.position,
							"velocity": direction * enemy_attack_speed(),
							"owner": index,
							"life": 5.0
						})

						enemy["phase"] = "recover"
						enemy["timer"] = 1.1
					else:
						enemy["phase"] = "lunge"
						enemy["timer"] = 0.65

			"lunge":
				var direction: Vector2 = enemy["direction"]
				var speed: float = enemy_attack_speed()

				if bool(enemy["boss"]):
					speed *= 1.15

				body.move_and_collide(
					direction * speed * delta
				)

				if echo_active:
					if body.position.distance_to(echo_position) < 39.0:
						stun_enemy(index)

				if enemy["phase"] == "lunge" and timer <= 0.0:
					enemy["phase"] = "recover"
					enemy["timer"] = 0.8

			"recover":
				if timer <= 0.0:
					enemy["phase"] = "roam"
					enemy["timer"] = 0.6

			_:
				if kind != "watcher":
					var direction := Vector2(
						cos(clock + float(enemy["angle"])),
						sin(clock * 0.7 + float(enemy["angle"]))
					)

					body.move_and_collide(
						direction * 35.0 * delta
					)

				var detection: float = (
					360.0 + float(current_level - 1) * 12.0
				)

				if body.position.distance_to(target) < detection:
					if timer <= 0.0:
						enemy["phase"] = "windup"
						enemy["timer"] = enemy_warning_time()

		var contact: float = (
			37.0 if bool(enemy["boss"]) else 29.0
		)

		if body.position.distance_to(player.position) < contact:
			if enemy["phase"] == "stunned":
				if mode == "move":
					strike_enemy(enemy)
			else:
				hurt_player()

		if mode == "dead":
			return


func stun_enemy(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return

	var enemy: Dictionary = enemies[index]

	if not bool(enemy["alive"]) or enemy["phase"] == "stunned":
		return

	enemy["phase"] = "stunned"
	enemy["timer"] = 3.0

	var body: CharacterBody2D = enemy["body"]

	burst(body.position, Color("#b58aff"), 16)
	play_sfx("seal")

	message.text = "ECHO BREAK! Bounce into the PURPLE enemy!"


func strike_enemy(enemy: Dictionary) -> void:
	var body: CharacterBody2D = enemy["body"]

	enemy["hp"] = int(enemy["hp"]) - 1

	var direction: Vector2 = player.position - body.position

	if direction.length_squared() < 1.0:
		direction = Vector2.UP

	player.velocity = direction.normalized() * PLAYER_SPEED

	burst(body.position, Color("#dba9ff"), 22)
	play_sfx("strike")

	if int(enemy["hp"]) <= 0:
		enemy["alive"] = false
		message.text = "Enemy defeated!"
	else:
		enemy["phase"] = "recover"
		enemy["timer"] = 1.2
		message.text = "Boss struck! Use another Echo for the next hit."


func update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var shot: Dictionary = bullets[i]

		var point: Vector2 = shot["position"]
		var velocity: Vector2 = shot["velocity"]

		point += velocity * delta

		shot["position"] = point
		shot["life"] = float(shot["life"]) - delta

		var remove: bool = float(shot["life"]) <= 0.0

		for rect in walls:
			if rect.grow(5.0).has_point(point):
				remove = true

		if echo_active and point.distance_to(echo_position) < 25.0:
			stun_enemy(int(shot["owner"]))
			remove = true
		elif point.distance_to(player.position) < 20.0:
			hurt_player()
			remove = true

		if remove:
			bullets.remove_at(i)

		if mode == "dead":
			return


# ============================================================
# INPUT
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				if mode == "aim" or mode == "move":
					show_pause()
				elif mode == "paused":
					resume_game()
				return

	if mode != "aim" and mode != "move":
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_R:
				restart_current_level()
				return

			if event.keycode == KEY_SPACE:
				begin_rewind()
				return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			launch()


func launch() -> void:
	if click_cooldown > 0.0:
		return

	var direction: Vector2 = (
		get_global_mouse_position() - player.position
	)

	if direction.length_squared() < 1.0:
		return

	if history.is_empty():
		history.append(player.position)

	player.velocity = direction.normalized() * PLAYER_SPEED

	mode = "move"
	click_cooldown = 0.18

	play_sfx("launch")


# ============================================================
# REWIND / ECHO
# ============================================================

func begin_rewind() -> void:
	if mode != "move":
		return

	if rewind_cooldown > 0.0:
		message.text = "Rewind is cooling down."
		return

	if echo_active:
		message.text = "Wait for your current Echo to finish."
		return

	if history.size() < 12:
		message.text = "Move a little longer to record an Echo route."
		return

	history.append(player.position)
	echo_path.assign(history)

	rewind_cursor = float(echo_path.size() - 1)

	player.velocity = Vector2.ZERO
	trail.clear()

	mode = "rewind"

	play_sfx("rewind")
	message.text = "BOUNCE BACK: retracing your recent movement..."


func update_rewind(delta: float) -> void:
	rewind_cursor = maxf(
		rewind_cursor - delta * 75.0,
		0.0
	)

	player.position = echo_path[int(rewind_cursor)]

	if rewind_cursor <= 0.0:
		player.reset_physics_interpolation()

		echo_active = true
		echo_index = 0
		echo_timer = 0.0
		echo_position = echo_path[0]

		history.clear()
		sample_timer = 0.0

		mode = "aim"
		click_cooldown = 0.2
		rewind_cooldown = 4.0
		protection = maxf(protection, 0.6)

		check_echo_seals()

		message.text = "Your Echo repeats the past. Launch a new route!"


func update_echo(delta: float) -> void:
	if not echo_active:
		return

	echo_timer += delta

	while echo_timer >= SAMPLE_INTERVAL and echo_active:
		echo_timer -= SAMPLE_INTERVAL
		echo_index += 1

		if echo_index >= echo_path.size():
			echo_active = false
			break

		echo_position = echo_path[echo_index]
		check_echo_seals()


func check_echo_seals() -> void:
	for i in range(seals.size()):
		if seal_active[i]:
			continue

		if echo_position.distance_to(seals[i]) < 35.0:
			seal_active[i] = true

			burst(seals[i], Color("#83f3ff"), 20)
			play_sfx("seal")

			message.text = "Optional Echo seal ignited!"


func clear_echo() -> void:
	history.clear()
	echo_path.clear()
	trail.clear()

	echo_active = false
	echo_index = 0
	echo_timer = 0.0
	sample_timer = 0.0


# ============================================================
# MAIN LOOP
# ============================================================

func _physics_process(delta: float) -> void:
	clock += delta
	click_cooldown = maxf(click_cooldown - delta, 0.0)
	rewind_cooldown = maxf(rewind_cooldown - delta, 0.0)

	if mode not in [
		"title",
		"select",
		"brief",
		"paused",
		"season_welcome"
	]:
		update_particles(delta)

		if unlock_delay >= 0.0:
			unlock_delay -= delta

			if unlock_delay <= 0.0:
				unlock_delay = -1.0

				if mode == "aim" or mode == "move":
					play_sfx("unlock")

	match mode:
		"aim", "move":
			update_gameplay(delta)

		"rewind":
			update_rewind(delta)

		"dead":
			state_timer -= delta

			if state_timer <= 0.0:
				restart_current_level()

		"restoring":
			state_timer -= delta

			restoration = clampf(
				1.0 - state_timer / 1.4,
				0.0,
				1.0
			)

			if state_timer <= 0.0:
				mode = "won"
				call_deferred("show_completion")

	update_bgm()
	update_hud()
	queue_redraw()


func update_gameplay(delta: float) -> void:
	elapsed += delta

	protection = maxf(protection - delta, 0.0)
	boost_cooldown = maxf(boost_cooldown - delta, 0.0)

	update_echo(delta)

	if mode == "move":
		move_player(delta)

		if touching_hazard():
			lose_heart()
			return

		if position_clear(player.position, 30.0):
			last_safe = player.position

		sample_timer += delta

		if sample_timer >= SAMPLE_INTERVAL:
			sample_timer = fmod(
				sample_timer,
				SAMPLE_INTERVAL
			)

			history.append(player.position)

			if history.size() > MAX_HISTORY:
				history.pop_front()

		check_world()

		trail.append(player.position)

		if trail.size() > 20:
			trail.pop_front()

	if mode == "aim" or mode == "move":
		update_enemies(delta)

		if mode != "dead":
			update_bullets(delta)


func update_hud() -> void:
	var visible_game: bool = mode not in [
		"title",
		"select",
		"brief",
		"season_welcome"
	]

	hud.visible = visible_game
	message.visible = visible_game

	if not visible_game:
		return

	var heart_text: String = ""

	for i in range(3):
		heart_text += (
			"♥ "
			if i < hearts
			else "♡ "
		)

	hud.text = (
		"%s | %s | Hearts: %s | Lights %d/%d"
		% [
			campaign_level_title(current_level),
			"REWIND READY"
			if rewind_cooldown <= 0.0
			else "REWIND %.1fs" % rewind_cooldown,
			heart_text,
			count_flags(point_taken),
			POINT_COUNT
		]
	)


# ============================================================
# MOVEMENT / BOUNDARIES
# ============================================================

func move_player(delta: float) -> void:
	var motion: Vector2 = player.velocity * delta
	var bounced: bool = false

	for i in range(4):
		if motion.length_squared() < 0.000001:
			break

		var hit: KinematicCollision2D = (
			player.move_and_collide(motion)
		)

		if hit == null:
			break

		player.velocity = (
			player.velocity.bounce(
				hit.get_normal()
			).normalized() * PLAYER_SPEED
		)

		motion = hit.get_remainder().bounce(
			hit.get_normal()
		)

		bounced = true

	if bounced:
		play_sfx("bounce")
		burst(player.position, Color("#ffc780"), 4)

	var point: Vector2 = player.position
	var velocity: Vector2 = player.velocity

	if point.x < 63.0:
		point.x = 63.0
		velocity.x = absf(velocity.x)
	elif point.x > 1037.0:
		point.x = 1037.0
		velocity.x = -absf(velocity.x)

	if point.y < 143.0:
		point.y = 143.0
		velocity.y = absf(velocity.y)
	elif point.y > 637.0:
		point.y = 637.0
		velocity.y = -absf(velocity.y)

	player.position = point
	player.velocity = velocity.normalized() * PLAYER_SPEED


func touching_hazard() -> bool:
	for rect in hazards:
		if rect.grow(PLAYER_RADIUS).has_point(player.position):
			return true

	return false


func count_flags(values: Array[bool]) -> int:
	var count: int = 0

	for value in values:
		if value:
			count += 1

	return count


# ============================================================
# LIGHTS / EXIT / CHECKPOINTS
# ============================================================

func exit_open() -> bool:
	return (
		not points.is_empty()
		and count_flags(point_taken) == points.size()
	)


func announce_exit() -> void:
	if exit_announced or not exit_open():
		return

	exit_announced = true
	unlock_delay = 0.27

	burst(GOAL, Color("#ffe7a0"), 35)

	message.text = "BEACON OPEN! Reach the golden ring in the upper-right."


func check_world() -> void:
	for i in range(points.size()):
		if point_taken[i]:
			continue

		if player.position.distance_to(points[i]) < 29.0:
			point_taken[i] = true

			var count: int = count_flags(point_taken)

			play_sfx(
				"coin_%d" % clampi(count, 1, 3)
			)

			burst(points[i], Color("#ffe29d"), 20)

			message.text = (
				"LIGHT %d/%d COLLECTED"
				% [count, POINT_COUNT]
			)

			announce_exit()

	if not checkpoint_active:
		if player.position.distance_to(checkpoint) < 32.0:
			checkpoint_active = true
			spawn_point = checkpoint
			last_safe = checkpoint

			hearts = 3

			play_sfx("checkpoint")
			burst(checkpoint, Color("#ffd58a"), 24)

			message.text = (
				"BEACON OPEN! Reach the upper-right ring."
				if exit_open()
				else "Checkpoint ignited! Hearts restored."
			)

	if boost_cooldown <= 0.0:
		for point in crystals:
			if player.position.distance_to(point) < 31.0:
				boost_player()
				break

	announce_exit()

	if player.position.distance_to(GOAL) < 43.0:
		if exit_open():
			finish_level()
		else:
			message.text = (
				"Beacon locked: collect %d more light(s)."
				% (points.size() - count_flags(point_taken))
			)


func boost_player() -> void:
	var horizontal: float = clampf(
		(GOAL.x - player.position.x) * 0.0015,
		-0.7,
		0.7
	)

	player.velocity = (
		Vector2(horizontal, -1.0).normalized()
		* PLAYER_SPEED
	)

	boost_cooldown = 0.7
	play_sfx("launch")


# ============================================================
# HEARTS / FAILURE
# ============================================================

func hurt_player() -> void:
	if protection > 0.0:
		return

	if mode != "aim" and mode != "move":
		return

	hearts -= 1
	protection = 1.5

	burst(player.position, Color("#ff647b"), 15)
	play_sfx("hurt")

	if hearts <= 0:
		lose_heart()
	else:
		message.text = (
			"HIT! %d heart(s) left." % hearts
		)


func lose_heart() -> void:
	if mode != "aim" and mode != "move":
		return

	retries += 1

	clear_echo()
	bullets.clear()

	mode = "dead"
	state_timer = 0.65
	unlock_delay = -1.0

	player.velocity = Vector2.ZERO

	burst(player.position, Color("#ffaf68"), 35)
	play_sfx("death")

	message.text = (
		"ALL HEARTS LOST! Restarting this level..."
	)


func restart_current_level() -> void:
	exit_announced = false
	unlock_delay = -1.0

	clear_echo()
	bullets.clear()

	for i in range(point_taken.size()):
		point_taken[i] = false

	for i in range(seal_active.size()):
		seal_active[i] = false

	for enemy in enemies:
		var body: CharacterBody2D = enemy["body"]

		body.position = enemy["spawn"]
		body.reset_physics_interpolation()

		enemy["hp"] = 3 if bool(enemy["boss"]) else 1
		enemy["alive"] = true
		enemy["phase"] = "roam"
		enemy["timer"] = 1.0

	reset_player()

	message.text = "Rise again. Collect all 5 golden lights."


func reset_player() -> void:
	player.position = spawn_point
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()

	last_safe = spawn_point

	hearts = 3

	protection = 2.0
	click_cooldown = 0.3
	boost_cooldown = 0.7
	rewind_cooldown = 0.0

	mode = "aim"


# ============================================================
# PAUSE
# ============================================================

func show_pause() -> void:
	previous_mode = mode
	mode = "paused"

	var box := make_page(760.0)

	add_text(
		box,
		"YOUR LIGHT IS SAFE",
		36,
		true,
		Color("#ffd28c")
	)

	add_text(
		box,
		"Paused. The background music is paused too.",
		20,
		true
	)

	add_button(box, "RESUME", resume_game)
	add_button(box, "RESTART LEVEL", restart_current_level)
	add_button(box, "LEVEL SELECT", show_level_select)
	add_button(box, "TITLE SCREEN", show_title)


func resume_game() -> void:
	close_menu()
	mode = previous_mode
	click_cooldown = 0.25


# ============================================================
# COMPLETION / SEASON TRANSITION
# ============================================================

func finish_level() -> void:
	if mode != "aim" and mode != "move":
		return

	if not exit_open():
		return

	mode = "restoring"
	state_timer = 1.4
	unlock_delay = -1.0

	clear_echo()
	bullets.clear()

	player.velocity = Vector2.ZERO

	play_sfx("win")
	burst(GOAL, Color("#ffe8b5"), 60)

	unlocked_level = maxi(
		unlocked_level,
		mini(current_level + 1, TOTAL_LEVELS)
	)

	continue_level = mini(
		current_level + 1,
		TOTAL_LEVELS
	)

	var key: String = str(current_level)

	var previous_best: float = float(
		save_data.get_value(
			"best",
			key,
			999999.0
		)
	)

	save_data.set_value(
		"best",
		key,
		minf(previous_best, elapsed)
	)

	if current_level == SEASON_1_LEVELS:
		season_complete = true

	if current_level == TOTAL_LEVELS:
		campaign_complete = true

	save_progress()


func show_completion() -> void:
	if current_level == SEASON_1_LEVELS:
		show_season_2_welcome()
		return

	if current_level == TOTAL_LEVELS:
		show_season_complete()
		return

	var box := make_page(860.0)

	add_text(
		box,
		"LEVEL COMPLETE!",
		38,
		true,
		Color("#ffd28c")
	)

	add_text(
		box,
		"%s\nTime: %.1f seconds\nRetries: %d\nProgress saved."
		% [
			campaign_level_title(current_level),
			elapsed,
			retries
		],
		22,
		true
	)

	add_text(
		box,
		"Next: S%d Level %d — %s"
		% [
			campaign_season(current_level + 1),
			season_level(current_level + 1),
			theme_name(current_level + 1)
		],
		21,
		true,
		Color("#a6e8ff")
	)

	add_button(
		box,
		"NEXT LEVEL",
		show_get_started.bind(current_level + 1)
	)

	add_button(
		box,
		"LEVEL SELECT",
		show_level_select
	)

	add_button(
		box,
		"TITLE SCREEN",
		show_title
	)


func show_season_2_welcome() -> void:
	mode = "season_welcome"
	restoration = 0.0

	clear_echo()
	stop_bgm()
	unlock_delay = -1.0

	var box := make_page(940.0)

	add_text(
		box,
		"SEASON 1 COMPLETE!",
		40,
		true,
		Color("#ffd28c")
	)

	add_text(
		box,
		"WELCOME TO SEASON 2",
		52,
		true,
		Color("#a6e8ff")
	)

	add_text(
		box,
		"THE CHANGING WORLD",
		27,
		true,
		Color("#b5f3bf")
	)

	add_text(
		box,
		"Summer. Winter. Spring.\n"
		+ "Autumn. City. Ocean.",
		23,
		true
	)

	add_text(
		box,
		"You still have only 3 hearts.\n"
		+ "Season 2 is even harder.",
		20,
		true,
		Color("#ff9d9d")
	)

	box.add_child(HSeparator.new())

	var start := add_button(
		box,
		"GET STARTED — SEASON 2",
		start_season_2
	)

	start.custom_minimum_size.y = 52
	start.grab_focus()

	add_button(
		box,
		"BACK TO LEVEL SELECT",
		show_level_select
	)


func start_season_2() -> void:
	load_level(SEASON_1_LEVELS + 1)


func show_season_complete() -> void:
	var box := make_page(920.0)

	add_text(
		box,
		"SEASON 2 COMPLETE!",
		42,
		true,
		Color("#ffd28c")
	)

	add_text(
		box,
		"YOU RESTORED EVERY WORLD",
		29,
		true,
		Color("#a7efb4")
	)

	add_text(
		box,
		"Season 1: 6 levels\n"
		+ "Season 2: 6 levels\n\n"
		+ "Horror. Jungle. Summer. Winter.\n"
		+ "Spring. Autumn. City. Ocean.",
		23,
		true
	)

	add_button(
		box,
		"REPLAY LEVELS",
		show_level_select
	)

	add_button(
		box,
		"TITLE SCREEN",
		show_title
	)


# ============================================================
# PARTICLES
# ============================================================

func burst(point: Vector2, color: Color, amount: int) -> void:
	for i in range(amount):
		if particles.size() >= 200:
			particles.pop_front()

		particles.append({
			"position": point,
			"velocity": Vector2(
				randf_range(-90.0, 90.0),
				randf_range(-130.0, 40.0)
			),
			"life": randf_range(0.3, 0.9),
			"color": color
		})


func update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var item: Dictionary = particles[i]

		item["life"] = float(item["life"]) - delta

		if float(item["life"]) <= 0.0:
			particles.remove_at(i)
		else:
			var point: Vector2 = item["position"]
			var velocity: Vector2 = item["velocity"]

			item["position"] = point + velocity * delta


# ============================================================
# DRAW HELPERS
# ============================================================

func glow(point: Vector2, radius: float, color: Color) -> void:
	for i in range(5, 0, -1):
		draw_circle(
			point,
			radius * float(i) / 3.0,
			Color(color.r, color.g, color.b, 0.025)
		)


func flame(point: Vector2, size: float, color: Color) -> void:
	var flicker: float = sin(clock * 10.0) * 2.0

	var shape := PackedVector2Array([
		point + Vector2(0, -size * 1.7 - flicker),
		point + Vector2(size * 0.7, -size * 0.4),
		point + Vector2(size, size * 0.2),
		point + Vector2(size * 0.5, size * 0.8),
		point + Vector2(-size * 0.5, size * 0.8),
		point + Vector2(-size, size * 0.2)
	])

	draw_colored_polygon(shape, color)

	draw_circle(
		point + Vector2(0, size * 0.2),
		size * 0.45,
		Color("#fff0b5")
	)


# ============================================================
# HORROR BACKGROUNDS (3 SCENES)
# ============================================================

func draw_horror_background() -> void:
	var scene_index: int = int(
		float(background_level - 1) / 2.0
	)

	scene_index = clampi(scene_index, 0, 2)

	var sky_colors: Array[Color] = [
		Color("#110b20"),
		Color("#101522"),
		Color("#071711")
	]

	var sky: Color = sky_colors[scene_index]

	draw_rect(
		Rect2(0, 0, 1100, 720),
		sky.lerp(
			Color("#59402f"),
			restoration * 0.6
		)
	)

	match scene_index:
		0:
			horror_moon(
				Vector2(920, 115),
				37,
				Color("#aaa1ca")
			)

			for i in range(7):
				var x: float = 20.0 + float(i) * 165.0

				var height: float = (
					155.0 + sin(float(i) * 2.0) * 45.0
				)

				horror_building(
					Rect2(x, 650.0 - height, 100, height),
					true,
					Color("#281d36"),
					Color(0.8, 0.35, 0.2, 0.35)
				)

		1:
			horror_moon(
				Vector2(180, 115),
				45,
				Color("#a5b5cb")
			)

			for i in range(13):
				var point := Vector2(
					35.0 + float(i) * 90.0,
					580.0 + sin(float(i) * 2.0) * 35.0
				)

				horror_grave(point, 0.85)

			for i in range(23):
				var x: float = float(i) * 50.0

				draw_line(
					Vector2(x, 600),
					Vector2(x, 515),
					Color("#202637"),
					3.0
				)

				draw_line(
					Vector2(x - 8, 530),
					Vector2(x + 8, 530),
					Color("#202637"),
					3.0
				)

			draw_line(
				Vector2(0, 560),
				Vector2(1100, 560),
				Color("#202637"),
				4.0
			)

		2:
			horror_moon(
				Vector2(810, 120),
				30,
				Color("#a2b997")
			)

			for i in range(12):
				horror_tree(
					Vector2(float(i) * 100.0, 720),
					260.0 + sin(float(i) * 3.0) * 80.0,
					Color("#10271d")
				)

			for i in range(6):
				var x: float = 80.0 + float(i) * 180.0

				draw_circle(
					Vector2(x, 440),
					2.0,
					Color(0.8, 1.0, 0.4, 0.5)
				)

				draw_circle(
					Vector2(x + 8, 440),
					2.0,
					Color(0.8, 1.0, 0.4, 0.5)
				)

	for i in range(5):
		var y: float = (
			170.0
			+ float(i) * 100.0
			+ float(scene_index) * 3.0
			+ sin(clock * 0.25 + float(i)) * 13.0
		)

		draw_rect(
			Rect2(0, y, 1100, 27),
			Color(0.55, 0.46, 0.65, 0.035)
		)


func horror_moon(
	point: Vector2,
	radius: float,
	color: Color
) -> void:
	glow(point, radius * 1.6, color)
	draw_circle(point, radius, color)

	draw_circle(
		point + Vector2(-radius * 0.25, radius * 0.1),
		radius * 0.15,
		Color(color.r * 0.8, color.g * 0.8, color.b * 0.8)
	)


func horror_building(
	rect: Rect2,
	pitched_roof: bool,
	color: Color,
	window_color: Color
) -> void:
	draw_rect(rect, color)

	if pitched_roof:
		var roof := PackedVector2Array([
			rect.position + Vector2(-12, 0),
			Vector2(rect.get_center().x, rect.position.y - 50),
			Vector2(rect.end.x + 12, rect.position.y)
		])

		draw_colored_polygon(roof, color)

	var columns: int = maxi(
		int(rect.size.x / 55.0),
		1
	)

	var rows: int = maxi(
		int(rect.size.y / 65.0),
		1
	)

	for row in range(rows):
		for column in range(columns):
			var point := Vector2(
				rect.position.x + 17.0 + float(column) * 55.0,
				rect.position.y + 25.0 + float(row) * 65.0
			)

			draw_rect(
				Rect2(point, Vector2(17, 27)),
				window_color
			)

			draw_line(
				point + Vector2(8, 0),
				point + Vector2(8, 27),
				color,
				2.0
			)


func horror_tree(
	base: Vector2,
	height: float,
	color: Color
) -> void:
	var top: Vector2 = base + Vector2(25, -height)

	draw_line(base, top, color, 13.0)

	draw_line(
		base + Vector2(12, -height * 0.45),
		base + Vector2(-45, -height * 0.7),
		color,
		7.0
	)

	draw_line(
		base + Vector2(18, -height * 0.65),
		base + Vector2(80, -height * 0.9),
		color,
		6.0
	)

	draw_line(
		top,
		top + Vector2(-35, -45),
		color,
		5.0
	)


func horror_grave(point: Vector2, scale_value: float) -> void:
	var color := Color("#333747")

	draw_rect(
		Rect2(
			point + Vector2(-17, -35) * scale_value,
			Vector2(34, 50) * scale_value
		),
		color
	)

	draw_circle(
		point + Vector2(0, -35) * scale_value,
		17.0 * scale_value,
		color
	)

	draw_line(
		point + Vector2(0, -32) * scale_value,
		point + Vector2(0, -7) * scale_value,
		Color("#171b28"),
		3.0
	)

	draw_line(
		point + Vector2(-8, -23) * scale_value,
		point + Vector2(8, -23) * scale_value,
		Color("#171b28"),
		3.0
	)


# ============================================================
# JUNGLE BACKGROUND
# ============================================================

func draw_jungle_background() -> void:
	draw_rect(
		Rect2(0, 0, 1100, 720),
		Color("#08251c").lerp(
			Color("#425a25"),
			restoration * 0.6
		)
	)

	glow(Vector2(900, 110), 75, Color("#e9db8b"))
	draw_circle(Vector2(900, 110), 38, Color("#d7d48b"))

	for i in range(10):
		var x: float = float(i) * 125.0

		var height: float = (
			260.0 + sin(float(i) * 2.0) * 75.0
		)

		draw_rect(
			Rect2(x + 35, 720 - height, 25, height),
			Color("#143a29")
		)

		draw_circle(
			Vector2(x + 45, 720 - height),
			88,
			Color("#174c32")
		)

		draw_circle(
			Vector2(x + 10, 690 - height),
			60,
			Color("#1d5939")
		)

	for i in range(12):
		var x: float = float(i) * 100.0 + 20.0

		var length: float = (
			90.0 + sin(float(i) * 3.0) * 45.0
		)

		var swing: float = (
			sin(clock * 0.7 + float(i)) * 7.0
		)

		draw_line(
			Vector2(x, 0),
			Vector2(x + swing, length),
			Color("#4c7f3e"),
			3.0
		)

		draw_circle(
			Vector2(x + swing, length),
			7,
			Color("#5c9649")
		)

	for i in range(13):
		draw_circle(
			Vector2(float(i) * 95.0, 10),
			70,
			Color("#103b27")
		)

	for i in range(18):
		var point := Vector2(
			fmod(
				float(i) * 83.0 + sin(clock + float(i)) * 15.0,
				1100.0
			),
			170.0 + fmod(
				float(i) * 53.0 + clock * 5.0,
				480.0
			)
		)

		draw_circle(
			point,
			2.0,
			Color(0.85, 1.0, 0.45, 0.5)
		)


# ============================================================
# SEASON 2 BACKGROUNDS
# ============================================================

func draw_season_2_background() -> void:
	var local_level: int = season_level(background_level)

	match local_level:
		1:
			draw_summer_world()
		2:
			draw_winter_world()
		3:
			draw_spring_world()
		4:
			draw_autumn_world()
		5:
			draw_city_world()
		6:
			draw_ocean_world()


func draw_summer_world() -> void:
	draw_rect(
		Rect2(0, 0, 1100, 720),
		Color("#82cddd")
	)

	glow(Vector2(900, 110), 70, Color("#ffe39b"))
	draw_circle(Vector2(900, 110), 42, Color("#ffe39b"))

	draw_environment_cloud(
		Vector2(200, 170),
		Color("#d9f0e9")
	)

	draw_environment_cloud(
		Vector2(620, 220),
		Color("#d9f0e9")
	)

	draw_rect(
		Rect2(0, 440, 1100, 280),
		Color("#4aaeb7")
	)

	draw_rect(
		Rect2(0, 560, 1100, 160),
		Color("#d7bd7d")
	)

	for i in range(8):
		var x: float = float(i) * 155.0

		draw_arc(
			Vector2(
				x + sin(clock + float(i)) * 12.0,
				530
			),
			65,
			0,
			PI,
			24,
			Color(0.85, 1.0, 1.0, 0.25),
			3.0,
			true
		)

	for x in [140.0, 950.0]:
		var top := Vector2(x + 30, 380)

		draw_line(
			Vector2(x, 680),
			top,
			Color("#756044"),
			13.0
		)

		for i in range(5):
			var angle: float = (
				-PI + float(i) * PI / 4.0
			)

			draw_line(
				top,
				top + Vector2.from_angle(angle) * 90.0,
				Color("#40764d"),
				13.0
			)


func draw_winter_world() -> void:
	draw_rect(
		Rect2(0, 0, 1100, 720),
		Color("#a6c2d4")
	)

	draw_circle(
		Vector2(900, 115),
		36,
		Color("#e5edf0")
	)

	for i in range(5):
		var x: float = float(i) * 280.0 - 80.0
		var peak_y: float = 230.0 + float(i % 2) * 70.0

		var mountain := PackedVector2Array([
			Vector2(x, 650),
			Vector2(x + 170, peak_y),
			Vector2(x + 350, 650)
		])

		draw_colored_polygon(
			mountain,
			Color("#7894b1")
		)

		var snow_cap := PackedVector2Array([
			Vector2(x + 115, peak_y + 135),
			Vector2(x + 170, peak_y),
			Vector2(x + 230, peak_y + 135)
		])

		draw_colored_polygon(
			snow_cap,
			Color("#d9e6e9")
		)

	draw_rect(
		Rect2(0, 620, 1100, 100),
		Color("#c5dce2")
	)

	for i in range(45):
		var point := Vector2(
			fmod(
				float(i) * 83.0 + clock * 12.0,
				1100.0
			),
			fmod(
				float(i) * 53.0 + clock * 25.0,
				720.0
			)
		)

		draw_circle(
			point,
			2.0,
			Color(1.0, 1.0, 1.0, 0.6)
		)


func draw_spring_world() -> void:
	draw_rect(
		Rect2(0, 0, 1100, 720),
		Color("#9ad8cb")
	)

	draw_circle(
		Vector2(880, 110),
		37,
		Color("#f5df9a")
	)

	draw_environment_cloud(
		Vector2(220, 160),
		Color("#dfefe0")
	)

	draw_environment_cloud(
		Vector2(650, 220),
		Color("#dfefe0")
	)

	for i in range(5):
		draw_circle(
			Vector2(float(i) * 300.0, 760),
			300,
			Color("#79ad78")
		)

	draw_rect(
		Rect2(0, 625, 1100, 95),
		Color("#60945d")
	)

	for i in range(5):
		draw_environment_tree(
			Vector2(90.0 + float(i) * 240.0, 660),
			Color("#a47b66"),
			Color("#d6a8bb")
		)

	for i in range(35):
		var point := Vector2(
			float((i * 73) % 1100),
			645.0 + float((i * 19) % 60)
		)

		var color: Color = (
			Color("#ecc3d3")
			if i % 2 == 0
			else Color("#e4dc91")
		)

		draw_circle(point, 4, color)


func draw_autumn_world() -> void:
	draw_rect(
		Rect2(0, 0, 1100, 720),
		Color("#b99a80")
	)

	draw_circle(
		Vector2(900, 110),
		40,
		Color("#e2bd88")
	)

	draw_rect(
		Rect2(0, 590, 1100, 130),
		Color("#78563d")
	)

	for i in range(7):
		var leaf_color: Color = (
			Color("#a95c38")
			if i % 2 == 0
			else Color("#b48b3d")
		)

		draw_environment_tree(
			Vector2(
				40.0 + float(i) * 180.0,
				680
			),
			Color("#614c3d"),
			leaf_color
		)

	for i in range(28):
		var point := Vector2(
			fmod(
				float(i) * 87.0 + clock * 30.0,
				1100.0
			),
			150.0 + fmod(
				float(i) * 49.0 + clock * 18.0,
				550.0
			)
		)

		draw_line(
			point,
			point + Vector2(7, 4),
			Color("#c49447"),
			3.0
		)


func draw_city_world() -> void:
	draw_rect(
		Rect2(0, 0, 1100, 720),
		Color("#121d38")
	)

	draw_circle(
		Vector2(900, 105),
		33,
		Color("#a4b5d5")
	)

	for i in range(10):
		var x: float = float(i) * 120.0
		var height: float = (
			210.0 + float((i * 73) % 230)
		)

		var top: float = 650.0 - height

		draw_rect(
			Rect2(x, top, 95, height),
			Color("#22334e")
		)

		for row in range(5):
			for column in range(3):
				var y: float = top + 24.0 + float(row) * 40.0

				if y + 15.0 > 650.0:
					continue

				draw_rect(
					Rect2(
						x + 12.0 + float(column) * 27.0,
						y,
						12,
						15
					),
					Color("#7899a7")
					if (row + column + i) % 3 == 0
					else Color("#b19f72")
				)

	draw_rect(
		Rect2(0, 650, 1100, 70),
		Color("#172230")
	)

	for i in range(12):
		draw_rect(
			Rect2(float(i) * 100.0, 685, 50, 4),
			Color("#8e926f")
		)


func draw_ocean_world() -> void:
	draw_rect(
		Rect2(0, 0, 1100, 720),
		Color("#0a3f62")
	)

	draw_rect(
		Rect2(0, 0, 1100, 180),
		Color("#145b78")
	)

	for i in range(6):
		var x: float = float(i) * 220.0

		var ray := PackedVector2Array([
			Vector2(x, 100),
			Vector2(x + 45, 100),
			Vector2(x + 190, 650),
			Vector2(x + 80, 650)
		])

		draw_colored_polygon(
			ray,
			Color(0.5, 0.9, 1.0, 0.035)
		)

	draw_rect(
		Rect2(0, 650, 1100, 70),
		Color("#486a65")
	)

	for i in range(18):
		var x: float = float(i) * 68.0
		var sway: float = sin(clock + float(i)) * 12.0

		draw_line(
			Vector2(x, 720),
			Vector2(x + sway, 590 - (i % 3) * 20),
			Color("#267269"),
			7.0
		)

	for i in range(22):
		var point := Vector2(
			float((i * 97) % 1100),
			720.0 - fmod(
				float(i) * 61.0 + clock * 24.0,
				720.0
			)
		)

		draw_arc(
			point,
			3.0 + float(i % 3),
			0,
			TAU,
			16,
			Color(0.6, 0.9, 1.0, 0.3),
			1.0,
			true
		)

	for i in range(7):
		var point := Vector2(
			fmod(
				float(i) * 180.0 + clock * 18.0,
				1180.0
			) - 40.0,
			220.0 + float(i % 4) * 85.0
		)

		draw_circle(
			point,
			7,
			Color("#83aaa4")
		)

		var tail := PackedVector2Array([
			point + Vector2(-6, 0),
			point + Vector2(-17, -7),
			point + Vector2(-17, 7)
		])

		draw_colored_polygon(
			tail,
			Color("#83aaa4")
		)


func draw_environment_cloud(
	point: Vector2,
	color: Color
) -> void:
	draw_circle(point, 28, color)
	draw_circle(point + Vector2(30, -15), 37, color)
	draw_circle(point + Vector2(65, 0), 29, color)


func draw_environment_tree(
	base: Vector2,
	trunk_color: Color,
	leaf_color: Color
) -> void:
	draw_rect(
		Rect2(
			base + Vector2(-10, -175),
			Vector2(20, 175)
		),
		trunk_color
	)

	draw_circle(
		base + Vector2(0, -190),
		64,
		leaf_color
	)

	draw_circle(
		base + Vector2(-40, -155),
		48,
		leaf_color
	)

	draw_circle(
		base + Vector2(40, -155),
		48,
		leaf_color
	)


# ============================================================
# MAIN DRAW
# ============================================================

func _draw() -> void:
	if background_level > SEASON_1_LEVELS:
		draw_season_2_background()
	elif level_is_horror(background_level):
		draw_horror_background()
	else:
		draw_jungle_background()

	if mode in [
		"title",
		"select",
		"brief",
		"season_welcome"
	]:
		return

	draw_map()
	draw_objectives()
	draw_enemy_visuals()
	draw_echo_visuals()
	draw_player_visuals()
	draw_particle_visuals()

	if mode == "restoring" or mode == "won":
		draw_arc(
			GOAL,
			20.0 + restoration * 1250.0,
			0,
			TAU,
			100,
			Color(
				1.0,
				0.85,
				0.55,
				(1.0 - restoration) * 0.6
			),
			12.0,
			true
		)


func draw_map() -> void:
	var block_color: Color
	var edge_color: Color

	if current_level > SEASON_1_LEVELS:
		var block_colors: Array[Color] = [
			Color("#9b7845"),
			Color("#668fa9"),
			Color("#496c44"),
			Color("#805237"),
			Color("#324665"),
			Color("#24626a")
		]

		var edge_colors: Array[Color] = [
			Color("#f2d898"),
			Color("#d9f6ff"),
			Color("#a8dc8b"),
			Color("#e1ac6c"),
			Color("#85c9f2"),
			Color("#8de1d8")
		]

		var index: int = season_level(current_level) - 1

		block_color = block_colors[index]
		edge_color = edge_colors[index]
	else:
		block_color = (
			Color("#303047")
			if level_is_horror(current_level)
			else Color("#315740")
		)

		edge_color = (
			Color("#69617e")
			if level_is_horror(current_level)
			else Color("#75a565")
		)

	for rect in walls:
		draw_rect(
			rect.grow(3.0),
			Color(0.02, 0.03, 0.05, 0.7)
		)

		draw_rect(rect, block_color)
		draw_rect(rect, edge_color, false, 2.0)

	for rect in hazards:
		draw_rect(rect, Color("#54203b"))
		draw_rect(
			rect,
			Color("#ff7388"),
			false,
			2.0
		)

		draw_line(
			rect.position,
			rect.end,
			Color("#ff7388"),
			2.0
		)

		draw_line(
			Vector2(rect.end.x, rect.position.y),
			Vector2(rect.position.x, rect.end.y),
			Color("#ff7388"),
			2.0
		)


func draw_objectives() -> void:
	for i in range(seals.size()):
		var color: Color = (
			Color("#8ffaff")
			if seal_active[i]
			else Color("#4489b5")
		)

		draw_arc(
			seals[i],
			33,
			0,
			TAU,
			48,
			color,
			3.0,
			true
		)

		draw_string(
			ThemeDB.fallback_font,
			seals[i] + Vector2(-22, 56),
			"BONUS" if seal_active[i] else "ECHO",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			color
		)

	for i in range(points.size()):
		if not point_taken[i]:
			var bob: float = (
				sin(clock * 3.0 + float(i)) * 3.0
			)

			var point: Vector2 = (
				points[i] + Vector2(0, bob)
			)

			glow(point, 20, Color("#ffd580"))
			flame(point, 8, Color("#ffc56a"))
		else:
			draw_circle(
				points[i],
				3,
				Color("#ffe4a0")
			)

	for point in crystals:
		glow(point, 22, Color("#64e7ff"))

		var diamond := PackedVector2Array([
			point + Vector2(0, -18),
			point + Vector2(12, 0),
			point + Vector2(0, 18),
			point + Vector2(-12, 0)
		])

		draw_colored_polygon(
			diamond,
			Color("#64e7ff")
		)

	var checkpoint_color: Color = (
		Color("#ffd58a")
		if checkpoint_active
		else Color("#80715a")
	)

	draw_arc(
		checkpoint,
		24,
		0,
		TAU,
		40,
		checkpoint_color,
		3.0,
		true
	)

	if checkpoint_active:
		glow(checkpoint, 35, checkpoint_color)
		flame(checkpoint, 10, Color("#ffb347"))

	var ready: bool = exit_open()

	var goal_color: Color = (
		Color("#ffe3a0")
		if ready
		else Color("#817768")
	)

	draw_arc(
		GOAL,
		32,
		0,
		TAU,
		48,
		goal_color,
		4.0,
		true
	)

	if ready:
		glow(GOAL, 45, goal_color)
		flame(GOAL, 15, Color("#ffb347"))

	draw_string(
		ThemeDB.fallback_font,
		GOAL + Vector2(-29, 58),
		"ENTER" if ready else "LOCKED",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		15,
		goal_color
	)


func draw_enemy_visuals() -> void:
	for enemy in enemies:
		if not bool(enemy["alive"]):
			continue

		var body: CharacterBody2D = enemy["body"]
		var point: Vector2 = body.position
		var phase: String = enemy["phase"]
		var color := Color("#a15c72")

		if phase == "windup":
			color = Color("#ffb34e")

			var target: Vector2 = (
				echo_position if echo_active else player.position
			)

			draw_line(
				point,
				target,
				Color(1.0, 0.4, 0.3, 0.35),
				2.0
			)

		elif phase == "lunge":
			color = Color("#ff476a")

		elif phase == "stunned":
			color = Color("#bc8aff")
			glow(point, 30, color)

		var radius: float = (
			23.0 if bool(enemy["boss"]) else 15.0
		)

		draw_circle(point, radius, Color("#1b1525"))

		draw_arc(
			point,
			radius,
			0,
			TAU,
			32,
			color,
			3.0,
			true
		)

		draw_circle(point + Vector2(-5, -2), 2.5, color)
		draw_circle(point + Vector2(5, -2), 2.5, color)

		if enemy["kind"] == "watcher":
			draw_rect(
				Rect2(
					point + Vector2(-7, 8),
					Vector2(14, 8)
				),
				color
			)

		elif enemy["kind"] == "wisp":
			draw_arc(
				point,
				radius + 5,
				clock,
				clock + PI,
				20,
				color,
				2.0,
				true
			)

		if bool(enemy["boss"]):
			draw_string(
				ThemeDB.fallback_font,
				point + Vector2(-25, -32),
				"BOSS %d" % int(enemy["hp"]),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				14,
				color
			)

	for shot in bullets:
		var point: Vector2 = shot["position"]
		draw_circle(point, 5, Color("#ff557b"))


func draw_echo_visuals() -> void:
	if history.size() > 1 and not echo_active:
		for i in range(1, history.size()):
			draw_line(
				history[i - 1],
				history[i],
				Color(0.3, 0.75, 1.0, 0.13),
				2.0
			)

	if not echo_active:
		return

	for i in range(1, echo_path.size()):
		draw_line(
			echo_path[i - 1],
			echo_path[i],
			Color(0.3, 0.8, 1.0, 0.15),
			2.0
		)

	glow(echo_position, 30, Color("#72e6ff"))
	flame(echo_position, 13, Color("#72dcff"))


func draw_player_visuals() -> void:
	for i in range(trail.size()):
		var alpha: float = (
			float(i + 1) / float(trail.size()) * 0.25
		)

		draw_circle(
			trail[i],
			6,
			Color(1.0, 0.5, 0.2, alpha)
		)

	if mode not in ["aim", "move", "rewind", "paused"]:
		return

	glow(player.position, 35, Color("#ffb347"))

	if protection <= 0.0 or int(clock * 12.0) % 2 == 0:
		var color: Color = (
			Color("#72e6ff")
			if mode == "rewind"
			else Color("#ffb347")
		)

		flame(player.position, 13, color)

		draw_circle(
			player.position + Vector2(-4, -1),
			2,
			Color("#302333")
		)

		draw_circle(
			player.position + Vector2(4, -1),
			2,
			Color("#302333")
		)

	if mode == "aim" or mode == "move":
		var aim: Vector2 = (
			get_global_mouse_position() - player.position
		)

		if aim.length_squared() > 1.0:
			draw_line(
				player.position,
				player.position + aim.normalized() * 65.0,
				Color(1.0, 0.85, 0.55, 0.5),
				2.0
			)


func draw_particle_visuals() -> void:
	for item in particles:
		var color: Color = item["color"]

		color.a = clampf(
			float(item["life"]) * 1.5,
			0.0,
			1.0
		)

		var point: Vector2 = item["position"]
		draw_circle(point, 2.5, color)
