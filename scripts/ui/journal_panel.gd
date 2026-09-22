class_name JournalPanel
extends VBoxContainer

var ui: Node
var content: VBoxContainer
var map_view: NavigationMap
var map_caption: Label

func configure(owner_ui: Node, as_map: bool = false) -> void:
	ui = owner_ui
	if as_map:
		content = UIStyle.scroll_content(self)
		map_caption = UIStyle.label("")
		content.add_child(map_caption)
		map_view = NavigationMap.new()
		map_view.game = ui.game
		content.add_child(map_view)
		content.add_child(UIStyle.label("Circles mark discovered places. Blue marks your position; the cross marks your objective. North is up. Travel by the roads and paths.", true))
	else:
		content = UIStyle.scroll_content(self)

func refresh() -> void:
	var journal := GameSession.quests.journal_view()
	if map_view != null:
		var tracked: Dictionary = journal.tracked
		map_caption.text = "Explore the valley." if tracked.is_empty() else String(tracked.name) + ": " + String(tracked.objective.label) + "\n" + String(tracked.objective.location)
		map_view.queue_redraw()
		return
	var focused := UIStyle.focus_id(self)
	UIStyle.clear(content)
	content.add_child(UIStyle.label("Active quests", true))
	if journal.active.is_empty():
		content.add_child(UIStyle.label("No accepted quests. Speak to a giver to begin."))
	for quest: Dictionary in journal.active:
		content.add_child(UIStyle.label(quest.name + (" · Ready to return" if quest.turn_in_available else "")))
		for objective: Dictionary in quest.objectives:
			content.add_child(UIStyle.label(("✓ " if objective.completed else "□ ") + String(objective.label) + "  %d/%d" % [objective.progress, objective.count], objective.completed))
		content.add_child(UIStyle.label(String(quest.next_objective.get("location", "")), true))
		content.add_child(UIStyle.button("Track " + String(quest.name), func() -> void:
			ui.report(GameSession.quests.track(StringName(quest.quest_id)), "Quest tracked.")
		, "track/" + String(quest.quest_id)))
	content.add_child(UIStyle.label("Completed quests", true))
	if journal.completed.is_empty():
		content.add_child(UIStyle.label("Your completed promises will be recorded here.", true))
	for quest: Dictionary in journal.completed:
		content.add_child(UIStyle.label("✓ " + String(quest.name)))
	content.add_child(UIStyle.label("Documents and clues", true))
	for document: Dictionary in journal.documents:
		content.add_child(UIStyle.button(document.title, func() -> void: ui.show_document(StringName(document.document_id)), "document/" + String(document.document_id)))
	if GameSession.state.choices.ending != "none":
		content.add_child(UIStyle.button("Read the valley's epilogue", func() -> void: ui.show_epilogue(true), "journal/epilogue"))
	UIStyle.restore_focus(self, focused)
