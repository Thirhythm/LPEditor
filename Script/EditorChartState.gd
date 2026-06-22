extends Node

# ============================================================
# 谱面元信息 (General)
# ============================================================
var title: String = "Untitled"
var producer: String = ""
var vocalist: String = ""
var creator: String = ""
var difficulty: String = "EZ"  # EZ, NM, HD
var version: String = "1.0"
var bpm: float = 80.0
var jacket_path: String = ""
var audio_path: String = ""

# ============================================================
# 存档态（直接对应 RGCBeatmap）
# ============================================================
var timing_points: Array[Dictionary] = []
var notes: Array[Dictionary] = []          # 平铺所有音符，不按轨道分组

# ============================================================
# 编辑态（不存盘）
# ============================================================
var selected_notes: Array[Dictionary] = []
var clipboard: Array[Dictionary] = []
## 时间轴起始时间(ms)，向右递增
var scroll_time: int = 0
## 缩放：每毫秒占多少像素
var px_per_ms: float = 0.3

## 音频时长(ms)，0 表示无边界
var audio_duration_ms: int = 0

## 波形振幅数据（归一化 0.0-1.0），采样率 1000Hz（索引即毫秒）
var waveform_samples: PackedFloat32Array = []

# ============================================================
# 文件路径
# ============================================================

var current_file_path: String = ""

# ============================================================
# 滚动边界
# ============================================================

## 计算最大可滚动时间
func get_max_scroll_time() -> int:
	if audio_duration_ms <= 0:
		if notes.is_empty():
			return 10000
		var max_note_time: int = 0
		for note in notes:
			var t := note.get("time", 0) as int
			if t > max_note_time:
				max_note_time = t
			if note.get("type", "") == "hold" and note.has("duration"):
				var end_t := t + (note.get("duration", 0) as int)
				if end_t > max_note_time:
					max_note_time = end_t
		return maxi(max_note_time + 3000, 1000)
	return audio_duration_ms + 3000

## 限制 scroll_time 到合理范围（判定线时间不得小于 0）
func clamp_scroll() -> void:
	var max_time := get_max_scroll_time()
	scroll_time = clampi(scroll_time, 0, max_time)

# ============================================================
# JSON 序列化 / 反序列化
# ============================================================

## 从 JSON 字典加载谱面数据
func load_from_dict(data: Dictionary) -> void:
	var general: Dictionary = data.get("General", {})
	title = general.get("Title", "Untitled")
	producer = general.get("Producer", "")
	vocalist = general.get("Vocalist", "")
	creator = general.get("Creator", "")
	difficulty = general.get("Difficulty", "EZ")
	version = general.get("Version", "1.0")
	bpm = general.get("BPM", 80.0)
	
	var hit_objects: Array = data.get("HitObjects", [])
	notes.clear()
	for obj in hit_objects:
		notes.append(obj.duplicate(true))
	
	selected_notes.clear()
	timing_points.clear()

## 导出为 JSON 字典
func to_dict() -> Dictionary:
	var general := {
		"Title": title,
		"Producer": producer,
		"Vocalist": vocalist,
		"Creator": creator,
		"Difficulty": difficulty,
		"Version": version,
		"BPM": bpm
	}
	
	var hit_objects: Array[Dictionary] = []
	for note in notes:
		hit_objects.append(note.duplicate(true))
	
	return {
		"General": general,
		"HitObjects": hit_objects
	}

## 新建谱面（重置所有数据）
func new_chart() -> void:
	title = "Untitled"
	producer = ""
	vocalist = ""
	creator = ""
	difficulty = "EZ"
	version = "1.0"
	bpm = 80.0
	jacket_path = ""
	audio_path = ""
	timing_points.clear()
	notes.clear()
	selected_notes.clear()
	clipboard.clear()
	scroll_time = 0
	px_per_ms = 0.3
	audio_duration_ms = 0
	waveform_samples.clear()
	current_file_path = ""
