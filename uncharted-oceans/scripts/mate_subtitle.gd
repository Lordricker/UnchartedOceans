class_name MateSubtitle
extends CanvasLayer
## The mate's subtitles: one line at the bottom of the screen, in the Ferrum face, with the speaker's name over it.
## Lines queue and fade in and out, and stay up long enough to read (about 2.5 s plus 0.045 s a letter).
##
## say(id, text) is the only call. If res://assets/audio/voice/silas/<id>.ogg exists it plays with the line and the line
## stays up as long as the clip (voice comes later; nothing else changes). `line_started(id)` and `line_finished(id)`
## fire either way, so a script can wait on the line.

signal line_started(id: String)
signal line_finished(id: String)
signal queue_empty

const FONT := "res://assets/fonts/Ferrum-ExtraCondensed.otf"
const VOICE_DIR := "res://assets/audio/voice/silas/"

@export var speaker := "Capt. Cobb"
@export var font_size := 26
@export var bottom_margin := 150.0
@export var fade_s := 0.35
@export var min_gap_s := 0.45

var _label: Label
var _name_label: Label
var _box: Control
var _queue: Array = []
var _busy := false
var _voice: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = Control.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.modulate.a = 0.0
	add_child(_box)
	var fnt := load(FONT) as Font
	_name_label = Label.new()
	_label = Label.new()
	for l in [_name_label, _label]:
		var lab := l as Label
		lab.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lab.add_theme_constant_override("outline_size", 6)
		if fnt != null:
			lab.add_theme_font_override("font", fnt)
		_box.add_child(lab)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.84))
	_name_label.add_theme_font_size_override("font_size", int(font_size * 0.7))
	_name_label.add_theme_color_override("font_color", Color(0.86, 0.7, 0.36))
	_name_label.text = speaker.to_upper()
	# 80% of the width, centred, above the helm's hotkey line
	for l in [_name_label, _label]:
		var lab := l as Label
		lab.anchor_left = 0.1
		lab.anchor_right = 0.9
		lab.offset_left = 0.0
		lab.offset_right = 0.0
		lab.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_bottom = -bottom_margin
	_label.offset_top = -bottom_margin - font_size * 3.2
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_name_label.offset_bottom = -bottom_margin - font_size * 3.2
	_name_label.offset_top = -bottom_margin - font_size * 3.2 - font_size
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"Master"
	add_child(_voice)


## Queue a line.
func say(id: String, text: String) -> void:
	_queue.append({"id": id, "text": text})
	if not _busy:
		_next()


## Drop everything waiting (the line on screen finishes).
func clear_queue() -> void:
	_queue.clear()


func is_idle() -> bool:
	return not _busy and _queue.is_empty()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		queue_empty.emit()
		return
	_busy = true
	var q: Dictionary = _queue.pop_front()
	var id := String(q["id"])
	var text := String(q["text"])
	_label.text = text
	var hold := 2.5 + 0.045 * text.length()
	var clip := VOICE_DIR + id + ".ogg"
	if ResourceLoader.exists(clip):
		var st := load(clip) as AudioStream
		if st != null:
			_voice.stream = st
			_voice.play()
			hold = maxf(hold, st.get_length() + 0.3)
	line_started.emit(id)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_box, "modulate:a", 1.0, fade_s)
	_tween.tween_interval(hold)
	if _queue.is_empty():
		_tween.tween_property(_box, "modulate:a", 0.0, fade_s)
	_tween.tween_callback(func() -> void:
		line_finished.emit(id)
		if _queue.is_empty():
			_busy = false
			queue_empty.emit()
		else:
			var t2 := create_tween()
			t2.tween_interval(min_gap_s)
			t2.tween_callback(_next))
