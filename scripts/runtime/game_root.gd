class_name MireGameRoot
extends Control
## Persistent runtime. WorldRouter replaces only the scene inside WorldContainer.

signal action_result(result: MireTypes.ActionResult)
signal world_ready(world: Node3D)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var player: MirePlayer
var world_container: Node3D
var router: WorldRouter
var campaign: CampaignWorld
var crypt: CryptContent
var modes: GameModeController
var interaction: InteractionRay
var modal_host: ModalHost
var game_view: SubViewport
var view_texture: TextureRect
var interface: Control
var display_rect: Rect2
var ui: GameUI
var _session_bound: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	game_view = SubViewport.new()
	game_view.name = "GameView"
	game_view.own_world_3d = true
	game_view.handle_input_locally = false
	game_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game_view.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game_view)
	view_texture = TextureRect.new()
	view_texture.name = "WorldImage"
	view_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_texture.texture = game_view.get_texture()
	add_child(view_texture)
	world_container = Node3D.new()
	world_container.name = "WorldContainer"
	game_view.add_child(world_container)
	player = PLAYER_SCENE.instantiate()
	game_view.add_child(player)
	player.set_input_enabled(false)
	interface = Control.new()
	interface.name = "Interface"
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(interface)
	modal_host = ModalHost.new()
	modal_host.name = "ModalHost"
	interface.add_child(modal_host)
	modes = GameModeController.new()
	modes.name = "GameModeController"
	add_child(modes)
	modes.configure(player, modal_host)
	modes.mode_changed.connect(_mode_changed)
	modes.push_mode(&"title")
	router = WorldRouter.new()
	router.name = "WorldRouter"
	add_child(router)
	var configured := router.configure(player, world_container, modes, interface)
	if not configured.ok:
		push_error(configured.message_key)
	campaign = CampaignWorld.new(player)
	crypt = CryptContent.new()
	router.world_builder = _build_world
	router.world_activated.connect(_world_activated)
	var bound := bind_session_services()
	if not bound.ok:
		push_error(bound.message_key)
	interaction = InteractionRay.new()
	interaction.name = "InteractionRay"
	player.add_child(interaction)
	interaction.configure(player, modes)
	interaction.interaction_completed.connect(_report_action)
	player.combat.died.connect(_player_died)
	resized.connect(apply_settings)
	SaveService.settings_changed.connect(_settings_changed)
	apply_settings()
	_apply_window_settings()
	ui = GameUI.new()
	ui.name = "GameUI"
	interface.add_child(ui)
	var interface_ready := ui.configure(self)
	if not interface_ready.ok:
		push_error(interface_ready.message_key)

func bind_session_services() -> MireTypes.ActionResult:
	if _session_bound:
		return MireTypes.success()
	var bound := GameSession.recovery.bind_runtime(player, router.is_dangerous, router.reset_living_encounters, router.recovery_travel)
	if not bound.ok:
		return bound
	bound = SaveService.bind_runtime(player, router)
	if not bound.ok:
		GameSession.recovery.unbind_runtime()
		return bound
	_session_bound = true
	return MireTypes.success()

func start_new_game(confirm_replace_autosave: bool = false) -> MireTypes.ActionResult:
	var bound := bind_session_services()
	if not bound.ok:
		return bound
	return await SaveService.start_new_game(confirm_replace_autosave)

func load_slot(slot_id: StringName, use_backup: bool = false) -> MireTypes.ActionResult:
	var bound := bind_session_services()
	if not bound.ok:
		return bound
	return await SaveService.load_slot(slot_id, use_backup)

func leave_to_title() -> MireTypes.ActionResult:
	var left := SaveService.leave_session()
	if not left.ok:
		return left
	_session_bound = false
	interaction.clear_focus()
	if is_instance_valid(router.current_world):
		router.current_world.free()
	router.current_world = null
	router.loaded_scene_id = &""
	router.last_safe.clear()
	player.set_input_enabled(false)
	modes.push_mode(&"title")
	return MireTypes.success()

func apply_settings() -> void:
	if not is_instance_valid(game_view):
		return
	display_rect = fitted_rect(size)
	view_texture.position = display_rect.position
	view_texture.size = display_rect.size
	var aspect: float = display_rect.size.x / maxf(1.0, display_rect.size.y)
	if SaveService.settings.render_mode == "retro":
		game_view.size = Vector2i(roundi(540.0 * aspect), 540)
	else:
		var root_size: Vector2 = get_viewport_rect().size
		var pixel_scale := Vector2(get_window().size) / root_size.max(Vector2.ONE)
		game_view.size = Vector2i((display_rect.size * pixel_scale).round().max(Vector2.ONE))
	player.apply_settings()
	_apply_shadows()

static func fitted_rect(available: Vector2) -> Rect2:
	var extent := available.max(Vector2.ONE)
	var aspect: float = extent.x / extent.y
	if aspect < 4.0 / 3.0:
		extent.y = extent.x * 3.0 / 4.0
	elif aspect > 21.0 / 9.0:
		extent.x = extent.y * 21.0 / 9.0
	return Rect2((available - extent) * 0.5, extent)

func _unhandled_input(event: InputEvent) -> void:
	# Menus consume their events first. Only the captured gameplay view receives look.
	if modes.mode == &"gameplay" and event is InputEventMouseMotion:
		game_view.push_input(event)

func _build_world(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	var built := campaign.build(world, candidate)
	if not built.ok:
		return built
	if StringName(world.get("scene_id")) == &"interior_crypt":
		built = campaign.populate_encounters(world, candidate)
		if not built.ok:
			return built
		return crypt.build(world, candidate)
	return built

func _world_activated(world: Node3D) -> void:
	for node: Node in world.find_children("*", "", true, false):
		if node is NpcActor:
			var activated: MireTypes.ActionResult = node.activate()
			if not activated.ok:
				_report_action(activated)
		elif node is TrainingDummy:
			node.activate()
		elif node is WorldObject:
			var activated: MireTypes.ActionResult = node.activate()
			if not activated.ok:
				_report_action(activated)
	var populated := campaign.activate(world)
	if not populated.ok:
		_report_action(populated)
	if StringName(world.get("scene_id")) == &"interior_crypt":
		var activated := crypt.activate(world)
		if not activated.ok:
			_report_action(activated)
	_apply_shadows()
	world_ready.emit(world)

func _apply_shadows() -> void:
	if not is_instance_valid(router) or not is_instance_valid(router.current_world):
		return
	for node: Node in router.current_world.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = node
		sun.shadow_enabled = SaveService.settings.shadows != "off"
		sun.directional_shadow_max_distance = 140.0 if SaveService.settings.shadows == "high" else 70.0

func _mode_changed(mode: StringName) -> void:
	view_texture.visible = GameSession.active and mode != &"title"
	if mode not in [&"dialogue", &"confirmation", &"readable"] and GameSession.dialogue != null:
		GameSession.dialogue.close()

func _settings_changed(_settings: Dictionary) -> void:
	apply_settings()
	_apply_window_settings()

func _apply_window_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if SaveService.settings.fullscreen and window.mode not in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = Window.MODE_FULLSCREEN
	elif not SaveService.settings.fullscreen and window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if SaveService.settings.vsync else DisplayServer.VSYNC_DISABLED)

func _report_action(result: MireTypes.ActionResult) -> void:
	action_result.emit(result)
	if not result.ok:
		EventBus.feedback.emit(String(result.message_key))

func _player_died(_entity_id: StringName) -> void:
	modes.push_mode(&"death")

func _exit_tree() -> void:
	SaveService.unbind_runtime()
	GameSession.dialogue.close()
	GameSession.recovery.unbind_runtime()
	GameSession.active = false
