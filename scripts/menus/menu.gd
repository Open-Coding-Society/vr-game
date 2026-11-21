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

## The page on screen ("home", "login", "modes", "coming_soon", ...).
var page := ""
## True when playing in a headset.
var in_vr := false

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
		_:
			content = _coming_soon_page(arg)
	var frame := MenuTheme.panel()
	frame.name = "Page_" + name
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(content)
	screen.ui_root.add_child(frame)


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
		"Pick any Computer or Cloud task and start it.", [], func(): show_page("coming_soon", "Free Play")))
	cards.add_child(_card("StoryCard", "mode_story", "Story Mode",
		"Follow a roadmap: from plugging in a PC to building rigs, or into the cloud.", [],
		func(): show_page("coming_soon", "Story Mode")))
	cards.add_child(_card("OpenWorldCard", "mode_open_world", "Open World",
		"Your own desk and room, every part and tool.", ["Coming soon"],
		func(): show_page("coming_soon", "Open World")))
	column.add_child(cards)
	return column


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
## ("Open >", in blue) or tags such as "Coming soon" along the bottom.
func _card(card_name: String, image_name: String, title: String, text: String, tags: Array, on_press: Callable, action := "Open") -> Button:
	var card := Button.new()
	card.name = card_name
	card.focus_mode = Control.FOCUS_NONE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.CARD))
	card.add_theme_stylebox_override("hover", MenuTheme.box(MenuTheme.CARD_HOVER, MenuTheme.ACCENT))
	card.add_theme_stylebox_override("pressed", MenuTheme.box(MenuTheme.CARD_HOVER, MenuTheme.ACCENT_PRESSED))
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


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _how_to_point() -> String:
	if in_vr:
		return "Point with your right controller and pull the trigger. Push the thumbstick to scroll."
	return "Click to choose. Scroll with the mouse wheel."
