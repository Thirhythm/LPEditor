extends VBoxContainer
class_name EditorVisual

# 轨道编辑区控制器：处理鼠标 / 键盘交互（选中、放置、拖拽、删除、滚动、缩放），
# 并在状态变化时请求重绘。
# 已拆分的部分：坐标换算 → visual_geometry.gd，绘制 → visual_renderer.gd。

const SCROLL_SMOOTH: float = 0.18
## 命中特效开始 / 结束边界线的像素半径（与长键尾部一致的手感）
const EFFECT_EDGE_HIT_RADIUS: float = 8.0

var playhead_time: int = 0
var selected_index: int = -1
var placement_type: String = ""
# --- 特效放置 ---
var effect_placement: bool = false		# 处于「两次点击定区间」的放置模式
var selected_effect_index: int = -1
var _pending_effect_index: int = -1		# 正在放置的特效下标
var _effect_stage: int = 0				# 0 = 等待开始位置，1 = 等待结束位置
var _target_scroll_time: int = 0
var _scroll_initialized: bool = false
var _prev_scroll_time: int = 0

var _drag_note_index: int = -1
var _drag_original_time: int = 0
var _drag_original_column: int = 0
var _drag_original_duration: int = 0
var _drag_mode: int = 0
# 特效拖拽：与长键同构 —— 拖边界改区间大小，拖本体整体平移
var _drag_effect_index: int = -1
var _drag_effect_mode: int = 0			# 1 = 整体移动，2 = 拖起始边界，3 = 拖结束边界
var _drag_effect_original_time: int = 0
var _drag_effect_original_duration: int = 0
var _drag_effect_grab_time: int = 0		# 按下时鼠标所在的时间（整体平移的相对基准）
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
		if event.button_index == MOUSE_BUTTON_LEFT \
				and (_drag_note_index >= 0 or _drag_effect_index >= 0):
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
	VisualRenderer.draw_all(self, _geom, selected_index, selected_effect_index)








func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var dragging := _drag_note_index >= 0 or _drag_effect_index >= 0
		if dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
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
	if effect_placement:
		mouse_default_cursor_shape = CURSOR_CROSS
		return
	if not placement_type.is_empty():
		mouse_default_cursor_shape = CURSOR_ARROW
		return
	# 顺序必须与 _on_left_click 的实际命中一致：长键尾 → 音符 → 特效边界 → 特效本体，
	# 否则光标会承诺一个按下后并不会发生的动作
	var track := x_to_track(pos.x)
	if _hit_test_hold_tail(pos, track) >= 0:
		mouse_default_cursor_shape = CURSOR_VSIZE	# 拖长键尾改时长
		return
	if _hit_test_note(pos, track) >= 0:
		mouse_default_cursor_shape = CURSOR_ARROW	# 音符优先于特效，按下去拖的是音符
		return
	if not _hit_test_effect_edge(pos).is_empty():
		mouse_default_cursor_shape = CURSOR_VSIZE	# 拖边界改区间端点
		return
	mouse_default_cursor_shape = CURSOR_MOVE if _hit_test_effect(y_to_time(pos.y)) >= 0 else CURSOR_ARROW

# 左键点击：特效放置优先，其次检测命中音符 / 特效，最后放置新音符或取消选择
func _on_left_click(pos: Vector2, force_place: bool) -> void:
	var track := x_to_track(pos.x)
	var time_ms := y_to_time(pos.y)

	# 每次按下前先把两个拖拽通道清干净：窗口失焦等原因可能让上一次的 mouse-up 丢失，
	# 残留的下标会劫持这次拖拽（还会改写错的音符 / 特效）
	_drag_note_index = -1
	_drag_mode = 0
	_drag_effect_index = -1
	_drag_effect_mode = 0

	if effect_placement:
		_apply_effect_placement_click(time_ms)
		return

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

		# 音符优先于特效：特效是铺满轨道区的色带，作为背景层响应
		var edge := _hit_test_effect_edge(pos)
		if not edge.is_empty():
			_begin_effect_drag(edge["index"] as int, edge["mode"] as int, time_ms)
			return

		var effect_idx := _hit_test_effect(time_ms)
		if effect_idx >= 0:
			_begin_effect_drag(effect_idx, 1, time_ms)
			return

		var had_effect := selected_effect_index >= 0
		selected_index = -1
		selected_effect_index = -1
		emit_signal("note_deselected")
		if had_effect:
			emit_signal("effect_deselected")
		queue_redraw()
		return

	place_note(track, time_ms)

func _snap_time(time_ms: int) -> int:
	return _geom.snap_time(time_ms)

## 在指定轨道与时间放置一个音符，返回是否真的放下了（同轨同刻已有音符则跳过）。
## 时间会先吸附到量化网格；`note_type` 留空表示用当前工具的类型 —— 鼠标点击走这条，
## 快捷键 d/f/j/k 会显式传 "tap"，这样在「选择」模式下也能直接放蓝键。
func place_note(track: int, time_ms: int, note_type: String = "") -> bool:
	var type := note_type if not note_type.is_empty() else placement_type
	if type.is_empty():
		return false

	time_ms = _snap_time(time_ms)
	if _note_exists_at(track, time_ms):
		return false

	EditorState.push_undo_state()
	var idx := add_note(ChartDefs.make_note(type, time_ms, track))
	select_note(idx)
	emit_signal("note_placed", idx)
	return true

## 同一轨道同一时刻只允许一个音符
func _note_exists_at(track: int, time_ms: int) -> bool:
	for note in ChartData.notes:
		if int(note.get("time", 0)) == time_ms and int(note.get("column", 1)) == track:
			return true
	return false

# 右键点击：删除音符（音符优先），否则删除命中的特效
func _on_right_click(pos: Vector2) -> void:
	var track := x_to_track(pos.x)
	var hit_idx := _hit_test_note(pos, track)
	if hit_idx >= 0:
		_delete_note(hit_idx)
		return

	var effect_idx := _hit_test_effect(y_to_time(pos.y))
	if effect_idx >= 0:
		_delete_effect(effect_idx)

# 从后往前搜索点击位置的音符（后绘制在上层，优先响应）
func _hit_test_note(pos: Vector2, track: int) -> int:
	var track_w: float = size.x / float(ChartDefs.NUM_TRACKS)
	# 横向容差覆盖整条轨道；纵向按音符自身的绘制高度给（与 _draw_single_note 的 note_h 一致）。
	# 纵向若也取半个轨道宽，轨道随窗口拉宽后容差会大到几百毫秒，同轨道的远处音符会被误命中。
	var hit_x: float = track_w * 0.5
	var hit_y: float = maxf(track_w * 0.2, VisualRenderer.MIN_NOTE_HEIGHT) * 0.5 + 4.0
	var mid_x: float = (track - 1) * track_w + track_w / 2.0

	for ni in range(ChartData.notes.size() - 1, -1, -1):
		var note: Dictionary = ChartData.notes[ni]
		if note.get("column", 1) as int != track:
			continue

		var nt := note.get("time", 0) as int
		var ny := time_to_y(nt)

		if ChartDefs.is_hold(note):
			var dur := note.get("duration", 0) as int
			var end_y := time_to_y(float(nt + dur))
			if pos.y >= end_y - 4 and pos.y <= ny + 4:
				if absf(pos.x - mid_x) < hit_x:
					return ni
		else:
			if absf(ny - pos.y) < hit_y and absf(pos.x - mid_x) < hit_x:
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
		if not ChartDefs.is_hold(note):
			continue
		var nt := note.get("time", 0) as int
		var dur := note.get("duration", 0) as int
		var end_y := time_to_y(float(nt + dur))
		if absf(pos.y - end_y) < 8.0:
			return ni
	return -1

# Delete 键删除选中音符 / 选中特效
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_DELETE:
			if selected_index >= 0:
				_delete_note(selected_index)
				get_viewport().set_input_as_handled()
			elif selected_effect_index >= 0:
				_delete_effect(selected_effect_index)
				get_viewport().set_input_as_handled()

func _delete_note(index: int) -> void:
	if index < 0 or index >= ChartData.notes.size():
		return
	EditorState.push_undo_state()
	ChartData.notes.remove_at(index)

	# 删除后下标前移，选中 / 拖拽中的下标同步调整（否则会指到别的音符甚至越界）
	if selected_index == index:
		selected_index = -1
	elif selected_index > index:
		selected_index -= 1

	if _drag_note_index == index:
		_drag_note_index = -1
		_drag_mode = 0
	elif _drag_note_index > index:
		_drag_note_index -= 1

	emit_signal("note_deleted", index)
	queue_redraw()

# --- 特效 ---

## 附加一个新特效并返回其下标（由主控制器在「添加特效」时调用）
func add_effect(effect: Dictionary) -> int:
	var idx := ChartData.effects.size()
	ChartData.effects.append(effect)
	queue_redraw()
	return idx

## 进入特效放置模式：先点击轨道区确定开始位置，再点击确定结束位置
func begin_effect_placement(index: int) -> void:
	if index < 0 or index >= ChartData.effects.size():
		return
	effect_placement = true
	_effect_stage = 0
	_pending_effect_index = index
	mouse_default_cursor_shape = CURSOR_CROSS
	select_effect(index)

## 退出特效放置模式（切换工具 / 分类时调用）；已创建的特效保留，可用撤销移除
func cancel_effect_placement() -> void:
	if not effect_placement:
		return
	effect_placement = false
	_effect_stage = 0
	_pending_effect_index = -1
	mouse_default_cursor_shape = CURSOR_ARROW
	queue_redraw()

## 放置模式下的点击：第一次定开始时间，第二次定结束时间
func _apply_effect_placement_click(time_ms: int) -> void:
	if _pending_effect_index < 0 or _pending_effect_index >= ChartData.effects.size():
		cancel_effect_placement()
		return

	var index := _pending_effect_index
	var effect: Dictionary = ChartData.effects[index]
	var click_time := _snap_time(maxi(time_ms, 0))
	EditorState.push_undo_state()

	if _effect_stage == 0:
		effect["time"] = click_time
		_effect_stage = 1
		emit_signal("effect_start_set", index)
	else:
		var start := effect.get("time", 0) as int
		effect["duration"] = maxi(click_time - start, ChartDefs.EFFECT_MIN_DURATION_MS)
		effect_placement = false
		_pending_effect_index = -1
		_effect_stage = 0
		mouse_default_cursor_shape = CURSOR_ARROW
		emit_signal("effect_end_set", index)
	queue_redraw()

## 特效命中：时间落在区间内即命中（特效区间横跨全部轨道，作为背景层）
func _hit_test_effect(time_ms: int) -> int:
	for ei in range(ChartData.effects.size() - 1, -1, -1):
		var effect: Dictionary = ChartData.effects[ei]
		if time_ms >= int(effect.get("time", 0)) and time_ms <= ChartDefs.effect_end_time(effect):
			return ei
	return -1

func _delete_effect(index: int) -> void:
	if index < 0 or index >= ChartData.effects.size():
		return
	EditorState.push_undo_state()
	ChartData.effects.remove_at(index)

	# 删除后下标前移，选中 / 放置中的下标同步调整
	if selected_effect_index == index:
		selected_effect_index = -1
	elif selected_effect_index > index:
		selected_effect_index -= 1

	if _pending_effect_index == index:
		effect_placement = false
		_effect_stage = 0
		_pending_effect_index = -1
		mouse_default_cursor_shape = CURSOR_ARROW
	elif _pending_effect_index > index:
		_pending_effect_index -= 1

	if _drag_effect_index == index:
		_drag_effect_index = -1
		_drag_effect_mode = 0
	elif _drag_effect_index > index:
		_drag_effect_index -= 1

	emit_signal("effect_deleted", index)
	queue_redraw()

## 命中特效的开始 / 结束边界线；返回 { index, mode }，未命中返回空字典。
## mode 2 = 起始边，3 = 结束边。
## 两条边都够得着时取更近的那条；落在区间内部时命中半径按区间高度收缩，
## 这样缩得很短（甚至被拖成 1ms）的区间中间仍留得出拖本体平移的余地。
func _hit_test_effect_edge(pos: Vector2) -> Dictionary:
	for ei in range(ChartData.effects.size() - 1, -1, -1):
		var effect: Dictionary = ChartData.effects[ei]
		var y_start := time_to_y(float(effect.get("time", 0)))
		var y_end := time_to_y(float(ChartDefs.effect_end_time(effect)))
		var radius := EFFECT_EDGE_HIT_RADIUS
		if pos.y <= maxf(y_start, y_end) and pos.y >= minf(y_start, y_end):
			radius = minf(EFFECT_EDGE_HIT_RADIUS, absf(y_start - y_end) * 0.35)

		var d_start := absf(pos.y - y_start)
		var d_end := absf(pos.y - y_end)
		if d_start <= radius and d_start <= d_end:
			return {"index": ei, "mode": 2}
		if d_end <= radius:
			return {"index": ei, "mode": 3}
	return {}

## 与长键同构：按下左键即压一次撤销点并进入拖拽，移动过程中实时改数据。
## grab_time 是按下时鼠标所在的时间，整体平移按它做相对位移（抓色带中间时区间不跳）
func _begin_effect_drag(index: int, mode: int, grab_time: int) -> void:
	if index < 0 or index >= ChartData.effects.size():
		return
	EditorState.push_undo_state()
	select_effect(index)
	_drag_effect_index = index
	_drag_effect_mode = mode
	_drag_effect_grab_time = grab_time
	_drag_effect_original_time = ChartData.effects[index].get("time", 0) as int
	_drag_effect_original_duration = ChartData.effects[index].get("duration", 0) as int

func _drag_update_effect(pos: Vector2) -> void:
	if _drag_effect_index < 0 or _drag_effect_index >= ChartData.effects.size():
		_drag_effect_index = -1
		_drag_effect_mode = 0
		return

	var effect: Dictionary = ChartData.effects[_drag_effect_index]
	var target := maxi(_snap_time(y_to_time(pos.y)), 0)

	match _drag_effect_mode:
		1:	# 整体平移：时长不变，跟随鼠标的相对位移
			var new_time := maxi(_drag_effect_original_time + target - _drag_effect_grab_time, 0)
			if effect.get("time", 0) != new_time:
				effect["time"] = new_time
				queue_redraw()
		2:	# 拖起始边：结束时间固定，区间反向伸缩
			var end := _drag_effect_original_time + _drag_effect_original_duration
			var new_time := maxi(mini(target, end - ChartDefs.EFFECT_MIN_DURATION_MS), 0)
			if effect.get("time", 0) != new_time:
				effect["time"] = new_time
				effect["duration"] = end - new_time
				queue_redraw()
		3:	# 拖结束边：开始时间固定
			var start := effect.get("time", 0) as int
			var new_duration := maxi(target - start, ChartDefs.EFFECT_MIN_DURATION_MS)
			if effect.get("duration", 0) != new_duration:
				effect["duration"] = new_duration
				queue_redraw()

func _end_effect_drag() -> void:
	var index := _drag_effect_index
	_drag_effect_index = -1
	_drag_effect_mode = 0

	if index < 0 or index >= ChartData.effects.size():
		return
	var effect: Dictionary = ChartData.effects[index]
	# 只是点了一下没有真的拖动时不产生额外通知
	if effect.get("time", 0) == _drag_effect_original_time \
			and effect.get("duration", 0) == _drag_effect_original_duration:
		return
	emit_signal("effect_adjusted", index)

func _drag_update(pos: Vector2) -> void:
	if _drag_effect_index >= 0:
		_drag_update_effect(pos)
		return

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
	# 两个通道各自收尾，不用 early return 跳过另一个，避免残留下标带到下一次拖拽
	if _drag_effect_index >= 0:
		_end_effect_drag()

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
signal effect_selected(index: int, effect: Dictionary)
signal effect_deselected()
signal effect_start_set(index: int)
signal effect_end_set(index: int)
signal effect_adjusted(index: int)
signal effect_deleted(index: int)

func select_note(index: int) -> void:
	selected_index = index
	selected_effect_index = -1
	if index >= 0 and index < ChartData.notes.size():
		emit_signal("note_selected", index, ChartData.notes[index])
	queue_redraw()

func select_effect(index: int) -> void:
	selected_index = -1
	selected_effect_index = index
	if index >= 0 and index < ChartData.effects.size():
		emit_signal("effect_selected", index, ChartData.effects[index])
	queue_redraw()

func deselect() -> void:
	selected_index = -1
	selected_effect_index = -1
	_drag_note_index = -1
	_drag_mode = 0
	_drag_effect_index = -1
	_drag_effect_mode = 0
	emit_signal("note_deselected")
	queue_redraw()

func add_note(note: Dictionary) -> int:
	var idx := ChartData.notes.size()
	ChartData.notes.append(note)
	queue_redraw()
	return idx

func update_playhead(time_ms: int) -> void:
	playhead_time = time_ms
