class_name GameUI
extends Control
## Native presentation and command routing. Domain services own all saved changes.

var game: MireGameRoot
var hud: GameHUD
var inventory: InventoryPanel
var shop: InventoryPanel
var settings: SettingsPanel
var journal: JournalPanel
var map_panel: JournalPanel
var panels: Dictionary = {}
var feedback: Label
var hint: Label
var _hint_id: String = ""
var _hint_left: float = 0.0
var _feedback_left: float = 0.0
var _dirty: bool = false
var _busy: bool = false
var _previous_mode: StringName = &"title"
var _awaiting_ending: bool = false
var _epilogue_page: int = 0
var _epilogue_return: Array[StringName] = []

func configure(owner_game: MireGameRoot) -> MireTypes.ActionResult:
	if game != null or not is_node_ready() or not is_instance_valid(owner_game):
		return MireTypes.failure(&"invalid_runtime", &"The interface needs one ready game root.")
	game = owner_game
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = GameHUD.new()
	add_child(hud)
	hud.configure(game)
	for mode: StringName in [&"title", &"pause", &"save", &"load", &"dialogue", &"readable", &"confirmation", &"death", &"epilogue", &"travel"]:
		var panel := VBoxContainer.new()
		_register(mode, panel)
	inventory = InventoryPanel.new()
	_register(&"inventory", inventory)
	inventory.configure(self)
	shop = InventoryPanel.new()
	_register(&"shop", shop)
	shop.configure(self)
	settings = SettingsPanel.new()
	_register(&"settings", settings)
	settings.configure(self)
	journal = JournalPanel.new()
	_register(&"journal", journal)
	journal.configure(self)
	map_panel = JournalPanel.new()
	_register(&"map", map_panel)
	map_panel.configure(self, true)
	feedback = UIStyle.label("")
	UIStyle.outline(feedback)
	feedback.position = Vector2(24, 8)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	feedback.offset_left = 24
	feedback.offset_right = -24
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(feedback)
	hint = UIStyle.label("")
	UIStyle.outline(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	hint.position = Vector2(24, -55)
	hint.size = Vector2(360, 110)
	add_child(hint)
	game.action_result.connect(handle_action)
	game.world_ready.connect(_world_ready)
	game.modes.mode_changed.connect(_mode_changed)
	game.router.travel_completed.connect(_travel_finished)
	SaveService.settings_changed.connect(_settings_changed)
	SaveService.autosave_finished.connect(_autosave_finished)
	EventBus.feedback.connect(show_feedback)
	EventBus.inventory_changed.connect(_mark_dirty)
	EventBus.currency_changed.connect(_mark_dirty)
	EventBus.quest_updated.connect(func(_id: StringName) -> void: _mark_dirty())
	EventBus.choice_committed.connect(func(_id: StringName, _value: StringName) -> void: _mark_dirty())
	EventBus.session_restored.connect(_mark_dirty)
	GameSession.recovery.consumption_finished.connect(_consumption_finished)
	game.player.combat.feedback.connect(_combat_feedback)
	_settings_changed(SaveService.settings)
	_mode_changed(game.modes.mode)
	return MireTypes.success()

func _register(mode: StringName, panel: Control) -> void:
	panel.name = String(mode).capitalize() + "Panel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panels[mode] = panel
	game.modal_host.register_panel(mode, panel)

func _process(delta: float) -> void:
	if game == null:
		return
	_feedback_left = maxf(0, _feedback_left - delta)
	feedback.visible = _feedback_left > 0
	hint.visible = not _hint_id.is_empty() and game.modes.mode == &"gameplay"
	if hint.visible:
		_hint_left -= delta
		if _hint_left <= 0:
			dismiss_hint()
		elif Input.is_action_pressed(&"move_forward") and _hint_id == "movement":
			_hint_left = minf(_hint_left, 2)
	if _dirty:
		_dirty = false
		refresh()
	if game.modes.mode == &"gameplay" and _hint_id.is_empty():
		if game.interaction.offer != null:
			show_hint("interaction", "Look at a person or object and press [" + InputBindings.label(&"interact") + "] to interact.")
		elif hud.target.visible:
			show_hint("combat", "Light attack [" + InputBindings.label(&"attack_light") + "]; heavy attack [" + InputBindings.label(&"attack_heavy") + "]. Face attacks and hold [" + InputBindings.label(&"block") + "] to block. Raise it just before impact to parry.")
		elif float(GameSession.state.player.health) < 65:
			show_hint("healing", "Press [" + InputBindings.label(&"quick_heal") + "] to use a bandage. Damage interrupts healing without using it up.")

func refresh() -> void:
	if game == null:
		return
	match game.modes.mode:
		&"title": _title()
		&"pause": _pause()
		&"inventory": inventory.refresh()
		&"shop": shop.refresh()
		&"journal": journal.refresh()
		&"map": map_panel.refresh()
		&"save", &"load": _slots(game.modes.mode == &"save")
		&"dialogue": _dialogue()
		&"death": _death()

func handle_action(result: MireTypes.ActionResult) -> void:
	if not result.ok:
		report(result)
		if result.payload.has("dialogue") and not result.payload.dialogue.is_empty():
			_dialogue()
		return
	var action: String = result.payload.get("ui_action", "")
	match action:
		"dialogue":
			game.modes.push_mode(&"dialogue")
			_dialogue()
		"close_dialogue": game.modes.push_mode(&"gameplay")
		"shop":
			shop.shop_id = StringName(result.payload.shop_id)
			game.modes.push_mode(&"shop")
			shop.refresh()
		"rest": report(GameSession.recovery.rest(StringName(result.payload.rest_id), UIStyle.action_id("rest")))
		"loot":
			var opened := inventory.open_loot(StringName(result.payload.entity_id))
			if not opened.ok:
				report(opened)
				return
			game.modes.push_mode(&"inventory")
			inventory.refresh()
		"readable": show_document(StringName(result.payload.document_id))
		"writ": _show_writ()
		"training": _training()
		"challenge_rusk":
			var world: Node3D = game.router.current_world
			var boss: Node = world.entities.get(StringName(result.payload.entity_id)) if is_instance_valid(world) else null
			if not is_instance_valid(boss) or not boss.has_method("challenge"):
				show_feedback("The captain's duel is not available in this scene.")
				return
			game.modes.push_mode(&"gameplay")
			var started: Variant = boss.call("challenge")
			if started is MireTypes.ActionResult:
				report(started)
			else:
				show_feedback("The captain could not begin the duel.")
		_: report(result)

func report(result: MireTypes.ActionResult, success_text: String = "") -> void:
	if not result.ok:
		show_feedback(String(result.message_key))
	elif not result.message_key.is_empty():
		show_feedback(String(result.message_key))
	elif result.payload.get("started", false):
		show_feedback("Using the item. Stay clear of attacks.")
	elif not success_text.is_empty():
		show_feedback(success_text)
	_mark_dirty()

func show_feedback(message: String) -> void:
	if feedback == null or message.is_empty():
		return
	feedback.text = message
	_feedback_left = 5.0
	feedback.visible = true

func show_hint(id: String, text: String) -> void:
	if id in SaveService.settings.dismissed_hints or not _hint_id.is_empty():
		return
	_hint_id = id
	_hint_left = 9
	hint.text = text + "\nHide this hint in Pause."

func dismiss_hint() -> void:
	if _hint_id.is_empty():
		return
	var candidate := SaveService.settings.duplicate(true)
	if _hint_id not in candidate.dismissed_hints:
		candidate.dismissed_hints.append(_hint_id)
	var result := SaveService.save_settings(candidate)
	if not result.ok:
		show_feedback(String(result.message_key))
	_hint_id = ""
	hint.visible = false

func confirm(title: String, text: String, action: Callable) -> void:
	var panel: VBoxContainer = panels[&"confirmation"]
	UIStyle.clear(panel)
	var column := UIStyle.scroll_content(panel)
	column.add_child(UIStyle.label(text))
	column.add_child(UIStyle.button("Confirm", func() -> void:
		game.modes.pop_mode()
		action.call()
	, "confirmation/confirm"))
	column.add_child(UIStyle.button("Cancel", game.modes.pop_mode, "confirmation/cancel"))
	game.modes.push_mode(&"confirmation")
	game.modal_host.set_heading(title)
	_focus_first(panel)

func show_document(document_id: StringName) -> void:
	var document := GameSession.quests.document_view(document_id)
	if document.is_empty():
		show_feedback("That document is not available.")
		return
	_show_text(document.title, document.text)

func _show_text(title: String, text: String) -> void:
	var panel: VBoxContainer = panels[&"readable"]
	UIStyle.clear(panel)
	UIStyle.scroll_content(panel).add_child(UIStyle.label(text))
	game.modes.push_mode(&"readable")
	game.modal_host.set_heading(title)

func _title() -> void:
	var column := _column(&"title")
	column.add_child(UIStyle.label("A borrowed sword. A broken road. A promise worth keeping.", true))
	var continued := SaveService.continue_slot()
	var button := UIStyle.button("Continue" if continued.ok else "Continue · no valid save", _continue, "title/continue")
	button.disabled = not continued.ok or _busy
	column.add_child(button)
	if not continued.ok:
		column.add_child(UIStyle.label(String(continued.message_key), true))
	column.add_child(UIStyle.button("New Game", _new_game, "title/new"))
	column.add_child(UIStyle.button("Load Game", func() -> void: game.modes.push_mode(&"load"), "title/load"))
	column.add_child(UIStyle.button("Settings", func() -> void: game.modes.push_mode(&"settings"), "title/settings"))
	column.add_child(UIStyle.button("Credits", func() -> void: _show_text("Credits", "MIREWARD\nOriginal low-poly models, textures, icons and world construction are authored locally for this game.\nBuilt with Godot 4.5.2. Open Sans SemiBold © 2011 Google Corporation, Apache 2.0.\nLicenses and asset provenance are included with the game."), "title/credits"))
	column.add_child(UIStyle.button("Quit", func() -> void: get_tree().quit(), "title/quit"))
	_focus_first(panels[&"title"])

func _pause() -> void:
	var column := _column(&"pause")
	column.add_child(UIStyle.button("Resume", func() -> void: game.modes.push_mode(&"gameplay"), "pause/resume"))
	column.add_child(UIStyle.button("Save Game", func() -> void: game.modes.push_mode(&"save"), "pause/save"))
	column.add_child(UIStyle.button("Load Game", func() -> void: game.modes.push_mode(&"load"), "pause/load"))
	column.add_child(UIStyle.button("Settings", func() -> void: game.modes.push_mode(&"settings"), "pause/settings"))
	if not _hint_id.is_empty():
		column.add_child(UIStyle.button("Hide this hint", func() -> void: dismiss_hint(); refresh(), "pause/hide_hint"))
	var pending := SaveService.pending_autosave()
	if pending.failed:
		column.add_child(UIStyle.label("Autosave failed. Your current progress is still in memory.", true))
		column.add_child(UIStyle.button("Retry autosave", func() -> void: report(SaveService.retry_autosave(), "Autosave completed."), "pause/retry_autosave"))
	column.add_child(UIStyle.button("Main menu", func() -> void: confirm("Return to title", "Return to the title? Unsaved progress since your last successful save will be lost.", func() -> void: report(game.leave_to_title())), "pause/title"))
	_focus_first(panels[&"pause"])

func _slots(saving: bool) -> void:
	var mode: StringName = &"save" if saving else &"load"
	var column := _column(mode)
	var availability := SaveService.save_availability()
	if saving:
		column.add_child(UIStyle.label("Manual saves load you at a safe local anchor. " + ("Choose a slot." if availability.ok else String(availability.message_key)), true))
	for row: Dictionary in SaveService.list_slots():
		if saving and row.id == "autosave":
			continue
		var label: String = String(row.id).replace("_", " ").capitalize()
		if row.valid:
			label += " · " + String(row.chapter) + "\n" + String(row.location) + " · " + Time.get_datetime_string_from_unix_time(int(row.timestamp)).replace("T", " ") + " UTC"
		else:
			label += " · " + ("Empty" if row.empty else String(row.message))
		column.add_child(UIStyle.label(label))
		var slot := StringName(row.id)
		if saving:
			var button := UIStyle.button("Save here", func() -> void:
				if row.empty:
					report(SaveService.save_slot(slot), "Game saved.")
				else:
					confirm("Replace manual save", "Replace this slot? Its previous valid save is retained as a backup.", func() -> void: report(SaveService.save_slot(slot), "Game saved."))
			, "save/" + row.id)
			button.disabled = not availability.ok
			column.add_child(button)
		elif row.valid:
			column.add_child(UIStyle.button("Load this save", func() -> void: _load(slot), "load/" + row.id))
		elif row.has("backup"):
			column.add_child(UIStyle.button("Recover valid backup", func() -> void:
				confirm("Recover backup", "The main save is unavailable. Recover the backup from " + Time.get_datetime_string_from_unix_time(int(row.backup_timestamp)).replace("T", " ") + " UTC? The damaged file is preserved.", func() -> void: _load(slot, true))
			, "backup/" + row.id))
	_focus_first(panels[mode])

func _continue() -> void:
	var chosen := SaveService.continue_slot()
	if not chosen.ok:
		report(chosen)
		return
	await _load(StringName(chosen.payload.slot_id))
	if not String(chosen.payload.notice).is_empty():
		show_feedback(chosen.payload.notice)

func _new_game(confirmed: bool = false) -> void:
	if _busy:
		return
	_busy = true
	var result := await game.start_new_game(confirmed)
	_busy = false
	if result.code == &"confirmation_required":
		confirm("Start a new game", String(result.message_key), func() -> void: _new_game(true))
	else:
		report(result)

func _load(slot: StringName, backup: bool = false) -> void:
	if _busy:
		return
	_busy = true
	var result := await game.load_slot(slot, backup)
	_busy = false
	report(result, "Recovered the backup." if backup else "Game loaded.")

func _dialogue() -> void:
	var view := GameSession.dialogue.view()
	if view.is_empty():
		game.modes.push_mode(&"gameplay")
		return
	var panel: VBoxContainer = panels[&"dialogue"]
	UIStyle.clear(panel)
	game.modal_host.set_heading(String(view.speaker_name))
	panel.add_child(UIStyle.label(String(view.text)))
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_FILL
	panel.add_child(scroll)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(choices)
	var row_height: float = 48 * float(SaveService.settings.text_scale)
	scroll.custom_minimum_size.y = row_height * min(3, view.choices.size()) + 10 * float(SaveService.settings.text_scale) * 2
	for choice: Dictionary in view.choices:
		var button := UIStyle.button(String(choice.text), func() -> void:
			handle_action(GameSession.dialogue.choose(StringName(view.node_id), StringName(choice.id)))
		, "dialogue/" + String(choice.id))
		button.custom_minimum_size.y = row_height
		choices.add_child(button)
	_focus_first(panel)

func _death() -> void:
	var column := _column(&"death")
	var pending: bool = GameSession.recovery.has_pending_recovery()
	column.add_child(UIStyle.label("Your progress and recovery fee are already committed. Retry arrival without another charge." if pending else "Return to your last rest point. Lose 10% of your crowns, rounded down, up to 12. Equipment, quests and evidence are kept."))
	column.add_child(UIStyle.button("Retry recovery" if pending else "Return to safety", func() -> void: report(GameSession.recovery.retry_recovery() if pending else GameSession.recovery.confirm_death()), "death/recover"))
	column.add_child(UIStyle.button("Main menu", func() -> void: confirm("Return to title", "Leave without completing recovery? Unsaved progress will be lost.", func() -> void: report(game.leave_to_title())), "death/title"))
	_focus_first(panels[&"death"])

func _show_writ() -> void:
	var reviewed := GameSession.quests.read_document(&"village_writ_table")
	if not reviewed.ok:
		report(reviewed)
		return
	_show_text("The Last Toll", String(reviewed.payload.text))
	var panel: VBoxContainer = panels[&"readable"]
	var column: VBoxContainer = panel.get_child(0).get_child(0)
	if GameSession.state.choices.ending != "none":
		var locked_name: String = {"charter": "The village charter was restored.", "warden": "The wardens were bound to an oath.", "free_road": "The toll authority was broken."}[GameSession.state.choices.ending]
		column.add_child(UIStyle.label(locked_name + " The resolution is settled."))
		column.add_child(UIStyle.button("Read the valley's epilogue", func() -> void: show_epilogue(true), "writ/replay"))
		_focus_first(panel)
		return
	for ending: String in ["charter", "warden", "free_road"]:
		var label: String = {"charter": "Restore the village charter", "warden": "Bind the wardens to an oath", "free_road": "Break the toll authority"}[ending]
		var consequences: String = {"charter": "Publish a public grain tally. Surviving checkpoint soldiers become neutral road keepers. Shop purchases cost 15% less.", "warden": "Set a fixed public levy. Surviving checkpoint soldiers become neutral wardens under Ada's oath. Shop purchases cost 5% less.", "free_road": "Checkpoint soldiers withdraw and the toll bar is removed. Shops keep their ordinary prices."}[ending]
		column.add_child(UIStyle.button(label, func() -> void:
			confirm("Confirm the road's future", label + ". " + consequences + " This choice is permanent.", func() -> void:
				var result := GameSession.quests.choose(&"ending", StringName(ending), UIStyle.action_id("ending"))
				report(result)
				if result.ok:
					if result.payload.get("replayed", false):
						_show_writ()
					else:
						_awaiting_ending = true
						_ending_wait()
			)
		, "ending/" + ending))
	_focus_first(panel)

func _ending_wait(failed: bool = false) -> void:
	var panel: VBoxContainer = panels[&"confirmation"]
	UIStyle.clear(panel)
	var column := UIStyle.scroll_content(panel)
	column.add_child(UIStyle.label("The ending is committed, but its save failed. Leaving the game can lose this choice. Retry the save or explicitly continue without saving." if failed else "Saving the valley's future before the epilogue…"))
	if failed:
		column.add_child(UIStyle.button("Retry save", func() -> void: report(SaveService.retry_autosave()), "ending/retry_save"))
		column.add_child(UIStyle.button("Continue without saving", func() -> void:
			var result := SaveService.continue_without_saving()
			report(result)
			if result.ok and result.payload.get("ending_ready", false):
				show_epilogue()
		, "ending/continue_unsaved"))
	game.modes.push_mode(&"confirmation")
	game.modal_host.set_heading("The Last Toll")
	game.modal_host.set_back_visible(false)
	game.modes.set_back_locked(true)
	_focus_first(panel)

func show_epilogue(replay: bool = false) -> void:
	if not replay and not SaveService.pending_autosave().ending_ready:
		show_feedback("The ending must be saved or explicitly continued without saving first.")
		return
	if GameSession.quests.epilogue_view().is_empty():
		return
	if replay:
		_epilogue_return = game.modes.snapshot_stack()
	else:
		_epilogue_return = [&"gameplay"]
	_epilogue_page = 0
	_awaiting_ending = false
	game.modes.set_back_locked(false)
	game.modes.push_mode(&"epilogue")
	_epilogue()

func _epilogue() -> void:
	var texts := GameSession.quests.epilogue_view()
	var column := _column(&"epilogue")
	column.add_child(UIStyle.label("%d / 3" % (_epilogue_page + 1), true))
	column.add_child(UIStyle.label(texts[_epilogue_page]))
	if _epilogue_page < 2:
		column.add_child(UIStyle.button("Continue", func() -> void: _epilogue_page += 1; _epilogue(), "epilogue/next"))
	else:
		column.add_child(UIStyle.button("Return to the valley", func() -> void: game.modes.push_mode(&"gameplay"), "epilogue/valley"))
		column.add_child(UIStyle.button("Main menu", func() -> void: report(game.leave_to_title()), "epilogue/title"))
		if _epilogue_return.size() > 1:
			var return_label := "Back to journal" if _epilogue_return.back() == &"journal" else "Back to the writ"
			column.add_child(UIStyle.button(return_label, func() -> void: game.modes.restore_stack(_epilogue_return), "epilogue/journal"))
	game.modal_host.set_back_visible(false)
	_focus_first(panels[&"epilogue"])

func _training() -> void:
	_show_text("The smith's straw dummy", "Practice on this straw target. It gives no money or quest progress and does not attack.\n\nLight attack: [" + InputBindings.label(&"attack_light") + "]. Heavy attack: [" + InputBindings.label(&"attack_heavy") + "]. Both spend stamina.\n\nAgainst an enemy, face the incoming strike and hold [" + InputBindings.label(&"block") + "] to block. Raise your shield just before contact to parry. Holding it does not repeat a parry.\n\nLeave this panel to practice.")

func _column(mode: StringName) -> VBoxContainer:
	var panel: VBoxContainer = panels[mode]
	UIStyle.clear(panel)
	return UIStyle.scroll_content(panel)

func _focus_first(panel: Control) -> void:
	for child: Node in panel.find_children("*", "Button", true, false):
		if child is Button and not child.disabled:
			UIStyle.focus_visible.call_deferred(child)
			return

func _mode_changed(mode: StringName) -> void:
	if _previous_mode == &"inventory" and mode != &"inventory":
		inventory.clear_context()
	if _previous_mode == &"shop" and mode != &"shop":
		shop.clear_context()
	if mode == &"settings":
		settings.refresh(_previous_mode == &"confirmation")
	if mode not in [&"settings", &"confirmation"]:
		settings.capturing = &""
	_previous_mode = mode
	refresh()
	if mode == &"gameplay" and GameSession.active:
		show_hint("movement", "Move with [" + InputBindings.label(&"move_forward") + "] [" + InputBindings.label(&"move_left") + "] [" + InputBindings.label(&"move_back") + "] [" + InputBindings.label(&"move_right") + "]. Look with the mouse. Journal [" + InputBindings.label(&"journal") + "]; map [" + InputBindings.label(&"map") + "].")

func _world_ready(_world: Node3D) -> void:
	inventory.clear_context()
	_mark_dirty()

func _mark_dirty() -> void:
	_dirty = true

func _settings_changed(current: Dictionary) -> void:
	theme = UIStyle.theme_for(float(current.text_scale))
	game.modal_host.theme = theme
	game.modal_host._heading.add_theme_font_size_override("font_size", roundi(28 * float(current.text_scale)))
	_mark_dirty()

func _travel_finished(_id: StringName, result: MireTypes.ActionResult) -> void:
	if not result.ok and GameSession.recovery.has_pending_recovery():
		game.modes.push_mode(&"death")
	report(result)

func _autosave_finished(_reason: StringName, result: MireTypes.ActionResult) -> void:
	if result.ok and result.payload.get("ending_ready", false) and _awaiting_ending:
		show_epilogue()
	elif result.payload.get("ending_save_failed", false):
		_ending_wait(true)
	elif not result.ok:
		report(result)

func _consumption_finished(result: MireTypes.ActionResult) -> void:
	report(result, "Item used.")

func _combat_feedback(outcome: StringName) -> void:
	if outcome == &"insufficient_stamina":
		show_feedback("Not enough stamina. Lower your guard and catch your breath.")
