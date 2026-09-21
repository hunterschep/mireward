class_name EconomyService
extends RefCounted

const BUY_MULTIPLIERS := {"none": 1.0, "charter": 0.85, "warden": 0.95, "free_road": 1.0}
var session: Node
var db: Node

func _init(owner: Node) -> void:
	session = owner
	db = owner.get_node("/root/ContentDB")

func buy_price(item_id: StringName, ending: StringName = &"") -> MireTypes.ActionResult:
	var definition: MireTypes.ItemDef = db.items.get(item_id)
	if definition == null:
		return MireTypes.failure(&"unknown_item", &"That item does not exist.")
	if definition.category in InventoryService.KEYS:
		return MireTypes.failure(&"protected_item", &"Quest items are not for sale.")
	var choice: String = String(ending) if not ending.is_empty() else String(session.state.choices.ending)
	if not BUY_MULTIPLIERS.has(choice):
		return MireTypes.failure(&"invalid_ending", &"The shop price modifier is invalid.")
	return MireTypes.success({"item_id": String(item_id), "unit_price": ceili(definition.base_price * float(BUY_MULTIPLIERS[choice]))})

func sell_price(item_id: StringName) -> MireTypes.ActionResult:
	var definition: MireTypes.ItemDef = db.items.get(item_id)
	if definition == null:
		return MireTypes.failure(&"unknown_item", &"That item does not exist.")
	if definition.category in InventoryService.KEYS:
		return MireTypes.failure(&"protected_item", &"Quest items cannot be sold.")
	return MireTypes.success({"item_id": String(item_id), "unit_price": floori(definition.base_price * 0.35)})

func try_buy(shop_id: StringName, item_id: StringName, quantity: int, transaction_id: StringName) -> MireTypes.ActionResult:
	return session.transactions.run(transaction_id, func(candidate: Dictionary) -> MireTypes.ActionResult:
		var valid := _can_trade(shop_id)
		if not valid.ok:
			return valid
		var shop: String = String(shop_id)
		var item: String = String(item_id)
		if quantity <= 0:
			return MireTypes.failure(&"invalid_quantity", &"Choose a positive purchase quantity.")
		if not db.shops[shop].has(item):
			return MireTypes.failure(&"not_sold_here", &"This merchant does not sell that item.")
		if not candidate.shop_stock.has(shop) or not candidate.shop_stock[shop].has(item):
			return MireTypes.failure(&"invalid_stock", &"The merchant's stock record is missing.")
		var stock: int = int(candidate.shop_stock[shop][item])
		if stock >= 0 and quantity > stock:
			return MireTypes.failure(&"out_of_stock", &"That quantity is not in stock.")
		var capacity: MireTypes.ActionResult = session.inventory.preview_add(item_id, quantity, candidate)
		if not capacity.ok:
			return capacity
		if int(capacity.payload.fits) != quantity:
			return MireTypes.failure(&"capacity", &"Make room before buying this quantity.")
		var price := buy_price(item_id, StringName(candidate.choices.ending))
		if not price.ok:
			return price
		var total: int = int(price.payload.unit_price) * quantity
		if int(candidate.player.crowns) < total:
			return MireTypes.failure(&"insufficient_crowns", &"You do not have enough crowns.")
		var added: MireTypes.ActionResult = session.inventory.stage_add(candidate, item_id, quantity)
		if not added.ok:
			return added
		candidate.player.crowns = int(candidate.player.crowns) - total
		if stock >= 0:
			candidate.shop_stock[shop][item] = stock - quantity
		added.payload.merge({"shop_id": shop, "quantity": quantity, "unit_price": int(price.payload.unit_price), "total_price": total})
		return added.event(&"currency_changed")
	)

func try_sell(shop_id: StringName, stack_id: StringName, quantity: int, transaction_id: StringName) -> MireTypes.ActionResult:
	return session.transactions.run(transaction_id, func(candidate: Dictionary) -> MireTypes.ActionResult:
		var valid := _can_trade(shop_id)
		if not valid.ok:
			return valid
		var sale: MireTypes.ActionResult = session.inventory.sale_check(candidate, stack_id, quantity)
		if not sale.ok:
			return sale
		var item_id := StringName(sale.payload.item_id)
		var price := sell_price(item_id)
		if not price.ok:
			return price
		var removed: MireTypes.ActionResult = session.inventory.stage_remove(candidate, stack_id, quantity)
		if not removed.ok:
			return removed
		var total: int = int(price.payload.unit_price) * quantity
		candidate.player.crowns = int(candidate.player.crowns) + total
		removed.payload.merge({"shop_id": String(shop_id), "stack_id": String(stack_id), "unit_price": int(price.payload.unit_price), "total_price": total})
		return removed.event(&"currency_changed")
	)

func view(shop_id: StringName) -> MireTypes.ActionResult:
	var shop: String = String(shop_id)
	if not db.shops.has(shop):
		return MireTypes.failure(&"unknown_shop", &"That merchant does not exist.")
	var entries: Array[Dictionary] = []
	for item: String in db.shops[shop]:
		if not session.state.shop_stock.has(shop) or not session.state.shop_stock[shop].has(item):
			return MireTypes.failure(&"invalid_stock", &"The merchant's stock record is missing.")
		var quote := buy_price(StringName(item))
		if not quote.ok:
			return quote
		var stock: int = int(session.state.shop_stock[shop][item])
		entries.append({"item_id": item, "unit_price": int(quote.payload.unit_price), "stock": stock, "unlimited": stock == -1, "available": stock != 0})
	return MireTypes.success({"shop_id": shop, "items": entries, "crowns": int(session.state.player.crowns)})

func _can_trade(shop_id: StringName) -> MireTypes.ActionResult:
	if not db.shops.has(String(shop_id)):
		return MireTypes.failure(&"unknown_shop", &"That merchant does not exist.")
	if not session.active or float(session.state.player.health) <= 0:
		return MireTypes.failure(&"unavailable", &"Trading is not available right now.")
	if session.action_locked or session.travelling:
		return MireTypes.failure(&"action_locked", &"Finish the current action before trading.")
	return MireTypes.success()
