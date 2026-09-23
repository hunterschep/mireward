class_name InventoryPanel
extends VBoxContainer

var ui: Node
var content: VBoxContainer
var shop_id: StringName = &""
var loot_id: StringName = &""
var loot_world: WeakRef
var _revision: int = 0

func configure(owner_ui: Node) -> void:
	ui = owner_ui
	content = UIStyle.scroll_content(self)

func clear_context() -> void:
	_revision += 1
	shop_id = &""
	loot_id = &""
	loot_world = null

func open_loot(entity_id: StringName) -> MireTypes.ActionResult:
	clear_context()
	var world: Node3D = ui.game.router.current_world
	if not is_instance_valid(world) or not world.entities.has(entity_id):
		return MireTypes.failure(&"unavailable", &"That container is no longer in this world.")
	var result := GameSession.world_state.read_loot(entity_id)
	if result.ok:
		loot_id = entity_id
		loot_world = weakref(world)
	return result

func refresh() -> void:
	_revision += 1
	var revision := _revision
	var focused := UIStyle.focus_id(self)
	UIStyle.clear(content)
	var view := GameSession.inventory.view()
	content.add_child(UIStyle.label("%d crowns   |   Pack %d / %d slots" % [GameSession.state.player.crowns, view.slots_used, view.slots_max]))
	if not loot_id.is_empty():
		_loot()
	if not shop_id.is_empty():
		_shop()
	content.add_child(UIStyle.label("Your equipment and supplies" if shop_id.is_empty() else "Sell from your pack", true))
	for stack: Dictionary in view.stacks:
		var item: MireTypes.ItemDef = ContentDB.items[StringName(stack.item_id)]
		var card := _item_row(item, int(stack.quantity))
		var actions: HBoxContainer = card.actions
		var stack_id := StringName(stack.stack_id)
		if not shop_id.is_empty():
			var price := GameSession.economy.sell_price(item.id)
			var sale := GameSession.inventory.sale_check(GameSession.state, stack_id, 1)
			var quantity := _quantity(actions, int(stack.quantity))
			var quantity_ref: WeakRef = weakref(quantity)
			var sell := UIStyle.button("Sell 1 · %d crowns" % int(price.payload.unit_price), func() -> void:
				if not _current(revision): return
				var amount := quantity_ref.get_ref() as SpinBox
				if amount == null: return
				ui.report(GameSession.economy.try_sell(shop_id, stack_id, int(amount.value), UIStyle.action_id("sell")))
				refresh()
			, "sell/" + String(stack_id))
			quantity.value_changed.connect(func(value: float) -> void: sell.text = "Sell %d · %d crowns" % [int(value), int(value) * int(price.payload.unit_price)])
			sell.disabled = not sale.ok
			sell.tooltip_text = String(sale.message_key)
			actions.add_child(sell)
			if not sale.ok:
				card.body.add_child(UIStyle.label(String(sale.message_key), true))
		elif item.category in InventoryService.EQUIPMENT:
			var equipped: bool = view.equipment.get(String(item.category), "") == String(stack_id)
			var button := UIStyle.button("Equipped" if equipped else "Equip", func() -> void:
				if not _current(revision): return
				ui.report(GameSession.inventory.try_equip(stack_id))
				refresh()
			, "equip/" + String(stack_id))
			button.disabled = equipped
			actions.add_child(button)
			if equipped and item.category != &"weapon":
				actions.add_child(UIStyle.button("Unequip", func() -> void:
					if not _current(revision): return
					ui.report(GameSession.inventory.try_unequip(item.category))
					refresh()
				, "unequip/" + String(item.category)))
		elif item.category == &"consumable":
			actions.add_child(UIStyle.button("Use", func() -> void:
				if not _current(revision): return
				var result := GameSession.inventory.try_consume(stack_id)
				ui.report(result)
				if result.ok:
					ui.game.modes.push_mode(&"gameplay")
			, "use/" + String(stack_id)))
	if shop_id.is_empty():
		content.add_child(UIStyle.label("Key items and evidence (separate from your pack)", true))
		if view.key_items.is_empty():
			content.add_child(UIStyle.label("No carried key items. Acquired documents remain in the journal.", true))
		for id: String in view.key_items:
			var item: MireTypes.ItemDef = ContentDB.items[StringName(id)]
			_item_row(item, int(view.key_items[id]))
		content.add_child(UIStyle.label("Unclaimed rewards", true))
		if view.pending_delivery.is_empty():
			content.add_child(UIStyle.label("All rewards received.", true))
		for id: String in view.pending_delivery:
			var delivery: Dictionary = view.pending_delivery[id]
			var item: MireTypes.ItemDef = ContentDB.items[StringName(delivery.item_id)]
			var card := _item_row(item, int(delivery.quantity))
			card.actions.add_child(UIStyle.button("Claim reward", func() -> void:
				if not _current(revision): return
				ui.report(GameSession.inventory.claim_pending(StringName(id)))
				refresh()
			, "claim/" + id))
	UIStyle.restore_focus(self, focused)

func _shop() -> void:
	var revision := _revision
	var offered := GameSession.economy.view(shop_id)
	if not offered.ok:
		content.add_child(UIStyle.label(String(offered.message_key)))
		return
	content.add_child(UIStyle.label("Buy from " + ("Oswin" if shop_id == &"oswin_pike" else "Tamsin"), true))
	for stock: Dictionary in offered.payload.items:
		var item: MireTypes.ItemDef = ContentDB.items[StringName(stock.item_id)]
		var card := _item_row(item, 1)
		card.body.add_child(UIStyle.label("Stock: " + ("unlimited" if stock.unlimited else str(stock.stock)), true))
		var owned := GameSession.inventory.find_stack(StringName(GameSession.state.equipment.get(String(item.category), "")))
		if not owned.is_empty():
			var equipped: MireTypes.ItemDef = ContentDB.items[StringName(owned.item_id)]
			card.body.add_child(UIStyle.label("Equipped: " + equipped.name_key + " · " + equipped.description_key, true))
		var quantity := _quantity(card.actions, 99 if stock.unlimited else maxi(1, int(stock.stock)))
		var quantity_ref: WeakRef = weakref(quantity)
		var buy := UIStyle.button("Buy 1 · %d crowns" % int(stock.unit_price), func() -> void:
			if not _current(revision): return
			var amount := quantity_ref.get_ref() as SpinBox
			if amount == null: return
			ui.report(GameSession.economy.try_buy(shop_id, item.id, int(amount.value), UIStyle.action_id("buy")))
			refresh()
		, "buy/" + String(item.id))
		quantity.value_changed.connect(func(value: float) -> void: buy.text = "Buy %d · %d crowns" % [int(value), int(value) * int(stock.unit_price)])
		buy.disabled = not stock.available
		card.actions.add_child(buy)

func _loot() -> void:
	var revision := _revision
	if not _source_available():
		content.add_child(UIStyle.label("That container is no longer nearby. Close the pack and inspect it again."))
		return
	var result := GameSession.world_state.read_loot(loot_id)
	if not result.ok:
		content.add_child(UIStyle.label(String(result.message_key)))
		return
	var view: Dictionary = result.payload
	content.add_child(UIStyle.label("Container contents", true))
	if view.empty:
		content.add_child(UIStyle.label("This container is empty.", true))
	for id: String in view.items:
		var card := _item_row(ContentDB.items[StringName(id)], int(view.items[id]))
		var quantity := _quantity(card.actions, int(view.items[id]))
		var quantity_ref: WeakRef = weakref(quantity)
		card.actions.add_child(UIStyle.button("Take selected", func() -> void:
			if not _current(revision): return
			var amount := quantity_ref.get_ref() as SpinBox
			if amount == null: return
			if _source_available():
				ui.report(GameSession.world_state.take_loot(loot_id, StringName(id), int(amount.value), UIStyle.action_id("loot")))
			else:
				ui.show_feedback("That container is no longer in this world.")
			refresh()
		, "take/" + id))
	if int(view.crowns) > 0:
		content.add_child(UIStyle.button("Take %d crowns" % int(view.crowns), func() -> void:
			if not _current(revision): return
			if _source_available():
				ui.report(GameSession.world_state.take_crowns(loot_id, UIStyle.action_id("crowns")))
			refresh()
		, "take/crowns"))

func _current(revision: int) -> bool:
	return revision == _revision and is_visible_in_tree() and ui.game.modes.mode in [&"inventory", &"shop"]

func _source_available() -> bool:
	var world: Node3D = ui.game.router.current_world
	return loot_world != null and is_instance_valid(loot_world.get_ref()) and world == loot_world.get_ref() and world.entities.has(loot_id)

func _item_row(item: MireTypes.ItemDef, quantity: int) -> Dictionary:
	var panel := PanelContainer.new()
	content.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load(item.icon_path)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	body.add_child(UIStyle.label(item.name_key + (" ×%d" % quantity if quantity != 1 else "") + " · " + String(item.category).capitalize()))
	body.add_child(UIStyle.label(item.description_key, true))
	var actions := HBoxContainer.new()
	body.add_child(actions)
	return {"body": body, "actions": actions}

func _quantity(parent: Node, maximum: int) -> SpinBox:
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = maximum
	amount.value = 1
	amount.custom_minimum_size = Vector2(135, 44)
	parent.add_child(amount)
	return amount
