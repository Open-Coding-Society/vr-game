extends RefCounted
## The menus' look: flat dark panels, white text, one OCS blue accent. Rounded
## corners and thin borders, no gradients or shadows. Every menu builds its
## controls through these helpers, so the style lives in one place.

const BG := Color("#0E1116")
const PANEL := Color("#161B22")
const CARD := Color("#1C2330")
const CARD_HOVER := Color("#232C3B")
const BORDER := Color("#2A313C")
const TEXT := Color("#F0F3F6")
const MUTED := Color("#9AA4B2")
const ACCENT := Color("#2F81F7")
const ACCENT_HOVER := Color("#4493F8")
const ACCENT_PRESSED := Color("#1F6FEB")
const LOCKED := Color("#3A414C")
const DONE := Color("#3FB950")

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


## A filled blue button for the main action on a screen.
static func primary_button(text: String) -> Button:
	return _button(text, ACCENT, ACCENT, ACCENT_HOVER, ACCENT_PRESSED, TEXT)


## A dark outlined button for every other action.
static func secondary_button(text: String) -> Button:
	return _button(text, CARD, BORDER, CARD_HOVER, CARD, TEXT)


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
		var t := TextureRect.new()
		t.texture = load(path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.custom_minimum_size = size
		t.name = "Image_" + name
		return t
	var p := PanelContainer.new()
	p.name = "Placeholder_" + name
	p.custom_minimum_size = size
	p.add_theme_stylebox_override("panel", box(Color("#202733"), BORDER, RADIUS - 6, 12))
	var l := label("image: " + name, SIZE_SMALL, MUTED)
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
