extends Node

# --- 谱面元数据 ---
var title: String = "Untitled"
var producer: String = ""
var vocalist: String = ""
var creator: String = ""
var difficulty: String = "EZ"
var version: String = "1.0"
var bpm: float = 80.0
var jacket_path: String = ""
var audio_path: String = ""

# --- 谱面数据 ---
var timing_points: Array[Dictionary] = []	# 变速点
var notes: Array[Dictionary] = []			# 音符列表

# --- 编辑器状态 ---
var selected_notes: Array[Dictionary] = []
var clipboard: Array[Dictionary] = []
var scroll_time: int = 0			# 当前滚动时间 (ms)，决定视口起点
var px_per_ms: float = 0.3			# 像素/毫秒，控制缩放
var quantize_denominator: int = 4		# 量化分母 (4=1/4拍, 默认)
var snap_enabled: bool = true			# 编辑时音符吸附开关

# --- 音频数据 ---
var audio_duration_ms: int = 0
var waveform_samples: PackedFloat32Array = []	# 降采样后的波形数据，每元素为该毫秒的峰值 [0,1]

var current_file_path: String = ""

# --- 撤销/重做 ---
const MAX_HISTORY: int = 100
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _is_undoing: bool = false

func push_undo_state() -> void:
	if _is_undoing:
		return
	var state := _capture_state()
	_undo_stack.append(state)
	_redo_stack.clear()
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()

func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_is_undoing = true
	var current := _capture_state()
	_redo_stack.append(current)
	var prev = _undo_stack.pop_back()
	_restore_state(prev)
	_is_undoing = false
	return true

func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	_is_undoing = true
	var current := _capture_state()
	_undo_stack.append(current)
	var next = _redo_stack.pop_back()
	_restore_state(next)
	_is_undoing = false
	return true

func clear_undo_history() -> void:
	_undo_stack.clear()
	_redo_stack.clear()

func _capture_state() -> Dictionary:
	var notes_copy: Array[Dictionary] = []
	for note in notes:
		notes_copy.append(note.duplicate(true))
	return {
		"notes": notes_copy,
		"title": title,
		"producer": producer,
		"vocalist": vocalist,
		"creator": creator,
		"difficulty": difficulty,
		"version": version,
		"bpm": bpm,
		"jacket_path": jacket_path,
		"audio_path": audio_path,
		"quantize_denominator": quantize_denominator,
		"snap_enabled": snap_enabled,
	}

func _restore_state(state: Dictionary) -> void:
	title = state["title"]
	producer = state["producer"]
	vocalist = state["vocalist"]
	creator = state["creator"]
	difficulty = state["difficulty"]
	version = state["version"]
	bpm = state["bpm"]
	jacket_path = state["jacket_path"]
	audio_path = state["audio_path"]
	quantize_denominator = state["quantize_denominator"]
	snap_enabled = state["snap_enabled"]
	notes.clear()
	for note_dict in state["notes"]:
		notes.append(note_dict)
	selected_notes.clear()

# 计算最大可滚动时间：有音频时取音频时长+3s，否则取最晚音符+3s
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

# 将 scroll_time 限制在合法范围内
func clamp_scroll() -> void:
	scroll_time = clampi(scroll_time, 0, get_max_scroll_time())

# 从 JSON dict 加载谱面
func load_from_dict(data: Dictionary) -> void:
	var general: Dictionary = data.get("General", {})
	title = general.get("Title", "Untitled")
	producer = general.get("Producer", "")
	vocalist = general.get("Vocalist", "")
	creator = general.get("Creator", "")
	difficulty = general.get("Difficulty", "EZ")
	version = general.get("Version", "1.0")
	bpm = general.get("BPM", 80.0)
	jacket_path = general.get("JacketPath", "")
	audio_path = general.get("AudioPath", "")

	var hit_objects: Array = data.get("HitObjects", [])
	notes.clear()
	for obj in hit_objects:
		notes.append(obj.duplicate(true))

	selected_notes.clear()
	timing_points.clear()

# 将当前谱面序列化为 JSON dict
func to_dict() -> Dictionary:
	var general := {
		"Title": title,
		"Producer": producer,
		"Vocalist": vocalist,
		"Creator": creator,
		"Difficulty": difficulty,
		"Version": version,
		"BPM": bpm,
		"JacketPath": jacket_path,
		"AudioPath": audio_path
	}

	var hit_objects: Array[Dictionary] = []
	for note in notes:
		hit_objects.append(note.duplicate(true))

	return {
		"General": general,
		"HitObjects": hit_objects
	}

# 重置为新谱面
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
	quantize_denominator = 4
	snap_enabled = true
	audio_duration_ms = 0
	waveform_samples.clear()
	current_file_path = ""
