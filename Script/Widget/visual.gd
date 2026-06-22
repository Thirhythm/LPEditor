extends VBoxContainer
class_name EditorVisual

## 轨道数量
const NUM_TRACKS: int = 4
## 轨道颜色
const TRACK_COLORS: Array[Color] = [
	Color(0.25, 0.40, 0.70),  # 轨道1 - 蓝
	Color(0.70, 0.45, 0.20),  # 轨道2 - 橙
	Color(0.25, 0.65, 0.40),  # 轨道3 - 绿
	Color(0.70, 0.25, 0.45),  # 轨道4 - 粉紫
]
## 音符最小高度（保证可见）
const MIN_NOTE_HEIGHT: float = 6.0
## 音符最小宽度
const MIN_NOTE_WIDTH: float = 8.0
## 判定线位置（距顶部比例，0.85 = 85% 处）
const JUDGE_LINE_RATIO: float = 0.85
## 滚动平滑插值速度（值越大越灵敏，1.0 = 立即到达）
const SCROLL_SMOOTH: float = 0.18

## 播放头时间(ms) → 判定线位置
var playhead_time: int = 0
## 当前选中的音符索引 (-1 表示无)
var selected_index: int = -1
## 放置模式下的音符类型（空 = 仅选择）
var placement_type: String = ""
## 滚轮目标（用于平滑插值）
var _target_scroll_time: int = 0
var _scroll_initialized: bool = false

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# 让子节点（Tracks -> Track1..4 Panel）不吞噬鼠标事件
	_set_child_mouse_filter(MOUSE_FILTER_IGNORE)
	# 让 Panel 子节点透明，不遮挡 _draw() 绘制内容
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

## 上一帧的滚动时间（检测外部修改）
var _prev_scroll_time: int = 0

func _process(delta: float) -> void:
	# 平滑滚动插值
	if not _scroll_initialized:
		return
	
	# 检测外部修改（Ruler 等直接改了 scroll_time）
	if EditorChartState.scroll_time != _prev_scroll_time:
		_target_scroll_time = EditorChartState.scroll_time
	
	var diff := _target_scroll_time - EditorChartState.scroll_time
	if absi(diff) <= 1:
		EditorChartState.scroll_time = _target_scroll_time
	else:
		EditorChartState.scroll_time += int(float(diff) * SCROLL_SMOOTH * 60.0 * delta + signf(float(diff)))
	
	# 仅在滚动位置实际变化时通知 Ruler 并重绘
	var changed := EditorChartState.scroll_time != _prev_scroll_time
	_prev_scroll_time = EditorChartState.scroll_time
	
	if changed:
		emit_signal("scroll_changed")
		queue_redraw()

# ============================================================
# 坐标映射 — 纵向轨道（Y=时间，X=轨道列）
# ============================================================

## 判定线 Y 坐标
func _judge_line_y() -> float:
	return size.y * JUDGE_LINE_RATIO

## 时间(ms) → 屏幕 y 坐标（判定线=scroll_time，时间增加 → 向上移动）
func time_to_y(time_ms: float) -> float:
	return _judge_line_y() - (time_ms - EditorChartState.scroll_time) * EditorChartState.px_per_ms

## 屏幕 y → 时间(ms)
func y_to_time(y: float) -> int:
	return EditorChartState.scroll_time + int((_judge_line_y() - y) / EditorChartState.px_per_ms)

## 轨道编号(1-based) → 屏幕 x 范围
func track_to_x_range(col: int) -> Dictionary:
	var track_w: float = size.x / float(NUM_TRACKS)
	var x0: float = (col - 1) * track_w
	return {"left": x0, "right": x0 + track_w, "mid": x0 + track_w / 2.0}

## 屏幕 x → 轨道编号(1-based)
func x_to_track(x: float) -> int:
	var track_w: float = size.x / float(NUM_TRACKS)
	return clampi(int(x / track_w) + 1, 1, NUM_TRACKS)

## 可见时间范围（从顶部 y=0 到底部 y=h）
func _get_visible_time_range() -> Dictionary:
	var px := maxf(EditorChartState.px_per_ms, 0.001)
	return {
		"start": EditorChartState.scroll_time - int((size.y - _judge_line_y()) / px),  # y=h 对应的时间（判定线以下）
		"end": EditorChartState.scroll_time + int(_judge_line_y() / px)               # y=0 对应的时间（判定线以上）
	}

# ============================================================
# 滚动 / 缩放（纵向）
# ============================================================

func _input(event: InputEvent) -> void:
	if not get_global_rect().has_point(get_global_mouse_position()):
		return
	
	# 滚轮滚动轨道（时间轴上下）
	if event is InputEventMouseButton and event.pressed:
		if not event.ctrl_pressed and not event.meta_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_scroll_time -= int(200 / maxf(EditorChartState.px_per_ms, 0.01))
				_target_scroll_time = clampi(_target_scroll_time, 0, EditorChartState.get_max_scroll_time())
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_scroll_time += int(200 / maxf(EditorChartState.px_per_ms, 0.01))
				_target_scroll_time = clampi(_target_scroll_time, 0, EditorChartState.get_max_scroll_time())
				return
	
	# Ctrl+滚轮 = 纵向缩放
	if event is InputEventMouseButton:
		if event.ctrl_pressed or event.meta_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position.y, 1.2)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position.y, 1.0 / 1.2)

func _zoom_at(anchor_y: float, factor: float) -> void:
	var anchor_time := y_to_time(anchor_y)
	EditorChartState.px_per_ms = clampf(EditorChartState.px_per_ms * factor, 0.02, 5.0)
	EditorChartState.scroll_time = anchor_time - int((_judge_line_y() - anchor_y) / EditorChartState.px_per_ms)
	EditorChartState.clamp_scroll()
	_target_scroll_time = EditorChartState.scroll_time
	queue_redraw()
	emit_signal("scroll_changed")

# ============================================================
# 绘制
# ============================================================

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	
	# 1. 背景
	draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.08, 0.10), true)
	
	# 2. 轨道背景（纵向列）
	_draw_track_columns(w, h)
	
	# 3. 节拍横线
	_draw_grid_lines(w, h)
	
	# 4. 音符
	_draw_notes(w, h)
	
	# 5. 播放头 / 判定线
	_draw_playhead(w, h)

## 绘制纵向轨道列
func _draw_track_columns(w: float, h: float) -> void:
	var track_w: float = w / float(NUM_TRACKS)
	var font := get_theme_default_font()
	
	for i in range(NUM_TRACKS):
		var col := i + 1
		var x0: float = i * track_w
		
		# 交替背景色
		var bg_alpha: float = 0.12 if i % 2 == 0 else 0.08
		draw_rect(Rect2(x0, 0, track_w, h), Color(1, 1, 1, bg_alpha), true)
		
		# 轨道编号标签（顶部居中）
		var label := str(col)
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(font,
			Vector2(x0 + track_w / 2.0 - label_size.x / 2.0, 2),
			label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			TRACK_COLORS[i])
		
		# 轨道分隔线（竖线）
		if i > 0:
			draw_line(Vector2(x0, 0), Vector2(x0, h), Color(0.2, 0.2, 0.25), 1.0)

## 绘制节拍横线（每拍一条）
func _draw_grid_lines(w: float, h: float) -> void:
	var bpm: float = EditorChartState.bpm
	if bpm <= 0:
		bpm = 80.0
	var beat_ms: float = 60000.0 / bpm
	
	var range := _get_visible_time_range()
	var start_time := range["start"] as int
	var end_time := range["end"] as int
	
	var t: float = floor(float(start_time) / beat_ms) * beat_ms
	while t <= end_time:
		var y := time_to_y(t)
		if y >= 0 and y <= h:
			var bar_idx := int(t / beat_ms)
			var is_bar := bar_idx % 4 == 0
			var color := Color(0.25, 0.25, 0.3, 0.7) if is_bar else Color(0.15, 0.15, 0.18, 0.5)
			var line_w := 1.5 if is_bar else 0.5
			draw_line(Vector2(0, y), Vector2(w, y), color, line_w)
		t += beat_ms

## 绘制音符
func _draw_notes(w: float, h: float) -> void:
	var track_w: float = w / float(NUM_TRACKS)
	var range := _get_visible_time_range()
	var view_start := range["start"] as int
	var view_end := range["end"] as int
	
	for ni in range(EditorChartState.notes.size()):
		var note: Dictionary = EditorChartState.notes[ni]
		var t := note.get("time", 0) as int
		
		# hold 音符检查结束时间是否可见
		var note_end := t
		if note.get("type", "") == "hold" and note.has("duration"):
			note_end = t + (note.get("duration", 0) as int)
		
		if note_end < view_start or t > view_end:
			continue
		
		var col := note.get("column", 1) as int
		if col < 1 or col > NUM_TRACKS:
			continue
		
		var y := time_to_y(t)
		if y < 0 or y > h:
			continue
		
		var ntype := note.get("type", "tap") as String
		var color := _get_note_color(ntype)
		var x0: float = (col - 1) * track_w
		var mid_x: float = x0 + track_w / 2.0
		
		var is_selected: bool = (ni == selected_index)
		
		match ntype:
			"hold":
				_draw_hold_note(note, y, mid_x, track_w, color, is_selected)
			"heart":
				_draw_heart_note(mid_x, y, track_w, color, is_selected)
			_:
				_draw_single_note(ntype, mid_x, y, track_w, color, is_selected)

## 绘制普通音符（tap/drag/release）
func _draw_single_note(ntype: String, mid_x: float, y: float, track_w: float, color: Color, selected: bool) -> void:
	var note_w: float = maxf(track_w * 0.6, MIN_NOTE_WIDTH)
	var note_h: float = maxf(track_w * 0.2, MIN_NOTE_HEIGHT)
	var x0: float = mid_x - note_w / 2.0
	
	# 选中高亮边框
	if selected:
		draw_rect(Rect2(x0 - 2, y - note_h / 2.0 - 2, note_w + 4, note_h + 4),
			Color(1, 1, 1, 0.8), false, 1.5)
	
	match ntype:
		"drag":
			# 菱形
			var pts := PackedVector2Array([
				Vector2(mid_x, y - note_h / 2.0),
				Vector2(mid_x + note_w / 2.0, y),
				Vector2(mid_x, y + note_h / 2.0),
				Vector2(mid_x - note_w / 2.0, y),
			])
			draw_colored_polygon(pts, color)
		"release":
			# 倒三角
			var pts := PackedVector2Array([
				Vector2(mid_x - note_w / 2.0, y - note_h / 2.0),
				Vector2(mid_x + note_w / 2.0, y - note_h / 2.0),
				Vector2(mid_x, y + note_h / 2.0),
			])
			draw_colored_polygon(pts, color)
		_:
			# tap - 圆角矩形
			draw_rect(Rect2(x0, y - note_h / 2.0, note_w, note_h), color, true)

## 绘制 hold 长键（时间向上延伸，裁剪到可见区域）
func _draw_hold_note(note: Dictionary, y: float, mid_x: float, track_w: float, color: Color, selected: bool) -> void:
	var dur := note.get("duration", 0) as int
	var end_y := time_to_y(float(note["time"] as int + dur))
	# 裁剪上边界
	var bar_top := maxf(end_y, 0.0)
	var bar_h := maxf(y - bar_top, MIN_NOTE_HEIGHT)
	var bar_w: float = maxf(track_w * 0.4, MIN_NOTE_WIDTH)
	var x0: float = mid_x - bar_w / 2.0
	
	# 长条主体
	draw_rect(Rect2(x0, bar_top, bar_w, bar_h), color, true)
	
	# 头部标记（在 y 位置，即长条底部）
	if y >= 0:
		var head_size: float = maxf(bar_w * 1.2, 10.0)
		draw_rect(Rect2(mid_x - head_size / 2.0, y - 3, head_size, 6), Color.WHITE, true)
	
	# 选中边框
	if selected:
		draw_rect(Rect2(x0 - 1, bar_top - 4, bar_w + 2, bar_h + 8),
			Color(1, 1, 1, 0.8), false, 1.5)

## 绘制 heart 心键
func _draw_heart_note(mid_x: float, y: float, track_w: float, color: Color, selected: bool) -> void:
	var size: float = maxf(track_w * 0.35, 8.0)
	
	# 心形：两个圆 + 一个三角
	draw_circle(Vector2(mid_x + size * 0.25, y - size * 0.1), size * 0.25, color)
	draw_circle(Vector2(mid_x - size * 0.25, y - size * 0.1), size * 0.25, color)
	var pts := PackedVector2Array([
		Vector2(mid_x - size * 0.5, y - size * 0.1),
		Vector2(mid_x + size * 0.5, y - size * 0.1),
		Vector2(mid_x, y + size * 0.3),
	])
	draw_colored_polygon(pts, color)
	
	if selected:
		draw_circle(Vector2(mid_x, y), size * 0.6, Color(1, 1, 1, 0.5), false, 1.5)

## 获取音符颜色
func _get_note_color(type: String) -> Color:
	match type:
		"tap":
			return Color(0.3, 0.6, 1.0)    # 蓝键
		"drag":
			return Color(1.0, 0.85, 0.2)   # 黄键
		"release":
			return Color(1.0, 0.3, 0.3)    # 红键
		"hold":
			return Color(0.3, 1.0, 0.5)    # 长键 - 青色
		"heart":
			return Color(1.0, 0.3, 1.0)    # 心键 - 粉色
		_:
			return Color(0.7, 0.7, 0.7)

## 绘制播放头（判定线，固定位置的水平横线）
func _draw_playhead(w: float, _h: float) -> void:
	var y := _judge_line_y()
	draw_line(Vector2(0, y), Vector2(w, y), Color(0.3, 0.7, 1.0, 0.85), 2.0)
	# 左侧三角
	var pts := PackedVector2Array([
		Vector2(0, y - 5),
		Vector2(0, y + 5),
		Vector2(6, y)
	])
	draw_colored_polygon(pts, Color(0.3, 0.7, 1.0, 0.90))

# ============================================================
# 交互：鼠标点击
# ============================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_on_left_click(event.position, event.ctrl_pressed or event.meta_pressed)
			MOUSE_BUTTON_RIGHT:
				_on_right_click(event.position)

func _on_left_click(pos: Vector2, force_place: bool) -> void:
	var track := x_to_track(pos.x)
	var time_ms := y_to_time(pos.y)
	print("[Visual] 左键点击 pos=(%.1f, %.1f) track=%d time=%dms force_place=%s placement_type='%s'" % [pos.x, pos.y, track, time_ms, force_place, placement_type])
	
	# 先检查是否点击到了音符
	var hit_idx := _hit_test_note(pos, track)
	if hit_idx >= 0:
		print("[Visual] 命中音符 index=%d" % hit_idx)
		select_note(hit_idx)
		return
	
	# 未点击到音符 → 尝试放置或取消选择
	if not placement_type.is_empty() or force_place:
		_place_note(track, time_ms)
	else:
		print("[Visual] 取消选择（未命中音符且非放置模式）")
		selected_index = -1
		emit_signal("note_deselected")
		queue_redraw()

func _place_note(track: int, time_ms: int) -> void:
	var ntype := placement_type
	if ntype.is_empty():
		ntype = "tap"
	
	print("[Visual] 放置音符 type=%s track=%d time=%dms size=%s" % [ntype, track, time_ms, size])
	
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
	print("[Visual] 音符已添加 index=%d total_notes=%d" % [idx, EditorChartState.notes.size()])
	emit_signal("note_placed", idx)

func _on_right_click(pos: Vector2) -> void:
	var track := x_to_track(pos.x)
	var hit_idx := _hit_test_note(pos, track)
	if hit_idx >= 0:
		_delete_note(hit_idx)

## 命中测试音符
func _hit_test_note(pos: Vector2, track: int) -> int:
	var track_w: float = size.x / float(NUM_TRACKS)
	var hit_radius: float = track_w * 0.5
	var mid_x: float = (track - 1) * track_w + track_w / 2.0
	
	# 从后往前搜索（后绘制的在上层）
	for ni in range(EditorChartState.notes.size() - 1, -1, -1):
		var note: Dictionary = EditorChartState.notes[ni]
		var nc := note.get("column", 1) as int
		if nc != track:
			continue
		
		var nt := note.get("time", 0) as int
		var ny := time_to_y(nt)
		var ntype := note.get("type", "") as String
		
		if ntype == "hold" and note.has("duration"):
			var dur := note.get("duration", 0) as int
			var end_y := time_to_y(float(nt + dur))
			# 翻转轴：end_y 在上（更小），ny 在下（更大）
			if pos.y >= end_y - 4 and pos.y <= ny + 4:
				if absf(pos.x - mid_x) < hit_radius:
					return ni
		else:
			if absf(ny - pos.y) < hit_radius:
				if absf(pos.x - mid_x) < hit_radius:
					return ni
	
	return -1

# ============================================================
# 键盘输入：删除选中的音符
# ============================================================

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
	emit_signal("note_deleted", index)
	queue_redraw()

# ============================================================
# 外部调用接口
# ============================================================

signal note_selected(index: int, note: Dictionary)
signal note_deselected()
signal note_deleted(index: int)
signal note_placed(index: int)
signal scroll_changed()

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
