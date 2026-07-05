extends VBoxContainer
class_name EditorVisual

# Visual 组件：编辑器中央的轨道编辑区，绘制音符、节拍线、播放判定线
# 支持音符选择、放置、删除，以及滚轮滚动/缩放

const NUM_TRACKS: int = 4
const TRACK_COLORS: Array[Color] = [
	Color(0.25, 0.40, 0.70),
	Color(0.70, 0.45, 0.20),
	Color(0.25, 0.65, 0.40),
	Color(0.70, 0.25, 0.45),
]
const MIN_NOTE_HEIGHT: float = 6.0
const MIN_NOTE_WIDTH: float = 8.0
const JUDGE_LINE_RATIO: float = 0.85
const SCROLL_SMOOTH: float = 0.18

var playhead_time: int = 0
var selected_index: int = -1
var placement_type: String = ""
var _target_scroll_time: int = 0
var _scroll_initialized: bool = false
var _prev_scroll_time: int = 0

var _drag_note_index: int = -1
var _drag_original_time: int = 0
var _drag_original_column: int = 0

func _ready() -> void:
	_set_child_mouse_filter(MOUSE_FILTER_IGNORE)
	_make_track_panels_transparent()
	_target_scroll_time = EditorChartState.scroll_time
	_scroll_initialized = true
	queue_redraw()
	set_process_input(true)
	set_process(true)

func _make_track_panels_transparent() -> void:
	for child in get_children():
		if child is Control:
			_make_transparent_recursive(child as Control)

func _make_transparent_recursive(node: Control) -> void:
	if node is Panel:
		var empty_style := StyleBoxEmpty.new()
		node.add_theme_stylebox_override("panel", empty_style)
	for child in node.get_children():
		if child is Control:
			_make_transparent_recursive(child as Control)

func _set_child_mouse_filter(filter: int) -> void:
	for child in get_children():
		if child is Control:
			child.mouse_filter = filter
			_set_child_recursive(child as Control, filter)

func _set_child_recursive(node: Control, filter: int) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = filter
			_set_child_recursive(child as Control, filter)

# 平滑滚动插值，使滚动动画自然
func _process(delta: float) -> void:
	if not _scroll_initialized:
		return

	if EditorChartState.scroll_time != _prev_scroll_time:
		_target_scroll_time = EditorChartState.scroll_time

	var diff := _target_scroll_time - EditorChartState.scroll_time
	if absi(diff) <= 1:
		EditorChartState.scroll_time = _target_scroll_time
	else:
		EditorChartState.scroll_time += int(float(diff) * SCROLL_SMOOTH * 60.0 * delta + signf(float(diff)))

	var changed := EditorChartState.scroll_time != _prev_scroll_time
	_prev_scroll_time = EditorChartState.scroll_time

	if changed:
		emit_signal("scroll_changed")
		queue_redraw()

# 判定线 Y 坐标（轨道的底部对齐线）
func _judge_line_y() -> float:
	return size.y * JUDGE_LINE_RATIO

# 将时间转换为 visual 上的 Y 坐标（从下往上增长：越大时间越早）
func time_to_y(time_ms: float) -> float:
	return _judge_line_y() - (time_ms - EditorChartState.scroll_time) * EditorChartState.px_per_ms

# 将 visual 上的 Y 坐标转换为时间
func y_to_time(y: float) -> int:
	return EditorChartState.scroll_time + int((_judge_line_y() - y) / EditorChartState.px_per_ms)

# 获取轨道的 X 范围
func track_to_x_range(col: int) -> Dictionary:
	var track_w: float = size.x / float(NUM_TRACKS)
	var x0: float = (col - 1) * track_w
	return {"left": x0, "right": x0 + track_w, "mid": x0 + track_w / 2.0}

# 将 X 坐标转换为轨道编号
func x_to_track(x: float) -> int:
	var track_w: float = size.x / float(NUM_TRACKS)
	return clampi(int(x / track_w) + 1, 1, NUM_TRACKS)

# 获取当前视口可见的时间范围
func _get_visible_time_range() -> Dictionary:
	var px := maxf(EditorChartState.px_per_ms, 0.001)
	return {
		"start": EditorChartState.scroll_time - int((size.y - _judge_line_y()) / px),
		"end": EditorChartState.scroll_time + int(_judge_line_y() / px)
	}

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _drag_note_index >= 0:
			_end_drag()
			get_viewport().set_input_as_handled()
			return

	if not get_global_rect().has_point(get_global_mouse_position()):
		return

	if event is InputEventMouseButton and event.pressed:
		if not event.ctrl_pressed and not event.meta_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_scroll_time -= int(200 / maxf(EditorChartState.px_per_ms, 0.01))
				_target_scroll_time = clampi(_target_scroll_time, 0, EditorChartState.get_max_scroll_time())
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_scroll_time += int(200 / maxf(EditorChartState.px_per_ms, 0.01))
				_target_scroll_time = clampi(_target_scroll_time, 0, EditorChartState.get_max_scroll_time())
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton:
		if event.ctrl_pressed or event.meta_pressed:
			var local_event := make_input_local(event) as InputEventMouseButton
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(local_event.position.y, 1.2)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(local_event.position.y, 1.0 / 1.2)
				get_viewport().set_input_as_handled()

func _zoom_at(anchor_y: float, factor: float) -> void:
	var anchor_time := y_to_time(anchor_y)
	EditorChartState.px_per_ms = clampf(EditorChartState.px_per_ms * factor, 0.02, 5.0)
	EditorChartState.scroll_time = anchor_time - int((_judge_line_y() - anchor_y) / EditorChartState.px_per_ms)
	EditorChartState.clamp_scroll()
	_target_scroll_time = EditorChartState.scroll_time
	queue_redraw()
	emit_signal("scroll_changed")

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.08, 0.10), true)
	_draw_track_columns(w, h)
	_draw_grid_lines(w, h)
	_draw_notes(w, h)
	_draw_playhead(w, h)

# 绘制四条轨道的背景色和编号
func _draw_track_columns(w: float, h: float) -> void:
	var track_w: float = w / float(NUM_TRACKS)
	var font := get_theme_default_font()

	for i in range(NUM_TRACKS):
		var col := i + 1
		var x0: float = i * track_w
		var bg_alpha: float = 0.12 if i % 2 == 0 else 0.08
		draw_rect(Rect2(x0, 0, track_w, h), Color(1, 1, 1, bg_alpha), true)

		var label := str(col)
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(font,
			Vector2(x0 + track_w / 2.0 - label_size.x / 2.0, 2),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TRACK_COLORS[i])

		if i > 0:
			draw_line(Vector2(x0, 0), Vector2(x0, h), Color(0.2, 0.2, 0.25), 1.0)

# 绘制 BPM 节拍线
func _draw_grid_lines(w: float, h: float) -> void:
	var bpm: float = EditorChartState.bpm
	if bpm <= 0:
		bpm = 80.0
	var beat_ms: float = 60000.0 / bpm
	var denom := EditorChartState.quantize_denominator
	if denom <= 0:
		denom = 4
	var sub_beat_ms: float = beat_ms / float(denom)

	var range := _get_visible_time_range()
	var start_time := range["start"] as int
	var end_time := range["end"] as int

	var step_start := int(floor(float(start_time) / sub_beat_ms))
	var step_end := int(ceil(float(end_time) / sub_beat_ms))
	for step in range(step_start, step_end + 1):
		var t := float(step) * sub_beat_ms
		var y := time_to_y(t)
		if y < 0 or y > h:
			continue
		var is_bar := step % (denom * 4) == 0
		var is_beat := step % denom == 0
		if is_bar:
			draw_line(Vector2(0, y), Vector2(w, y), Color(0.7, 0.7, 0.85, 0.95), 2.5)
		elif is_beat:
			draw_line(Vector2(0, y), Vector2(w, y), Color(0.5, 0.55, 0.7, 0.85), 1.5)
		else:
			draw_line(Vector2(0, y), Vector2(w, y), Color(0.45, 0.5, 0.65, 0.7), 1.0)

# 绘制所有可见音符
func _draw_notes(w: float, h: float) -> void:
	var track_w: float = w / float(NUM_TRACKS)
	var range := _get_visible_time_range()
	var view_start := range["start"] as int
	var view_end := range["end"] as int

	for ni in range(EditorChartState.notes.size()):
		var note: Dictionary = EditorChartState.notes[ni]
		var t := note.get("time", 0) as int

		var note_end := t
		if note.get("type", "") == "hold" and note.has("duration"):
			note_end = t + (note.get("duration", 0) as int)

		if note_end < view_start or t > view_end:
			continue

		var col := note.get("column", 1) as int
		if col < 1 or col > NUM_TRACKS:
			continue

		var ntype := note.get("type", "tap") as String

		var y := time_to_y(t)
		var end_y: float = y
		if ntype == "hold" and note.has("duration"):
			end_y = time_to_y(float(t + note.get("duration", 0) as int))

		# 普通音符以头部判断；hold 音符只要头/尾任一可见或条跨越视口就绘制
		if ntype == "hold":
			if y < 0 and end_y < 0:
				continue
			if y > h and end_y > h:
				continue
		else:
			if y < 0 or y > h:
				continue
		var color := _get_note_color(ntype)
		var x0: float = (col - 1) * track_w
		var mid_x: float = x0 + track_w / 2.0
		var is_selected: bool = (ni == selected_index)

		if ntype == "hold":
			_draw_hold_note(note, y, mid_x, track_w, color, is_selected)
		else:
			_draw_single_note(ntype, mid_x, y, track_w, color, is_selected)

func _draw_single_note(ntype: String, mid_x: float, y: float, track_w: float, color: Color, selected: bool) -> void:
	var note_w: float = maxf(track_w * 0.6, MIN_NOTE_WIDTH)
	var note_h: float = maxf(track_w * 0.2, MIN_NOTE_HEIGHT)
	var x0: float = mid_x - note_w / 2.0

	if selected:
		draw_rect(Rect2(x0 - 2, y - note_h / 2.0 - 2, note_w + 4, note_h + 4),
			Color(1, 1, 1, 0.8), false, 1.5)

	draw_rect(Rect2(x0, y - note_h / 2.0, note_w, note_h), color, true)

func _draw_hold_note(note: Dictionary, y: float, mid_x: float, track_w: float, color: Color, selected: bool) -> void:
	var dur := note.get("duration", 0) as int
	var end_y := time_to_y(float(note["time"] as int + dur))
	var bar_top := maxf(end_y, 0.0)
	var bar_h := maxf(y - bar_top, MIN_NOTE_HEIGHT)
	var bar_w: float = maxf(track_w * 0.4, MIN_NOTE_WIDTH)
	var x0: float = mid_x - bar_w / 2.0

	draw_rect(Rect2(x0, bar_top, bar_w, bar_h), color, true)

	if y >= 0:
		var head_size: float = maxf(bar_w * 1.2, 10.0)
		draw_rect(Rect2(mid_x - head_size / 2.0, y - 3, head_size, 6), Color.WHITE, true)

	if selected:
		draw_rect(Rect2(x0 - 1, bar_top - 4, bar_w + 2, bar_h + 8),
			Color(1, 1, 1, 0.8), false, 1.5)

func _draw_heart_note(mid_x: float, y: float, track_w: float, color: Color, selected: bool) -> void:
	var size: float = maxf(track_w * 0.35, 8.0)
	draw_circle(Vector2(mid_x + size * 0.25, y - size * 0.1), size * 0.25, color)
	draw_circle(Vector2(mid_x - size * 0.25, y - size * 0.1), size * 0.25, color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(mid_x - size * 0.5, y - size * 0.1),
		Vector2(mid_x + size * 0.5, y - size * 0.1),
		Vector2(mid_x, y + size * 0.3),
	]), color)
	if selected:
		draw_circle(Vector2(mid_x, y), size * 0.6, Color(1, 1, 1, 0.5), false, 1.5)

func _get_note_color(type: String) -> Color:
	match type:
		"tap":     return Color(0.3, 0.6, 1.0)
		"drag":    return Color(1.0, 0.85, 0.2)
		"release": return Color(1.0, 0.3, 0.3)
		"hold":    return Color(0.3, 1.0, 0.5)
		"heart":   return Color(1.0, 0.3, 1.0)
		_:         return Color(0.7, 0.7, 0.7)

# 绘制判定线（播放头水平线）
func _draw_playhead(w: float, _h: float) -> void:
	var y := _judge_line_y()
	draw_line(Vector2(0, y), Vector2(w, y), Color(0.3, 0.7, 1.0, 0.85), 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, y - 5), Vector2(0, y + 5), Vector2(6, y)
	]), Color(0.3, 0.7, 1.0, 0.90))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_note_index >= 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_drag_update(event.position)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_on_left_click(event.position, event.ctrl_pressed or event.meta_pressed)
			MOUSE_BUTTON_RIGHT:
				_on_right_click(event.position)

# 左键点击：检测命中音符、放置新音符或取消选择
func _on_left_click(pos: Vector2, force_place: bool) -> void:
	var track := x_to_track(pos.x)
	var time_ms := y_to_time(pos.y)

	var hit_idx := _hit_test_note(pos, track)
	if hit_idx >= 0:
		select_note(hit_idx)
		_drag_note_index = hit_idx
		_drag_original_time = EditorChartState.notes[hit_idx].get("time", 0) as int
		_drag_original_column = EditorChartState.notes[hit_idx].get("column", 1) as int
		return

	if not placement_type.is_empty() or force_place:
		_place_note(track, time_ms)
	else:
		selected_index = -1
		emit_signal("note_deselected")
		queue_redraw()

func _snap_time(time_ms: int) -> int:
	if not EditorChartState.snap_enabled:
		return time_ms
	var bpm: float = EditorChartState.bpm
	if bpm <= 0:
		bpm = 80.0
	var beat_ms: float = 60000.0 / bpm
	var denom := EditorChartState.quantize_denominator
	if denom <= 0:
		denom = 4
	var snap_ms: float = beat_ms / float(denom)
	return int(round(float(time_ms) / snap_ms) * snap_ms)

func _place_note(track: int, time_ms: int) -> void:
	var ntype := placement_type
	if ntype.is_empty():
		ntype = "tap"

	time_ms = _snap_time(time_ms)

	var note: Dictionary = {
		"type": ntype,
		"time": time_ms,
		"column": track,
	}

	if ntype == "hold":
		note["duration"] = 500
	elif ntype == "heart":
		note["map"] = [1, 2, 3, 4]

	var idx := add_note(note)
	select_note(idx)
	emit_signal("note_placed", idx)

# 右键点击：删除音符
func _on_right_click(pos: Vector2) -> void:
	var track := x_to_track(pos.x)
	var hit_idx := _hit_test_note(pos, track)
	if hit_idx >= 0:
		_delete_note(hit_idx)

# 从后往前搜索点击位置的音符（后绘制在上层，优先响应）
func _hit_test_note(pos: Vector2, track: int) -> int:
	var track_w: float = size.x / float(NUM_TRACKS)
	var hit_radius: float = track_w * 0.5
	var mid_x: float = (track - 1) * track_w + track_w / 2.0

	for ni in range(EditorChartState.notes.size() - 1, -1, -1):
		var note: Dictionary = EditorChartState.notes[ni]
		if note.get("column", 1) as int != track:
			continue

		var nt := note.get("time", 0) as int
		var ny := time_to_y(nt)

		if note.get("type", "") == "hold" and note.has("duration"):
			var dur := note.get("duration", 0) as int
			var end_y := time_to_y(float(nt + dur))
			if pos.y >= end_y - 4 and pos.y <= ny + 4:
				if absf(pos.x - mid_x) < hit_radius:
					return ni
		else:
			if absf(ny - pos.y) < hit_radius and absf(pos.x - mid_x) < hit_radius:
				return ni
	return -1

# Delete 键删除选中音符
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_DELETE and selected_index >= 0:
			_delete_note(selected_index)
			get_viewport().set_input_as_handled()

func _delete_note(index: int) -> void:
	if index < 0 or index >= EditorChartState.notes.size():
		return
	EditorChartState.notes.remove_at(index)
	if selected_index == index:
		selected_index = -1
	if _drag_note_index == index:
		_drag_note_index = -1
	emit_signal("note_deleted", index)
	queue_redraw()

func _drag_update(pos: Vector2) -> void:
	var new_time := y_to_time(pos.y)
	new_time = _snap_time(new_time)
	new_time = maxi(new_time, 0)
	var new_column := x_to_track(pos.x)
	new_column = clampi(new_column, 1, NUM_TRACKS)

	var note: Dictionary = EditorChartState.notes[_drag_note_index]
	if note["time"] != new_time or note["column"] != new_column:
		note["time"] = new_time
		note["column"] = new_column
		queue_redraw()

func _end_drag() -> void:
	if _drag_note_index < 0 or _drag_note_index >= EditorChartState.notes.size():
		_drag_note_index = -1
		return
	var note: Dictionary = EditorChartState.notes[_drag_note_index]
	var new_time := note.get("time", 0) as int
	var new_column := note.get("column", 1) as int
	if new_time != _drag_original_time or new_column != _drag_original_column:
		emit_signal("note_moved", _drag_note_index)
	_drag_note_index = -1

signal note_selected(index: int, note: Dictionary)
signal note_deselected()
signal note_deleted(index: int)
signal note_placed(index: int)
signal scroll_changed()
signal note_moved(index: int)

func select_note(index: int) -> void:
	selected_index = index
	if index >= 0 and index < EditorChartState.notes.size():
		emit_signal("note_selected", index, EditorChartState.notes[index])
	queue_redraw()

func deselect() -> void:
	selected_index = -1
	emit_signal("note_deselected")
	queue_redraw()

func add_note(note: Dictionary) -> int:
	var idx := EditorChartState.notes.size()
	EditorChartState.notes.append(note)
	queue_redraw()
	return idx

func update_playhead(time_ms: int) -> void:
	playhead_time = time_ms
