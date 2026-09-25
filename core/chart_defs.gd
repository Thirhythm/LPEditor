@tool
class_name ChartDefs
extends RefCounted

## 谱面与轨道的「纯定义」层：常量 + 无副作用的换算函数。
##
## 这里不持有任何状态，也不引用场景树，因此 core / audio / ui 各层都可以安全复用，
## 避免轨道数、配色、量化表、拍点换算在多个控件里各写一份。

# --- 轨道 ---
const NUM_TRACKS: int = 4
const TRACK_COLORS: Array[Color] = [
	Color(0.25, 0.40, 0.70),
	Color(0.70, 0.45, 0.20),
	Color(0.25, 0.65, 0.40),
	Color(0.70, 0.25, 0.45),
]

# --- 音符 ---
const NOTE_TYPES: Array[String] = ["tap", "drag", "release", "hold", "heart"]
const NOTE_TYPE_LABELS: Array[String] = ["Tap", "Drag", "Release", "Hold", "Heart"]
const NOTE_TYPE_HOLD: String = "hold"
const NOTE_TYPE_HEART: String = "heart"
const HOLD_DEFAULT_DURATION_MS: int = 500
## heart 音符默认目标轨（谱面格式要求 1..NUM_TRACKS）
const HEART_DEFAULT_MAP: Array[int] = [1, 2, 3, 4]

# --- 谱面元数据 ---
const DEFAULT_TITLE: String = "Untitled"
const DIFFICULTIES: Array[String] = ["EZ", "NM", "HD"]
const DEFAULT_DIFFICULTY: String = "EZ"
const DEFAULT_VERSION: String = "1.0"
const DEFAULT_BPM: float = 80.0

# --- 量化 ---
## OptionButton 的索引顺序，同时也是面板显示顺序
const QUANTIZE_DENOMINATORS: Array[int] = [2, 4, 5, 6, 7, 8, 9, 10, 12, 16, 32, 48]
const DEFAULT_QUANTIZE_DENOMINATOR: int = 4

# --- 视口缩放 ---
const DEFAULT_PX_PER_MS: float = 0.3
const MIN_PX_PER_MS: float = 0.02
const MAX_PX_PER_MS: float = 5.0
## 无音频时，视口至少留出的时间余量
const SCROLL_TAIL_MS: int = 3000
const MIN_SCROLL_TIME_MS: int = 10000


static func sanitize_bpm(value: float) -> float:
	return value if value > 0.0 else DEFAULT_BPM


static func sanitize_denominator(value: int) -> int:
	return value if value > 0 else DEFAULT_QUANTIZE_DENOMINATOR


## 一拍（四分音符）时长，单位 ms
static func beat_ms(bpm: float) -> float:
	return 60000.0 / sanitize_bpm(bpm)


## 当前量化下的最小吸附步长，单位 ms
static func snap_ms(bpm: float, denominator: int) -> float:
	return beat_ms(bpm) / float(sanitize_denominator(denominator))


## 把时间吸附到量化网格（四舍五入到最近网格线）
static func snap_time(time_ms: int, bpm: float, denominator: int) -> int:
	var step := snap_ms(bpm, denominator)
	return int(round(float(time_ms) / step) * step)


static func quantize_index_for(denominator: int) -> int:
	var idx := QUANTIZE_DENOMINATORS.find(denominator)
	return idx if idx >= 0 else QUANTIZE_DENOMINATORS.find(DEFAULT_QUANTIZE_DENOMINATOR)


static func quantize_denominator_at(index: int) -> int:
	if index < 0 or index >= QUANTIZE_DENOMINATORS.size():
		return DEFAULT_QUANTIZE_DENOMINATOR
	return QUANTIZE_DENOMINATORS[index]


static func difficulty_index(difficulty: String) -> int:
	var idx := DIFFICULTIES.find(difficulty)
	return idx if idx >= 0 else 0


static func is_hold(note: Dictionary) -> bool:
	return note.get("type", "") == NOTE_TYPE_HOLD and note.has("duration")


static func is_heart(note: Dictionary) -> bool:
	return note.get("type", "") == NOTE_TYPE_HEART


## 音符占用的结束时间（hold 为头 + 时长，其余等于头时间）
static func note_end_time(note: Dictionary) -> int:
	var start := note.get("time", 0) as int
	if is_hold(note):
		return start + (note.get("duration", 0) as int)
	return start


static func note_color(type: String) -> Color:
	match type:
		"tap":     return Color(0.3, 0.6, 1.0)
		"drag":    return Color(1.0, 0.85, 0.2)
		"release": return Color(1.0, 0.3, 0.3)
		"hold":    return Color(0.3, 1.0, 0.5)
		"heart":   return Color(1.0, 0.3, 1.0)
		_:         return Color(0.7, 0.7, 0.7)


## 工具面板的「音符类型」索引（0 = 选择模式，之后与 NOTE_TYPES 依次对齐）
static func tool_note_type(index: int) -> String:
	var type_index := index - 1
	if type_index < 0 or type_index >= NOTE_TYPES.size():
		return ""
	return NOTE_TYPES[type_index]


## 新建一个音符字典（hold / heart 会带上各自附加字段）
static func make_note(type: String, time_ms: int, column: int) -> Dictionary:
	var note := {
		"type": type if not type.is_empty() else NOTE_TYPES[0],
		"time": time_ms,
		"column": column,
	}
	if note["type"] == NOTE_TYPE_HOLD:
		note["duration"] = HOLD_DEFAULT_DURATION_MS
	elif note["type"] == NOTE_TYPE_HEART:
		note["map"] = HEART_DEFAULT_MAP.duplicate()
	return note


## 校验谱面是否可以导出，返回缺失项的中文说明列表（空表示通过）
static func missing_export_fields(chart: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var title := chart.get("title", "") as String
	if title.is_empty() or title == DEFAULT_TITLE:
		missing.append("标题")
	if (chart.get("audio_path", "") as String).is_empty():
		missing.append("音频")
	if (chart.get("jacket_path", "") as String).is_empty():
		missing.append("曲绘")
	return missing
