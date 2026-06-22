extends Node
# 编辑器专用计算器

var zoom: float = 1.0          # 横向缩放（像素/秒）
var scroll_x: float = 0.0      # 水平滚动偏移

@onready var note_pos_calc: Node = $"../NotePositionCalculatior"
func time_to_x(time_ms: int) -> float:
	# 调用 scroll_to_pos(time) 得到时间轴像素位置
	# 再乘以 zoom，减去 scroll_x 得到屏幕 x
	var timeline_pos: float = note_pos_calc.scroll_to_pos(time_ms)
	return timeline_pos * zoom - scroll_x

func x_to_time(x: float) -> int:
	var timeline_pos: float = (x + scroll_x) / zoom
	return note_pos_calc.scroll_to_time(timeline_pos, false)
