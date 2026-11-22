extends Node3D
## The menu room: where the game starts. One big 3D screen shows one page at a
## time (Home, Log in, the mode picker, Free Play, Story Mode); the mouse or the
## right controller points at it.
##
## Pages are built in code from menu_theme.gd's pieces, so they all share one
## look. Every button has a name (e.g. "PlayLocallyButton"), which the tests use.

const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const MenuScreen3D := preload("res://scripts/ui/menu_screen_3d.gd")
const MenuPointer := preload("res://scripts/input/menu_pointer.gd")
const StoryMap := preload("res://scripts/menus/story_map.gd")

## How many steps of a roadmap sit side by side.
const ROADMAP_COLUMNS := 4

## The page on screen ("home", "login", "modes", "coming_soon", ...).
var page := ""
## True when playing in a headset.
var in_vr := false
## The Story Mode roadmap (data/story.json).
var story = null

@onready var screen: MenuScreen3D = $MenuScreen
@onready var pointer: MenuPointer = $MenuPointer


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	in_vr = xr != null and xr.is_initialized()
	if in_vr:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		$XROrigin3D/XRCamera3D.make_current()
	else:
		$Camera3D.make_current()
		$XROrigin3D.visible = false
	pointer.use_vr(in_vr)
	var manager_for_story := _manager()
	story = StoryMap.load_from(manager_for_story.registry if manager_for_story else null)
	for problem in story.errors:
		push_error("story.json: " + problem)
	# Back from a mission started here: reopen the page it was started from.
	var manager := _manager()
	if manager and manager.return_page != "":
		var bits: PackedStringArray = manager.return_page.split(":", true, 1)
		manager.return_scene = ""
		manager.return_page = ""
		manager.return_label = ""
		show_page(bits[0], bits[1] if bits.size() > 1 else "")
	else:
		show_page("home")


## Replaces the screen's page. `arg` is page-specific (e.g. which mode).
func show_page(name: String, arg := "") -> void:
	for child in screen.ui_root.get_children():
		screen.ui_root.remove_child(child)
		child.queue_free()
	page = name
	var content: Control
	match name:
		"home":
			content = _home_page()
		"login":
			content = _login_page()
		"modes":
			content = _modes_page()
		"free_play":
			content = _free_play_page(arg if arg != "" else "computer")
		"story":
			content = _story_page()
		"roadmap":
			content = _roadmap_page(arg if arg != "" else "irl")
		_:
			content = _coming_soon_page(arg)
	var frame := MenuTheme.panel()
	frame.name = "Page_" + name
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(content)
	screen.ui_root.add_child(frame)


## Starts a mission from the menu. When it ends, the game comes back here and
## reopens `return_page` (e.g. "free_play:computer"); `label` names it on the
## mission's success panel.
func launch_task(full_id: String, return_page: String, label: String) -> void:
	var manager := _manager()
	if manager == null:
		return
	var mission: Dictionary = manager.registry.mission(full_id)
	if mission.is_empty():
		push_error("Menu: no mission %s" % full_id)
		return
	manager.return_scene = scene_file_path
	manager.return_page = return_page
	manager.return_label = label
	manager.open_scene(mission.scene)


## The button named `button_name` on the current page, or null.
func find_button(button_name: String) -> Button:
	return screen.ui_root.find_child(button_name, true, false) as Button


# ---------------------------------------------------------------- pages

func _home_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 56)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	column.add_child(MenuTheme.label("OCS VR", MenuTheme.SIZE_TITLE + 24))
	column.add_child(MenuTheme.label("Learn how computers and the cloud work, with your own hands.",
		MenuTheme.SIZE_BODY, MenuTheme.MUTED))
	column.add_child(_spacer(24))
	column.add_child(_button("LoginButton", MenuTheme.primary_button("Log in to your OCS account"),
		func(): show_page("login")))
	column.add_child(_button("PlayLocallyButton", MenuTheme.secondary_button("Skip: play locally"),
		func(): show_page("modes")))
	column.add_child(_spacer(16))
	column.add_child(MenuTheme.label(_how_to_point(), MenuTheme.SIZE_SMALL, MenuTheme.MUTED))
	row.add_child(column)
	var hero := MenuTheme.image("home_hero", Vector2(620, 620))
	hero.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hero)
	return row


func _login_page() -> Control:
	var column := _page_column("Log in", "home")
	column.add_child(MenuTheme.label(
		"Signing in to your OCS account will save your progress to the OCS server, so it follows you to any headset.",
		MenuTheme.SIZE_BODY))
	column.add_child(MenuTheme.label(
		"Sign-in arrives when the game is connected to the OCS backend. Until then, your progress is saved on this device.",
		MenuTheme.SIZE_BODY, MenuTheme.MUTED))
	column.add_child(_spacer(8))
	var play := _button("PlayLocallyButton", MenuTheme.primary_button("Play locally"), func(): show_page("modes"))
	play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	play.custom_minimum_size = Vector2(520, 88)
	column.add_child(play)
	return column


func _modes_page() -> Control:
	var column := _page_column("Choose how to play", "home")
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 32)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_child(_card("FreePlayCard", "mode_free_play", "Free Play",
		"Pick any Computer or Cloud task and start it.", [], func(): show_page("free_play", "computer")))
	cards.add_child(_card("StoryCard", "mode_story", "Story Mode",
		"Follow a roadmap: from plugging in a PC to building rigs, or into the cloud.", [],
		func(): show_page("story")))
	cards.add_child(_card("OpenWorldCard", "mode_open_world", "Open World",
		"Your own desk and room, every part and tool.", ["Coming soon"],
		func(): show_page("coming_soon", "Open World")))
	column.add_child(cards)
	return column


func _free_play_page(category: String) -> Control:
	var column := _page_column("Free Play", "modes")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 16)
	for tab in [["computer", "Computer"], ["cloud", "Cloud"]]:
		var look: Button = MenuTheme.primary_button(tab[1]) if tab[0] == category else MenuTheme.secondary_button(tab[1])
		var b := _button("Tab" + tab[1], look, func(): show_page("free_play", tab[0]))
		b.custom_minimum_size = Vector2(240, 80)
		tabs.add_child(b)
	column.add_child(tabs)
	var manager := _manager()
	var tasks: Array = manager.registry.missions_in(category) if manager else []
	if tasks.is_empty():
		var empty := MenuTheme.label("No %s tasks yet. The cloud world arrives in a later phase." % category.capitalize(),
			MenuTheme.SIZE_BODY, MenuTheme.MUTED)
		empty.name = "EmptyList"
		column.add_child(empty)
		return column
	var scroll := MenuTheme.scroll()
	scroll.name = "TaskList"
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	for task in tasks:
		list.add_child(_task_row(task, "free_play:" + category))
	scroll.add_child(list)
	column.add_child(scroll)
	return column


## One task in a list: image, title, description, tags, and Done/best score or
## Start. The card is a panel that grows with its text; a clear button on top
## of it ("Task_<id>") takes the click and draws the accent hover border.
func _task_row(task: Dictionary, return_page: String) -> Control:
	var card := PanelContainer.new()
	card.name = "TaskCard_" + task.full_id.replace(".", "_")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.CARD, MenuTheme.BORDER, MenuTheme.RADIUS, 20))
	var inside := HBoxContainer.new()
	inside.add_theme_constant_override("separation", 28)
	inside.add_child(MenuTheme.image("task_" + task.id, Vector2(230, 150)))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 8)
	text.add_child(MenuTheme.label(task.title.strip_edges(), MenuTheme.SIZE_BODY + 4))
	if task.description != "":
		text.add_child(MenuTheme.label(task.description, MenuTheme.SIZE_SMALL, MenuTheme.MUTED))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 10)
	for t in [task.topic, task.difficulty, "Practice" if task.practice else ""]:
		if t != "":
			tags.add_child(MenuTheme.tag(t))
	text.add_child(tags)
	inside.add_child(text)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 8)
	var saves := get_node_or_null("/root/SaveService")
	var progress: Dictionary = saves.task_progress(task.full_id) if saves else {}
	if not progress.is_empty():
		var done := MenuTheme.tag("Done", Color(MenuTheme.DONE, 0.14), MenuTheme.DONE)
		done.name = "DoneTag"
		done.size_flags_horizontal = Control.SIZE_SHRINK_END
		side.add_child(done)
		side.add_child(_nowrap(MenuTheme.label("Best %d" % progress.best_score, MenuTheme.SIZE_SMALL, MenuTheme.MUTED)))
	side.add_child(_nowrap(MenuTheme.label("Start  >", MenuTheme.SIZE_BODY, MenuTheme.ACCENT)))
	inside.add_child(side)
	_ignore_mouse(inside)
	card.add_child(inside)
	card.add_child(_click_layer("Task_" + task.full_id.replace(".", "_"),
		func(): launch_task(task.full_id, return_page, "Free Play")))
	return card


## A see-through button that covers a card: it takes the click and shows a
## border in the accent color on hover.
func _click_layer(button_name: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = button_name
	b.focus_mode = Control.FOCUS_NONE
	var clear := Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", MenuTheme.box(clear, MenuTheme.ACCENT))
	b.add_theme_stylebox_override("pressed", MenuTheme.box(clear, MenuTheme.ACCENT_PRESSED))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


func _story_page() -> Control:
	var column := _page_column("Story Mode", "modes")
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 32)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for id in ["irl", "cloud"]:
		var c: Dictionary = story.chapter(id)
		if c.is_empty():
			continue
		var p: Array = story.progress(id, _is_done)
		var tags := [] if p[1] > 0 else ["No tasks yet"]
		var card := _card("Chapter_" + id, "story_" + id, c.title, c.subtitle, tags,
			func(): show_page("roadmap", id), "%d of %d done" % [p[0], p[1]])
		cards.add_child(card)
	var both_done: bool = story.chapter_complete("irl", _is_done) and story.chapter_complete("cloud", _is_done)
	var bridge := _card("Chapter_bridge", "story_bridge", str(story.bridge.get("title", "Bridge")),
		str(story.bridge.get("subtitle", "")), [] if both_done else ["Locked"],
		func(): show_page("coming_soon", "Bridge"), "Open")
	bridge.disabled = not both_done
	cards.add_child(bridge)
	column.add_child(cards)
	return column


## A chapter's roadmap: each act and its tasks, in order, colored by state.
func _roadmap_page(chapter_id: String) -> Control:
	var c: Dictionary = story.chapter(chapter_id)
	var column := _page_column("Story: " + str(c.get("title", chapter_id)), "story")
	column.add_child(MenuTheme.label(str(c.get("subtitle", "")), MenuTheme.SIZE_SMALL, MenuTheme.MUTED))
	var states: Dictionary = story.states(chapter_id, _is_done)
	var scroll := MenuTheme.scroll()
	scroll.name = "Roadmap"
	var acts := VBoxContainer.new()
	acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_theme_constant_override("separation", 22)
	var number := 0
	for act in c.get("acts", []):
		acts.add_child(MenuTheme.label(act.title, MenuTheme.SIZE_BODY + 2))
		# A grid, so the steps share the screen's width evenly and a short last
		# row still lines up under the one above.
		var steps := GridContainer.new()
		steps.columns = ROADMAP_COLUMNS
		steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		steps.add_theme_constant_override("h_separation", 20)
		steps.add_theme_constant_override("v_separation", 20)
		for task in act.tasks:
			number += 1
			steps.add_child(_roadmap_node(chapter_id, task, states[task.id], number))
		acts.add_child(steps)
	scroll.add_child(acts)
	column.add_child(scroll)
	return column


## One step on the roadmap. Done and next steps can be played; locked and
## planned ones can't. Its state is in the "state" meta (for tests).
func _roadmap_node(chapter_id: String, task: Dictionary, state: String, number: int) -> Control:
	var fill := MenuTheme.CARD
	var border := MenuTheme.BORDER
	var text_color := MenuTheme.TEXT
	var tag_text := ""
	match state:
		StoryMap.DONE:
			border = MenuTheme.DONE
			tag_text = "Done"
		StoryMap.NEXT:
			fill = MenuTheme.PRIMARY
			border = MenuTheme.ACCENT
			text_color = MenuTheme.ON_PRIMARY
			tag_text = "Play"
		StoryMap.LOCKED:
			text_color = MenuTheme.MUTED
			tag_text = "Locked"
		_:
			fill = MenuTheme.PANEL
			text_color = MenuTheme.MUTED
			tag_text = "Planned"
	var node := PanelContainer.new()
	node.name = "Node_" + task.id.replace(".", "_")
	node.set_meta("state", state)
	node.custom_minimum_size = Vector2(262, 150)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_stylebox_override("panel", MenuTheme.box(fill, border, MenuTheme.RADIUS, 18))
	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_child(_nowrap(MenuTheme.label(str(number), MenuTheme.SIZE_SMALL, MenuTheme.ON_PRIMARY if state == StoryMap.NEXT else MenuTheme.MUTED)))
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(push)
	var tag_fill := Color(1, 1, 1, 0.16) if state == StoryMap.NEXT else (Color(MenuTheme.DONE, 0.14) if state == StoryMap.DONE else MenuTheme.CARD_HOVER)
	var tag_font := MenuTheme.ON_PRIMARY if state == StoryMap.NEXT else (MenuTheme.DONE if state == StoryMap.DONE else MenuTheme.MUTED)
	top.add_child(MenuTheme.tag(tag_text, tag_fill, tag_font))
	inside.add_child(top)
	inside.add_child(MenuTheme.label(task.title, MenuTheme.SIZE_SMALL, text_color))
	_ignore_mouse(inside)
	node.add_child(inside)
	if state == StoryMap.DONE or state == StoryMap.NEXT:
		node.add_child(_click_layer("Play_" + task.id.replace(".", "_"), func():
			var saves := get_node_or_null("/root/SaveService")
			if saves:
				saves.set_story_current(chapter_id, task.id)
			launch_task(task.mission, "roadmap:" + chapter_id, "Story Mode")))
	return node


func _is_done(task_id: String) -> bool:
	var saves := get_node_or_null("/root/SaveService")
	return saves != null and saves.is_task_done(task_id)


func _coming_soon_page(what: String) -> Control:
	var column := _page_column(what if what != "" else "Coming soon", "modes")
	column.add_child(MenuTheme.label("This part of the game is coming soon.", MenuTheme.SIZE_BODY, MenuTheme.MUTED))
	return column


# ---------------------------------------------------------------- pieces

## A page with a Back button (to `back_to`) and a heading.
func _page_column(heading: String, back_to: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	var back := _button("BackButton", MenuTheme.secondary_button("Back"), func(): show_page(back_to))
	back.custom_minimum_size = Vector2(180, 80)
	top.add_child(back)
	var title := MenuTheme.label(heading, MenuTheme.SIZE_HEADING)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(MenuTheme.tag("Playing locally"))
	column.add_child(top)
	return column


func _button(button_name: String, button: Button, on_press: Callable) -> Button:
	button.name = button_name
	button.pressed.connect(on_press)
	return button


## A big clickable card: image, title, description, then either an action
## ("Open >", in the accent color) or tags such as "Coming soon" along the bottom.
func _card(card_name: String, image_name: String, title: String, text: String, tags: Array, on_press: Callable, action := "Open") -> Button:
	var card := Button.new()
	card.name = card_name
	card.focus_mode = Control.FOCUS_NONE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.CARD))
	card.add_theme_stylebox_override("hover", MenuTheme.box(MenuTheme.CARD_HOVER, MenuTheme.ACCENT))
	card.add_theme_stylebox_override("pressed", MenuTheme.box(MenuTheme.CARD_HOVER, MenuTheme.ACCENT_PRESSED))
	card.add_theme_stylebox_override("disabled", MenuTheme.box(MenuTheme.PANEL))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var inside := VBoxContainer.new()
	inside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inside.offset_left = 24
	inside.offset_top = 24
	inside.offset_right = -24
	inside.offset_bottom = -24
	inside.add_theme_constant_override("separation", 18)
	var img := MenuTheme.image(image_name, Vector2(0, 340))
	inside.add_child(img)
	inside.add_child(MenuTheme.label(title, MenuTheme.SIZE_HEADING - 6))
	inside.add_child(MenuTheme.label(text, MenuTheme.SIZE_SMALL, MenuTheme.MUTED))
	var push_down := Control.new()
	push_down.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inside.add_child(push_down)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	if tags.is_empty():
		var go := MenuTheme.label(action + "  >", MenuTheme.SIZE_BODY, MenuTheme.ACCENT)
		go.autowrap_mode = TextServer.AUTOWRAP_OFF  # in a row, a wrapping label gets no width
		bottom.add_child(go)
	for t in tags:
		bottom.add_child(MenuTheme.tag(t))
	inside.add_child(bottom)
	_ignore_mouse(inside)
	card.add_child(inside)
	card.pressed.connect(on_press)
	return card


## Children of a card pass clicks through to the card.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


## A label that stays on one line (in a row, a wrapping label gets no width).
func _nowrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _manager() -> Node:
	return get_node_or_null("/root/TrainingManager")


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _how_to_point() -> String:
	if in_vr:
		return "Point with your right controller and pull the trigger. Push the thumbstick to scroll."
	return "Click to choose. Scroll with the mouse wheel."
