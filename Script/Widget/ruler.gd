extends Control
class_name EditorRuler

## 标尺高度（像素）
const RULER_HEIGHT: float = 100.0
## 轨道缩略图区域高度
const THUMBNAIL_HEIGHT: float = 60.0
## 时间指示器区域高度
const TIME_INDICATOR_HEIGHT: float = 40.0
## 轨道数量
const NUM_TRACKS: int = 4
## 轨道颜色
const TRACK_COLORS: Array[Color] = [
	Color(0.25, 0.40, 0.70),  # 轨道1 - 蓝色
	Color(0.70, 0.45, 0.20),  # 轨道2 - 橙色
	Color(0.25, 0.65, 0.40),  # 轨道3 - 绿色
	Color(0.70, 0.25, 0.45),  # 轨道4 - 粉紫色
]

## 播放头时间(ms)
var playhead_time: int = 0

## 音符数据（用于缩略图绘制）
var notes: Array[Dictionary] = []

func _ready() -> void:
	queue_redraw()
	set_process_input(true)
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

# ============================================================
# 坐标映射
# ============================================================

## 时间(ms) -> 屏幕 x
func time_to_x(time_ms: int) -> float:
	return (time_ms - EditorChartState.scroll_time) * EditorChartState.px_per_ms

## 屏幕 x -> 时间(ms)
func x_to_time(x: float) -> int:
	return EditorChartState.scroll_time + int(x / EditorChartState.px_per_ms)

# ============================================================
# 绘制
# ============================================================

func _draw() -> void:
	var w: float = size.x
	var h: float = RULER_HEIGHT
	
	# 1. 背景
	draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.12, 0.14), true)
	
	# 2. 轨道缩略图
	_draw_track_thumbnail(w)
	
	# 3. 播放头
	_draw_playhead(w, h)
	
	# 4. 时间指示器
	_draw_time_indicator(w, h)
	
	# 5. 底部分隔线
	draw_line(Vector2(0, h), Vector2(w, h), Color(0.3, 0.3, 0.3), 1.0)

## 绘制轨道缩略图 — 4 条横栏 + 音符标记
func _draw_track_thumbnail(w: float) -> void:
	var track_area_top: float = 4.0
	var track_h: float = THUMBNAIL_HEIGHT / NUM_TRACKS
	var font := get_theme_default_font()
	
	for i in range(NUM_TRACKS):
		var col := i + 1
		var y0: float = track_area_top + i * track_h
		
		# 轨道背景（横栏）
		draw_rect(Rect2(0, y0, w, track_h),
			TRACK_COLORS[i] * Color(0.3, 0.3, 0.3, 0.5), true)
		
		# 轨道边框
		draw_rect(Rect2(0, y0, w, track_h),
			TRACK_COLORS[i], false, 1.0)
		
		# 轨道编号（左侧）
		var label := str(col)
		draw_string(font, Vector2(3, y0 + 1), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TRACK_COLORS[i])
	
	# 音符缩略标记
	if not notes.is_empty():
		var view_start := EditorChartState.scroll_time
		var view_end := view_start + int(w / EditorChartState.px_per_ms)
		
		for note in notes:
			var t := note.get("time", 0) as int
			if t < view_start or t > view_end:
				continue
			var col := note.get("column", 1) as int - 1  # 0-based
			if col < 0 or col >= NUM_TRACKS:
				continue
			
			var nx := time_to_x(t)
			if nx < 0 or nx > w:
				continue
			
			var note_type := note.get("type", "") as String
			var note_color := _get_note_color(note_type)
			var y0: float = track_area_top + col * track_h
			var mid_y: float = y0 + track_h / 2.0
			
			# hold 绘制持续时间条
			if note_type == "hold" and note.has("duration"):
				var dur := note.get("duration", 0) as int
				var end_x := time_to_x(t + dur)
				var bar_y := mid_y - 2.0
				draw_rect(Rect2(nx, bar_y, maxf(end_x - nx, 2.0), 4.0), note_color, true)
			else:
				draw_circle(Vector2(nx, mid_y), 3.0, note_color)

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

## 绘制播放头
func _draw_playhead(w: float, h: float) -> void:
	var x := time_to_x(playhead_time)
	if x < 0 or x > w:
		return
	# 播放头竖线 — 贯穿缩略图和时间指示区域
	draw_line(Vector2(x, 0), Vector2(x, h), Color(0.3, 0.7, 1.0), 2.0)
	# 顶部三角
	var pts := PackedVector2Array([
		Vector2(x - 5, 0),
		Vector2(x + 5, 0),
		Vector2(x, 6)
	])
	draw_colored_polygon(pts, Color(0.3, 0.7, 1.0))

## 绘制时间指示器 — 显示当前播放头时间戳（毫秒）
func _draw_time_indicator(w: float, h: float) -> void:
	var indicator_y := THUMBNAIL_HEIGHT + 10.0
	var font := get_theme_default_font()
	
	# 分隔线
	draw_line(Vector2(0, indicator_y - 2), Vector2(w, indicator_y - 2), Color(0.25, 0.25, 0.25), 1.0)
	
	# 格式: MM:SS.ms
	var total_sec := playhead_time / 1000
	var minutes := total_sec / 60
	var seconds := total_sec % 60
	var millis := playhead_time % 1000
	var time_label := "%d:%02d.%03d" % [minutes, seconds, millis]
	
	# 计算文本位置 — 居中
	var label_size := font.get_string_size(time_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	var label_x := (w - label_size.x) / 2.0
	
	draw_string(font, Vector2(label_x, indicator_y), time_label, 
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.85, 0.95))
	
	# 副标签：毫秒
	var ms_label := "%d ms" % playhead_time
	var ms_size := font.get_string_size(ms_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	draw_string(font, Vector2((w - ms_size.x) / 2.0, indicator_y + 18), ms_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.6))

func _get_font() -> Font:
	return get_theme_default_font()

# ============================================================
# 交互
# ============================================================

func _input(event: InputEvent) -> void:
	if not get_global_rect().has_point(get_global_mouse_position()):
		return
	
	# 滚轮横向滚动
	if event is InputEventMouseButton and event.pressed:
		if not event.ctrl_pressed and not event.meta_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				EditorChartState.scroll_time -= int(200 / EditorChartState.px_per_ms)
				EditorChartState.clamp_scroll()
				queue_redraw()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				EditorChartState.scroll_time += int(200 / EditorChartState.px_per_ms)
				EditorChartState.clamp_scroll()
				queue_redraw()
				return
	
	# Ctrl+滚轮 = 缩放
	if event is InputEventMouseButton:
		if event.ctrl_pressed or event.meta_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position.x, 1.2)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position.x, 1.0 / 1.2)

## 以鼠标位置为中心缩放
func _zoom_at(anchor_x: float, factor: float) -> void:
	var anchor_time := x_to_time(anchor_x)
	EditorChartState.px_per_ms = clampf(EditorChartState.px_per_ms * factor, 0.02, 5.0)
	# 保持锚点时间在屏幕上不动
	EditorChartState.scroll_time = anchor_time - int(anchor_x / EditorChartState.px_per_ms)
	EditorChartState.clamp_scroll()
	queue_redraw()

## 点击跳转播放头
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		playhead_time = x_to_time(event.position.x)
		queue_redraw()
		emit_signal("playhead_moved", playhead_time)

# ============================================================
# 外部调用接口
# ============================================================

signal playhead_moved(time_ms: int)

## 设置音符数据（用于缩略图）
func set_notes(data: Array[Dictionary]) -> void:
	notes = data
	queue_redraw()

## 滚动到指定时间
func scroll_to(time_ms: int) -> void:
	EditorChartState.scroll_time = time_ms
	queue_redraw()

## 更新播放头
func update_playhead(time_ms: int) -> void:
	playhead_time = time_ms
	queue_redraw()
