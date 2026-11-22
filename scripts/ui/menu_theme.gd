extends RefCounted
## The menus' look: warm white panels and white cards on cream, charcoal text,
## and one bronze accent. Rounded corners and thin borders, no gradients or
## shadows. Every menu builds its controls through these helpers, so the style
## lives in one place.

const BG := Color("#EDE6D9")
const PANEL := Color("#FAF6EE")
const CARD := Color("#FFFFFF")
const CARD_HOVER := Color("#F6EFE2")
const BORDER := Color("#E0D6C4")
const TEXT := Color("#26231F")
const MUTED := Color("#6B645A")
## The accent: links such as "Start >", the border of whatever is pointed at.
const ACCENT := Color("#8C6A3A")
const ACCENT_HOVER := Color("#9E7B49")
const ACCENT_PRESSED := Color("#735629")
## The fill of the main button on a screen and of the selected tab or step, and
## the text that goes on it.
const PRIMARY := Color("#26231F")
const PRIMARY_HOVER := Color("#3B362F")
const PRIMARY_PRESSED := Color("#15130F")
const ON_PRIMARY := Color("#FBF7EF")
const LOCKED := Color("#D8CFBF")
const DONE := Color("#2F7D4F")

const RADIUS := 20
const BORDER_WIDTH := 2

const SIZE_TITLE := 72
const SIZE_HEADING := 48
const SIZE_BODY := 34
const SIZE_SMALL := 28

## Where finished menu images go. Until a file is there, a placeholder shows.
## The list of images is in docs/IMAGES_NEEDED.md.
const IMAGE_DIR := "res://ui/images/"


static func box(fill: Color, border := BORDER, radius := RADIUS, margin := 32) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(BORDER_WIDTH)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


## A screen's background panel.
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, BORDER, RADIUS + 8, 48))
	return p


static func label(text: String, size := SIZE_BODY, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A filled charcoal button for the main action on a screen.
static func primary_button(text: String) -> Button:
	return _button(text, PRIMARY, PRIMARY, PRIMARY_HOVER, PRIMARY_PRESSED, ON_PRIMARY)


## A white outlined button for every other action.
static func secondary_button(text: String) -> Button:
	return _button(text, CARD, BORDER, CARD_HOVER, CARD_HOVER, TEXT)


static func _button(text: String, fill: Color, border: Color, hover: Color, pressed: Color, font: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", SIZE_BODY)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, font)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_stylebox_override("normal", box(fill, border, RADIUS, 24))
	b.add_theme_stylebox_override("hover", box(hover, ACCENT if border == BORDER else border, RADIUS, 24))
	b.add_theme_stylebox_override("pressed", box(pressed, ACCENT, RADIUS, 24))
	b.add_theme_stylebox_override("disabled", box(CARD, BORDER, RADIUS, 24))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 88)
	return b


## A menu image by name (e.g. "mode_free_play"), sized `size` pixels. Shows
## res://ui/images/<name>.png when it exists, otherwise a flat placeholder
## with the image's name, so it's clear which image goes there.
static func image(name: String, size: Vector2) -> Control:
	var path := IMAGE_DIR + name + ".png"
	if ResourceLoader.exists(path):
		# A rounded panel that clips the picture to its shape, so every image
		# gets the menus' rounded corners, whatever its file looks like.
		var frame := PanelContainer.new()
		frame.name = "Image_" + name
		frame.custom_minimum_size = size
		frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		frame.add_theme_stylebox_override("panel", box(Color.WHITE, Color.WHITE, RADIUS - 6, 0))
		var t := TextureRect.new()
		t.texture = load(path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(t)
		return frame
	var p := PanelContainer.new()
	p.name = "Placeholder_" + name
	p.custom_minimum_size = size
	p.add_theme_stylebox_override("panel", box(CARD_HOVER, BORDER, RADIUS - 6, 12))
	# Small placeholders get smaller text, so the image's name fits.
	var l := label("image: " + name, SIZE_SMALL if size.x == 0 or size.x >= 400 else SIZE_SMALL - 10, MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## A small rounded tag, e.g. a topic or "Done".
static func tag(text: String, fill := CARD_HOVER, font := MUTED) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(fill, fill, 999, 10))
	var l := label(text, SIZE_SMALL - 4, font)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	return p


## A vertical scroll area with a slim flat scrollbar.
static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := s.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", box(BG, BG, 999, 6))
	bar.add_theme_stylebox_override("grabber", box(BORDER, BORDER, 999, 6))
	bar.add_theme_stylebox_override("grabber_highlight", box(MUTED, MUTED, 999, 6))
	bar.add_theme_stylebox_override("grabber_pressed", box(ACCENT, ACCENT, 999, 6))
	return s
