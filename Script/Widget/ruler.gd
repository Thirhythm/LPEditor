extends Control
class_name EditorRuler

# Ruler 组件：编辑器顶部的轨道概览，包含波形、音符缩略图、播放头和时间指示器
# 播放头固定在视口 PLAYHEAD_ANCHOR_RATIO 位置处

const RULER_HEIGHT: float = 100.0
const THUMBNAIL_HEIGHT: float = 60.0
const TIME_INDICATOR_HEIGHT: float = 40.0
const PLAYHEAD_ANCHOR_RATIO: float = 0.15
const NUM_TRACKS: int = 4
const SMOOTH_FACTOR: float = 0.18
const TRACK_COLORS: Array[Color] = [
	Color(0.25, 0.40, 0.70),
	Color(0.70, 0.45, 0.20),
	Color(0.25, 0.65, 0.40),
	Color(0.70, 0.25, 0.45),
]

var playhead_time: int = 0
var notes: Array[Dictionary] = []
var _smooth_target: int = 0
var _smooth_ready: bool = false
var _smooth_prev_scroll: int = 0

func _ready() -> void:
	_smooth_target = EditorChartState.scroll_time
	_smooth_prev_scroll = EditorChartState.scroll_time
	_smooth_ready = true
	queue_redraw()
	set_process_input(true)
	set_process(true)

func _process(delta: float) -> void:
	if not _smooth_ready:
		return

	if EditorChartState.scroll_time != _smooth_prev_scroll:
		_smooth_target = EditorChartState.scroll_time
		_smooth_prev_scroll = EditorChartState.scroll_time

	var diff := _smooth_target - EditorChartState.scroll_time
	if absi(diff) <= 1:
		if diff != 0:
			EditorChartState.scroll_time = _smooth_target
			_smooth_prev_scroll = EditorChartState.scroll_time
			queue_redraw()
		return

	EditorChartState.scroll_time += int(float(diff) * SMOOTH_FACTOR * 60.0 * delta + signf(float(diff)))
	EditorChartState.clamp_scroll()
	_smooth_prev_scroll = EditorChartState.scroll_time
	queue_redraw()

# 将时间转换为 ruler 上的 x 坐标（内建左侧边距，使时间 0 始终位于锚点处）
func time_to_x(time_ms: int) -> float:
	return size.x * PLAYHEAD_ANCHOR_RATIO + (time_ms - EditorChartState.scroll_time) * EditorChartState.px_per_ms

# 将 ruler 上的 x 坐标转换为时间
func x_to_time(x: float) -> int:
	return EditorChartState.scroll_time + int((x - size.x * PLAYHEAD_ANCHOR_RATIO) / EditorChartState.px_per_ms)

func _draw() -> void:
	var w: float = size.x
	var h: float = RULER_HEIGHT

	draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.12, 0.14), true)
	_draw_waveform(w)
	_draw_track_thumbnail(w)
	_draw_playhead(w, h)
	_draw_time_indicator(w, h)
	draw_line(Vector2(0, h), Vector2(w, h), Color(0.3, 0.3, 0.3), 1.0)

# 绘制音频波形：每像素列最大峰值聚合，避免每毫秒一个顶点的性能浪费
func _draw_waveform(w: float) -> void:
	var samples := EditorChartState.waveform_samples
	if samples.is_empty():
		return

	var wave_area_top: float = 4.0
	var wave_h := THUMBNAIL_HEIGHT - 4.0
	var mid_y := wave_area_top + wave_h / 2.0
	var half_h := wave_h / 2.0 - 2.0

	var pad := w * PLAYHEAD_ANCHOR_RATIO
	var view_start := EditorChartState.scroll_time - int(pad / EditorChartState.px_per_ms)
	var view_end := EditorChartState.scroll_time + int((w - pad) / EditorChartState.px_per_ms)

	var s0 := clampi(view_start, 0, samples.size() - 1)
	var s1 := clampi(view_end, 0, samples.size() - 1)
	if s1 <= s0:
		return

	var px_per_ms := EditorChartState.px_per_ms
	var scroll_time := EditorChartState.scroll_time
	var ms_per_px := maxi(1, ceili(1.0 / px_per_ms))
	var pts_upper := PackedVector2Array()
	var pts_lower := PackedVector2Array()

	var t := s0
	while t <= s1:
		var x := pad + (t - scroll_time) * px_per_ms
		var chunk_end := mini(t + ms_per_px, s1 + 1)
		var peak: float = 0.0
		for i in range(t, chunk_end):
			peak = maxf(peak, samples[i])

		var amp := peak * half_h
		pts_upper.append(Vector2(x, mid_y - amp))
		pts_lower.append(Vector2(x, mid_y + amp))
		t = chunk_end

	var polygon := PackedVector2Array()
	polygon.append_array(pts_upper)
	for i in range(pts_lower.size() - 1, -1, -1):
		polygon.append(pts_lower[i])

	draw_colored_polygon(polygon, Color(0.25, 0.55, 0.85, 0.28))
	draw_polyline(pts_upper, Color(0.35, 0.65, 0.95, 0.50), 1.0)
	draw_line(Vector2(pad + (s0 - scroll_time) * px_per_ms, mid_y),
		Vector2(pad + (s1 - scroll_time) * px_per_ms, mid_y),
		Color(0.25, 0.55, 0.85, 0.20), 1.0)

# 绘制四条轨道的音符缩略图
func _draw_track_thumbnail(w: float) -> void:
	var track_area_top: float = 4.0
	var track_h: float = THUMBNAIL_HEIGHT / NUM_TRACKS
	var font := get_theme_default_font()

	for i in range(NUM_TRACKS):
		var col := i + 1
		var y0: float = track_area_top + i * track_h
		draw_rect(Rect2(0, y0, w, track_h),
			TRACK_COLORS[i] * Color(0.3, 0.3, 0.3, 0.3), true)
		draw_rect(Rect2(0, y0, w, track_h), TRACK_COLORS[i], false, 1.0)

		var label := str(col)
		draw_string(font, Vector2(3, y0 + 1), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TRACK_COLORS[i])

	if not notes.is_empty():
		var pad := w * PLAYHEAD_ANCHOR_RATIO
		var view_start := EditorChartState.scroll_time - int(pad / EditorChartState.px_per_ms)
		var view_end := EditorChartState.scroll_time + int((w - pad) / EditorChartState.px_per_ms)

		for note in notes:
			var t := note.get("time", 0) as int
			if t < view_start or t > view_end:
				continue
			var col := note.get("column", 1) as int - 1
			if col < 0 or col >= NUM_TRACKS:
				continue

			var nx := time_to_x(t)
			if nx < 0 or nx > w:
				continue

			var note_type := note.get("type", "") as String
			var note_color := _get_note_color(note_type)
			var y0: float = track_area_top + col * track_h
			var mid_y: float = y0 + track_h / 2.0

			if note_type == "hold" and note.has("duration"):
				var dur := note.get("duration", 0) as int
				var end_x := time_to_x(t + dur)
				var bar_y := mid_y - 2.0
				draw_rect(Rect2(nx, bar_y, maxf(end_x - nx, 2.0), 4.0), note_color, true)
			else:
				draw_circle(Vector2(nx, mid_y), 3.0, note_color)

func _get_note_color(type: String) -> Color:
	match type:
		"tap":     return Color(0.3, 0.6, 1.0)
		"drag":    return Color(1.0, 0.85, 0.2)
		"release": return Color(1.0, 0.3, 0.3)
		"hold":    return Color(0.3, 1.0, 0.5)
		"heart":   return Color(1.0, 0.3, 1.0)
		_:         return Color(0.7, 0.7, 0.7)

# 绘制播放头竖线，固定在锚点位置不随滚动移动
func _draw_playhead(w: float, h: float) -> void:
	var x := w * PLAYHEAD_ANCHOR_RATIO
	draw_line(Vector2(x, 0), Vector2(x, h), Color(0.3, 0.7, 1.0), 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 5, 0), Vector2(x + 5, 0), Vector2(x, 6)
	]), Color(0.3, 0.7, 1.0))

# 绘制底部的时间显示区域
func _draw_time_indicator(w: float, h: float) -> void:
	var indicator_y := THUMBNAIL_HEIGHT + 10.0
	var font := get_theme_default_font()

	draw_line(Vector2(0, indicator_y - 2), Vector2(w, indicator_y - 2),
		Color(0.25, 0.25, 0.25), 1.0)

	var cur_time := EditorChartState.scroll_time
	var total_sec := cur_time / 1000
	var time_label := "%d:%02d.%03d" % [total_sec / 60, total_sec % 60, cur_time % 1000]

	var label_size := font.get_string_size(time_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(font, Vector2((w - label_size.x) / 2.0, indicator_y), time_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.85, 0.95))

	var ms_label := "%d ms" % cur_time
	var ms_size := font.get_string_size(ms_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	draw_string(font, Vector2((w - ms_size.x) / 2.0, indicator_y + 18), ms_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.6))

# 滚轮缩放与滚动
func _input(event: InputEvent) -> void:
	if not get_global_rect().has_point(get_global_mouse_position()):
		return

	if event is InputEventMouseButton and event.pressed:
		if not event.ctrl_pressed and not event.meta_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_smooth_target -= int(200 / EditorChartState.px_per_ms)
				playhead_time = _smooth_target
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_smooth_target += int(200 / EditorChartState.px_per_ms)
				playhead_time = _smooth_target
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton:
		if event.ctrl_pressed or event.meta_pressed:
			var local_event := make_input_local(event) as InputEventMouseButton
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(local_event.position.x, 1.2)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(local_event.position.x, 1.0 / 1.2)
				get_viewport().set_input_as_handled()

# 以鼠标位置为锚点缩放
func _zoom_at(anchor_x: float, factor: float) -> void:
	var anchor_time := x_to_time(anchor_x)
	EditorChartState.px_per_ms = clampf(EditorChartState.px_per_ms * factor, 0.02, 5.0)
	_smooth_target = anchor_time - int((anchor_x - size.x * PLAYHEAD_ANCHOR_RATIO) / EditorChartState.px_per_ms)
	playhead_time = _smooth_target
	queue_redraw()

# 点击左键设置播放头目标时间，由 _process 平滑滚动至目标
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		playhead_time = x_to_time(event.position.x)
		_smooth_target = playhead_time
		EditorChartState.clamp_scroll()
		emit_signal("playhead_moved", playhead_time)

signal playhead_moved(time_ms: int)

func set_notes(data: Array[Dictionary]) -> void:
	notes = data
	queue_redraw()

# 滚动到指定时间位置
func scroll_to(time_ms: int) -> void:
	_smooth_target = clampi(time_ms, 0, EditorChartState.get_max_scroll_time())
	playhead_time = _smooth_target

# 更新播放头时间
func update_playhead(time_ms: int) -> void:
	playhead_time = time_ms
	queue_redraw()
