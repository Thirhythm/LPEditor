extends VBoxContainer
class_name EditorVisual

# 轨道编辑区控制器：处理鼠标 / 键盘交互（选中、放置、拖拽、删除、滚动、缩放），
# 并在状态变化时请求重绘。
# 已拆分的部分：坐标换算 → visual_geometry.gd，绘制 → visual_renderer.gd。

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
var _drag_original_duration: int = 0
var _drag_mode: int = 0
var _geom: VisualGeometry

func _ready() -> void:
	_geom = VisualGeometry.new(self)
	_target_scroll_time = EditorState.scroll_time
	_scroll_initialized = true
	queue_redraw()
	set_process_input(true)
	set_process(true)

# 平滑滚动插值，使滚动动画自然
func _process(delta: float) -> void:
	if not _scroll_initialized:
		return

	if EditorState.scroll_time != _prev_scroll_time:
		_target_scroll_time = EditorState.scroll_time

	var diff := _target_scroll_time - EditorState.scroll_time
	if absi(diff) <= 1:
		EditorState.scroll_time = _target_scroll_time
	else:
		EditorState.scroll_time += int(float(diff) * SCROLL_SMOOTH * 60.0 * delta + signf(float(diff)))

	var changed := EditorState.scroll_time != _prev_scroll_time
	_prev_scroll_time = EditorState.scroll_time

	if changed:
		emit_signal("scroll_changed")
		queue_redraw()

# 坐标换算集中在 VisualGeometry，这里保留同名转发，让交互代码读起来更直接
func time_to_y(time_ms: float) -> float:
	return _geom.time_to_y(time_ms)

func y_to_time(y: float) -> int:
	return _geom.y_to_time(y)

func x_to_track(x: float) -> int:
	return _geom.x_to_track(x)

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
				_target_scroll_time += int(200 / maxf(EditorState.px_per_ms, 0.01))
				_target_scroll_time = clampi(_target_scroll_time, 0, ChartData.get_max_scroll_time())
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_scroll_time -= int(200 / maxf(EditorState.px_per_ms, 0.01))
				_target_scroll_time = clampi(_target_scroll_time, 0, ChartData.get_max_scroll_time())
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
	EditorState.px_per_ms = clampf(EditorState.px_per_ms * factor, 0.02, 5.0)
	EditorState.scroll_time = anchor_time - int((_geom.judge_line_y() - anchor_y) / EditorState.px_per_ms)
	EditorState.clamp_scroll()
	_target_scroll_time = EditorState.scroll_time
	queue_redraw()
	emit_signal("scroll_changed")

func _draw() -> void:
	VisualRenderer.draw_all(self, _geom, selected_index)








func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_note_index >= 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_drag_update(event.position)
			get_viewport().set_input_as_handled()
		else:
			_update_cursor(event.position)
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_on_left_click(event.position, event.ctrl_pressed or event.meta_pressed)
			MOUSE_BUTTON_RIGHT:
				_on_right_click(event.position)

func _update_cursor(pos: Vector2) -> void:
	if not placement_type.is_empty():
		mouse_default_cursor_shape = CURSOR_ARROW
		return
	var track := x_to_track(pos.x)
	var tail_idx := _hit_test_hold_tail(pos, track)
	if tail_idx >= 0:
		mouse_default_cursor_shape = CURSOR_VSIZE
	else:
		mouse_default_cursor_shape = CURSOR_ARROW

# 左键点击：检测命中音符、放置新音符或取消选择
func _on_left_click(pos: Vector2, force_place: bool) -> void:
	var track := x_to_track(pos.x)
	var time_ms := y_to_time(pos.y)

	if placement_type.is_empty() and not force_place:
		var tail_idx := _hit_test_hold_tail(pos, track)
		if tail_idx >= 0:
			EditorState.push_undo_state()
			select_note(tail_idx)
			_drag_note_index = tail_idx
			_drag_mode = 2
			_drag_original_duration = ChartData.notes[tail_idx].get("duration", 0) as int
			return

		var hit_idx := _hit_test_note(pos, track)
		if hit_idx >= 0:
			EditorState.push_undo_state()
			select_note(hit_idx)
			_drag_note_index = hit_idx
			_drag_mode = 1
			_drag_original_time = ChartData.notes[hit_idx].get("time", 0) as int
			_drag_original_column = ChartData.notes[hit_idx].get("column", 1) as int
			return

		selected_index = -1
		emit_signal("note_deselected")
		queue_redraw()
		return

	_place_note(track, time_ms)

func _snap_time(time_ms: int) -> int:
	return _geom.snap_time(time_ms)

func _place_note(track: int, time_ms: int) -> void:
	time_ms = _snap_time(time_ms)

	if _note_exists_at(track, time_ms):
		return

	EditorState.push_undo_state()
	var idx := add_note(ChartDefs.make_note(placement_type, time_ms, track))
	select_note(idx)
	emit_signal("note_placed", idx)

## 同一轨道同一时刻只允许一个音符
func _note_exists_at(track: int, time_ms: int) -> bool:
	for note in ChartData.notes:
		if int(note.get("time", 0)) == time_ms and int(note.get("column", 1)) == track:
			return true
	return false

# 右键点击：删除音符
func _on_right_click(pos: Vector2) -> void:
	var track := x_to_track(pos.x)
	var hit_idx := _hit_test_note(pos, track)
	if hit_idx >= 0:
		_delete_note(hit_idx)

# 从后往前搜索点击位置的音符（后绘制在上层，优先响应）
func _hit_test_note(pos: Vector2, track: int) -> int:
	var track_w: float = size.x / float(ChartDefs.NUM_TRACKS)
	var hit_radius: float = track_w * 0.5
	var mid_x: float = (track - 1) * track_w + track_w / 2.0

	for ni in range(ChartData.notes.size() - 1, -1, -1):
		var note: Dictionary = ChartData.notes[ni]
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

func _hit_test_hold_tail(pos: Vector2, track: int) -> int:
	var track_w: float = size.x / float(ChartDefs.NUM_TRACKS)
	var mid_x: float = (track - 1) * track_w + track_w / 2.0
	if absf(pos.x - mid_x) > track_w * 0.5:
		return -1
	for ni in range(ChartData.notes.size() - 1, -1, -1):
		var note: Dictionary = ChartData.notes[ni]
		if note.get("column", 1) as int != track:
			continue
		if note.get("type", "") != "hold" or not note.has("duration"):
			continue
		var nt := note.get("time", 0) as int
		var dur := note.get("duration", 0) as int
		var end_y := time_to_y(float(nt + dur))
		if absf(pos.y - end_y) < 8.0:
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
	if index < 0 or index >= ChartData.notes.size():
		return
	EditorState.push_undo_state()
	ChartData.notes.remove_at(index)
	if selected_index == index:
		selected_index = -1
	if _drag_note_index == index:
		_drag_note_index = -1
		_drag_mode = 0
	emit_signal("note_deleted", index)
	queue_redraw()

func _drag_update(pos: Vector2) -> void:
	var note: Dictionary = ChartData.notes[_drag_note_index]

	if _drag_mode == 1:
		var new_time := y_to_time(pos.y)
		new_time = _snap_time(new_time)
		new_time = maxi(new_time, 0)
		var new_column := x_to_track(pos.x)
		new_column = clampi(new_column, 1, ChartDefs.NUM_TRACKS)
		if note["time"] != new_time or note["column"] != new_column:
			note["time"] = new_time
			note["column"] = new_column
			queue_redraw()
	elif _drag_mode == 2:
		var note_time := note.get("time", 0) as int
		var tail_time := y_to_time(pos.y)
		tail_time = _snap_time(tail_time)
		var new_duration := maxi(tail_time - note_time, 1)
		if note.get("duration", 0) != new_duration:
			note["duration"] = new_duration
			queue_redraw()

func _end_drag() -> void:
	if _drag_note_index < 0 or _drag_note_index >= ChartData.notes.size():
		_drag_note_index = -1
		_drag_mode = 0
		return
	var note: Dictionary = ChartData.notes[_drag_note_index]
	if _drag_mode == 1:
		var new_time := note.get("time", 0) as int
		var new_column := note.get("column", 1) as int
		if new_time != _drag_original_time or new_column != _drag_original_column:
			emit_signal("note_moved", _drag_note_index)
	elif _drag_mode == 2:
		if note.get("duration", 0) != _drag_original_duration:
			emit_signal("note_resized", _drag_note_index)
	_drag_note_index = -1
	_drag_mode = 0

signal note_selected(index: int, note: Dictionary)
signal note_deselected()
signal note_deleted(index: int)
signal note_placed(index: int)
signal scroll_changed()
signal note_moved(index: int)
signal note_resized(index: int)

func select_note(index: int) -> void:
	selected_index = index
	if index >= 0 and index < ChartData.notes.size():
		emit_signal("note_selected", index, ChartData.notes[index])
	queue_redraw()

func deselect() -> void:
	selected_index = -1
	_drag_note_index = -1
	_drag_mode = 0
	emit_signal("note_deselected")
	queue_redraw()

func add_note(note: Dictionary) -> int:
	var idx := ChartData.notes.size()
	ChartData.notes.append(note)
	queue_redraw()
	return idx

func update_playhead(time_ms: int) -> void:
	playhead_time = time_ms
