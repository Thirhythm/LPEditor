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
## 已废弃的心键字段名：旧谱面里的 `map` 会在载入与类型归一化时被清掉
const NOTE_LEGACY_MAP_FIELD: String = "map"

# --- 特效 ---
## 可用的特效种类；新增种类时同步添加对应的标签与默认值
const EFFECT_TYPES: Array[String] = ["change"]
const EFFECT_TYPE_CHANGE: String = "change"
## change 特效的 changed 列表长度固定为轨道数，每项是 1..NUM_TRACKS 的目标轨
const EFFECT_CHANGED_SIZE: int = NUM_TRACKS
const EFFECT_DEFAULT_CHANGED: Array[int] = [1, 2, 3, 4]
const EFFECT_DEFAULT_DURATION_MS: int = 1000
const EFFECT_MIN_DURATION_MS: int = 1
## 轨道区标记特效区间的颜色
const EFFECT_COLOR: Color = Color(0.62, 0.40, 0.95)

# --- 谱面元数据 ---
const DEFAULT_TITLE: String = "Untitled"
const DIFFICULTIES: Array[String] = ["EZ", "NM", "HD"]
const DEFAULT_DIFFICULTY: String = "EZ"
const DEFAULT_VERSION: String = "1.0"
const DEFAULT_BPM: float = 80.0
const DEFAULT_CHAPTER: int = 1
## 元数据里几个整数字段的取值范围：属性面板与载入收敛共用同一组，
## 免得出现「文档里是 -3、面板显示 1」这种对不上的情况
const MAX_PREVIEW_MS: int = 99999999
const MAX_CRYSTAL: int = 999999
const MIN_CHAPTER: int = 1
const MAX_CHAPTER: int = 9999

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


## 把从 JSON 读来的值收敛成合法整数：null / 非数字回退到 fallback，浮点先钳制到
## [minimum, maximum] 再截断。不能直接 int()：int(null) 会抛错中断整个载入，
## 而超范围的浮点转 int 会溢出成一个巨大的乱值。
static func sanitize_int(value: Variant, fallback: int, minimum: int, maximum: int) -> int:
	if not (value is int or value is float):
		return fallback
	return clampi(int(clampf(float(value), float(minimum), float(maximum))), minimum, maximum)


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
		"heart":   return Color8(0x70, 0x0F, 0x0F)	# #700f0f
		_:         return Color(0.7, 0.7, 0.7)


## 工具面板的「音符类型」索引（0 = 选择模式，之后与 NOTE_TYPES 依次对齐）
static func tool_note_type(index: int) -> String:
	var type_index := index - 1
	if type_index < 0 or type_index >= NOTE_TYPES.size():
		return ""
	return NOTE_TYPES[type_index]


## 属性面板「音符类型」下拉的索引（与 NOTE_TYPES 顺序一致，0 = tap）
static func note_type_index(type: String) -> int:
	var idx := NOTE_TYPES.find(type)
	return idx if idx >= 0 else 0


## 属性面板「音符类型」下拉索引对应的类型名（越界回退到 NOTE_TYPES[0]）
static func note_type_at(index: int) -> String:
	if index < 0 or index >= NOTE_TYPES.size():
		return NOTE_TYPES[0]
	return NOTE_TYPES[index]

# 整理音符的「类型专属字段」：
##   * 长键：补上缺失的 duration；
##   * 其余类型：删掉 duration；
##   * 心键：不再有任何专属字段，顺手清掉旧谱面残留的 map。
## 面板与测试共用这条规则，不必各自记一遍。
static func normalize_note_fields(note: Dictionary) -> void:
	if note.get("type", "") == NOTE_TYPE_HOLD:
		if not note.has("duration"):
			note["duration"] = HOLD_DEFAULT_DURATION_MS
	else:
		note.erase("duration")
	if is_heart(note):
		note.erase(NOTE_LEGACY_MAP_FIELD)


#
## 新建一个音符字典（长键额外带上 duration）
static func make_note(type: String, time_ms: int, column: int) -> Dictionary:
	var note := {
		"type": type if not type.is_empty() else NOTE_TYPES[0],
		"time": time_ms,
		"column": column,
	}
	if note["type"] == NOTE_TYPE_HOLD:
		note["duration"] = HOLD_DEFAULT_DURATION_MS
	return note


# --- 特效 ---

## 特效区间的结束时间（特效的 time 是开始，duration 是持续时间）
static func effect_end_time(effect: Dictionary) -> int:
	return (effect.get("time", 0) as int) + (effect.get("duration", 0) as int)


static func effect_type_index(type: String) -> int:
	var idx := EFFECT_TYPES.find(type)
	return idx if idx >= 0 else 0


static func effect_type_at(index: int) -> String:
	if index < 0 or index >= EFFECT_TYPES.size():
		return EFFECT_TYPES[0]
	return EFFECT_TYPES[index]


## 把任意长度 / 越界的轨道变换列表整理成恰好 EFFECT_CHANGED_SIZE 项、取值 1..NUM_TRACKS
static func normalize_changed(values: Array) -> Array[int]:
	var result: Array[int] = []
	for i in range(EFFECT_CHANGED_SIZE):
		if i < values.size():
			result.append(clampi(int(values[i]), 1, NUM_TRACKS))
		else:
			result.append(EFFECT_DEFAULT_CHANGED[i])
	return result


## 新建一个特效字典，字段顺序与导出格式一致
static func make_effect(type: String, time_ms: int,
		duration_ms: int = EFFECT_DEFAULT_DURATION_MS) -> Dictionary:
	return {
		"type": type if not type.is_empty() else EFFECT_TYPES[0],
		"time": time_ms,
		"changed": EFFECT_DEFAULT_CHANGED.duplicate(),
		"duration": maxi(duration_ms, EFFECT_MIN_DURATION_MS),
	}


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
