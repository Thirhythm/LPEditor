class_name VisualRenderer
extends RefCounted

## 轨道编辑区的绘制：轨道底色、BPM 网格线、音符、判定线。
##
## 与 visual.gd 的输入 / 编辑逻辑分开：
## 这里只负责「给定几何换算，把当前谱面画出来」，不修改任何状态。
## 全部为静态方法，调用方传入要做画的 CanvasItem。

const MIN_NOTE_HEIGHT: float = 6.0
const MIN_NOTE_WIDTH: float = 8.0
const BACKGROUND_COLOR := Color(0.08, 0.08, 0.10)
const PLAYHEAD_COLOR := Color(0.3, 0.7, 1.0, 0.85)
const SELECTION_COLOR := Color(1, 1, 1, 0.8)
## 特效区间的填充 / 边框透明度（颜色取自 ChartDefs.EFFECT_COLOR）
const EFFECT_FILL_ALPHA: float = 0.16
const EFFECT_BORDER_ALPHA: float = 0.9


## 画整块轨道区；selected_index / selected_effect_index 为当前选中项（-1 表示无选中）
static func draw_all(ci: Control, geom: VisualGeometry, selected_index: int,
		selected_effect_index: int = -1) -> void:
	var w: float = ci.size.x
	var h: float = ci.size.y

	ci.draw_rect(Rect2(0, 0, w, h), BACKGROUND_COLOR, true)
	_draw_track_columns(ci, w, h)
	_draw_effects(ci, geom, w, h, selected_effect_index)
	_draw_grid_lines(ci, geom, w, h)
	_draw_notes(ci, geom, w, h, selected_index)
	_draw_playhead(ci, geom, w, h)


# --- 轨道与网格 ---

## 四条轨道的底色与编号
static func _draw_track_columns(ci: Control, w: float, h: float) -> void:
	var track_w: float = w / float(ChartDefs.NUM_TRACKS)
	var font := ci.get_theme_default_font()

	for i in range(ChartDefs.NUM_TRACKS):
		var x0: float = i * track_w
		var bg_alpha: float = 0.12 if i % 2 == 0 else 0.08
		ci.draw_rect(Rect2(x0, 0, track_w, h), Color(1, 1, 1, bg_alpha), true)

		var label := str(i + 1)
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		ci.draw_string(font,
			Vector2(x0 + track_w / 2.0 - label_size.x / 2.0, 2),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ChartDefs.TRACK_COLORS[i])

		if i > 0:
			ci.draw_line(Vector2(x0, 0), Vector2(x0, h), Color(0.2, 0.2, 0.25), 1.0)


## BPM 节拍线：小节 / 拍 / 子拍三级
static func _draw_grid_lines(ci: Control, geom: VisualGeometry, w: float, h: float) -> void:
	var denom := ChartDefs.sanitize_denominator(EditorState.quantize_denominator)
	var step_ms := ChartDefs.snap_ms(ChartData.bpm, denom)

	var visible := geom.visible_time_range()
	var step_start := int(floor(float(visible["start"]) / step_ms))
	var step_end := int(ceil(float(visible["end"]) / step_ms))

	for step in range(step_start, step_end + 1):
		var y := geom.time_to_y(float(step) * step_ms)
		if y < 0.0 or y > h:
			continue

		if step % (denom * 4) == 0:
			ci.draw_line(Vector2(0, y), Vector2(w, y), Color(0.7, 0.7, 0.85, 0.95), 2.5)
		elif step % denom == 0:
			ci.draw_line(Vector2(0, y), Vector2(w, y), Color(0.5, 0.55, 0.7, 0.85), 1.5)
		else:
			ci.draw_line(Vector2(0, y), Vector2(w, y), Color(0.45, 0.5, 0.65, 0.7), 1.0)


# --- 特效 ---

## 特效区间：横跨全部轨道的时间色带，画在网格线之下作为背景层
static func _draw_effects(ci: Control, geom: VisualGeometry, w: float, h: float,
		selected_effect_index: int) -> void:
	var color := ChartDefs.EFFECT_COLOR
	var fill := Color(color.r, color.g, color.b, EFFECT_FILL_ALPHA)
	var border := Color(color.r, color.g, color.b, EFFECT_BORDER_ALPHA)

	for index in range(ChartData.effects.size()):
		var effect: Dictionary = ChartData.effects[index]
		var y_start := geom.time_to_y(float(effect.get("time", 0)))
		var y_end := geom.time_to_y(float(ChartDefs.effect_end_time(effect)))

		if y_start < 0.0 and y_end < 0.0:
			continue
		if y_start > h and y_end > h:
			continue

		# 区间跨界时截断到视口：y_end 是较早的时间（更靠上），y_start 是较晚的时间
		var top := maxf(y_end, 0.0)
		var bottom := minf(y_start, h)
		if bottom <= top:
			continue

		ci.draw_rect(Rect2(0, top, w, bottom - top), fill, true)

		# 开始 / 结束边界线（滚出视口的一侧不画）
		if y_start >= 0.0 and y_start <= h:
			ci.draw_line(Vector2(0, y_start), Vector2(w, y_start), border, 2.0)
		if y_end >= 0.0 and y_end <= h:
			ci.draw_line(Vector2(0, y_end), Vector2(w, y_end), border, 2.0)

		if index == selected_effect_index:
			ci.draw_rect(Rect2(0, top, w, bottom - top), SELECTION_COLOR, false, 2.0)


# --- 音符 ---

## 绘制所有可见音符
static func _draw_notes(ci: Control, geom: VisualGeometry, w: float, h: float,
		selected_index: int) -> void:
	var track_w: float = w / float(ChartDefs.NUM_TRACKS)
	var visible := geom.visible_time_range()
	var view_start := visible["start"] as int
	var view_end := visible["end"] as int

	for index in range(ChartData.notes.size()):
		var note: Dictionary = ChartData.notes[index]
		var head_time := note.get("time", 0) as int
		var tail_time := ChartDefs.note_end_time(note)

		if tail_time < view_start or head_time > view_end:
			continue

		var column := note.get("column", 1) as int
		if column < 1 or column > ChartDefs.NUM_TRACKS:
			continue

		var note_type := note.get("type", "tap") as String
		var y := geom.time_to_y(head_time)
		var tail_y := geom.time_to_y(float(tail_time)) if tail_time != head_time else y

		# 普通音符只看头部；长键只要头/尾任一可见，或整条跨越视口，就要绘制
		if ChartDefs.is_hold(note):
			if y < 0.0 and tail_y < 0.0:
				continue
			if y > h and tail_y > h:
				continue
		elif y < 0.0 or y > h:
			continue

		var mid_x: float = (column - 1) * track_w + track_w / 2.0
		var color := ChartDefs.note_color(note_type)
		var selected := index == selected_index

		# 除长键外都是同一种矩形（heart 与 tap 同形状，只有配色不同）
		if note_type == ChartDefs.NOTE_TYPE_HOLD:
			_draw_hold_note(ci, geom, note, y, mid_x, track_w, color, selected)
		else:
			_draw_single_note(ci, mid_x, y, track_w, color, selected)


static func _draw_single_note(ci: Control, mid_x: float, y: float, track_w: float,
		color: Color, selected: bool) -> void:
	var note_w: float = maxf(track_w * 0.6, MIN_NOTE_WIDTH)
	var note_h: float = maxf(track_w * 0.2, MIN_NOTE_HEIGHT)
	var x0: float = mid_x - note_w / 2.0

	if selected:
		ci.draw_rect(Rect2(x0 - 2, y - note_h / 2.0 - 2, note_w + 4, note_h + 4),
			SELECTION_COLOR, false, 1.5)

	ci.draw_rect(Rect2(x0, y - note_h / 2.0, note_w, note_h), color, true)


static func _draw_hold_note(ci: Control, geom: VisualGeometry, note: Dictionary,
		y: float, mid_x: float, track_w: float, color: Color, selected: bool) -> void:
	var tail_y := geom.time_to_y(float(ChartDefs.note_end_time(note)))
	var bar_top := maxf(tail_y, 0.0)
	var bar_h := maxf(y - bar_top, MIN_NOTE_HEIGHT)
	var bar_w: float = maxf(track_w * 0.4, MIN_NOTE_WIDTH)
	var x0: float = mid_x - bar_w / 2.0

	ci.draw_rect(Rect2(x0, bar_top, bar_w, bar_h), color, true)

	if y >= 0.0:
		var head_size: float = maxf(bar_w * 1.2, 10.0)
		ci.draw_rect(Rect2(mid_x - head_size / 2.0, y - 3, head_size, 6), Color.WHITE, true)

	if tail_y >= 0.0 and tail_y <= ci.size.y:
		var tail_size: float = maxf(bar_w * 0.8, 8.0)
		ci.draw_rect(Rect2(mid_x - tail_size / 2.0, tail_y - 3, tail_size, 6),
			Color(1, 1, 1, 0.6), true)

	if selected:
		ci.draw_rect(Rect2(x0 - 1, bar_top - 4, bar_w + 2, bar_h + 8),
			SELECTION_COLOR, false, 1.5)


# --- 判定线 ---

## 判定线（播放头水平线）
static func _draw_playhead(ci: Control, geom: VisualGeometry, w: float, _h: float) -> void:
	var y := geom.judge_line_y()
	ci.draw_line(Vector2(0, y), Vector2(w, y), PLAYHEAD_COLOR, 2.0)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(0, y - 5), Vector2(0, y + 5), Vector2(6, y)
	]), Color(0.3, 0.7, 1.0, 0.90))
