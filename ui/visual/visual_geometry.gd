class_name VisualGeometry
extends RefCounted

## 轨道编辑区的坐标换算：时间 ↔ 屏幕 Y、X ↔ 轨道号、可见时间范围、量化吸附。
##
## 只依赖控件尺寸与 `EditorState` / `ChartData` 的公开字段，因此可以脱离场景单独测试。
## 绘制（visual_renderer.gd）与交互（visual.gd）共用这一份换算，避免两处各写一遍。

const JUDGE_LINE_RATIO: float = 0.85

var _control: Control


func _init(control: Control) -> void:
	_control = control


func control_size() -> Vector2:
	return _control.size


## 判定线 Y 坐标（轨道底部对齐线，约在控件高度的 85% 处）
func judge_line_y() -> float:
	return _control.size.y * JUDGE_LINE_RATIO


## 时间 → 屏幕 Y（从下往上增长：时间越大越靠上）
func time_to_y(time_ms: float) -> float:
	return judge_line_y() - (time_ms - EditorState.scroll_time) * EditorState.px_per_ms


## 屏幕 Y → 时间
func y_to_time(y: float) -> int:
	return EditorState.scroll_time + int((judge_line_y() - y) / EditorState.px_per_ms)


func track_width() -> float:
	return _control.size.x / float(ChartDefs.NUM_TRACKS)


## 轨道 X 范围：{ left, right, mid }
func track_to_x_range(col: int) -> Dictionary:
	var track_w := track_width()
	var x0 := (col - 1) * track_w
	return {"left": x0, "right": x0 + track_w, "mid": x0 + track_w / 2.0}


## 屏幕 X → 轨道编号（1..NUM_TRACKS）
func x_to_track(x: float) -> int:
	return clampi(int(x / track_width()) + 1, 1, ChartDefs.NUM_TRACKS)


## 当前视口可见的时间范围：{ start, end }
func visible_time_range() -> Dictionary:
	var px := maxf(EditorState.px_per_ms, 0.001)
	var judge_y := judge_line_y()
	return {
		"start": EditorState.scroll_time - int((_control.size.y - judge_y) / px),
		"end": EditorState.scroll_time + int(judge_y / px),
	}


## 量化吸附（吸附关闭时原样返回）
func snap_time(time_ms: int) -> int:
	return EditorState.snap_time(time_ms)
