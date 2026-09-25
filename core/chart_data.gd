@tool
class_name ChartData
extends RefCounted

## 谱面文档：元数据 + 音符 + 音频分析结果 + 序列化。
##
## 全部字段/方法都是静态的（`ChartData.title`、`ChartData.notes`），因此：
##   * 不依赖 autoload 注册，编辑器里改完即可解析，也无需重启编辑器；
##   * 不依赖场景树，可被 core / audio / ui 任意层直接调用，也便于单元测试。
## 编辑器会话状态（视口、量化、选区、撤销栈）见 `EditorState`。

# --- 元数据 ---
static var title: String = "Untitled"
static var producer: String = ""
static var vocalist: String = ""
static var creator: String = ""
static var difficulty: String = ChartDefs.DEFAULT_DIFFICULTY
static var version: String = ChartDefs.DEFAULT_VERSION
static var bpm: float = ChartDefs.DEFAULT_BPM
static var jacket_path: String = ""
static var audio_path: String = ""

# --- 谱面数据 ---
static var timing_points: Array[Dictionary] = []	# 变速点
static var notes: Array[Dictionary] = []			# 音符列表

# --- 音频分析结果（由 AudioManager 填充）---
static var audio_duration_ms: int = 0
static var waveform_samples: PackedFloat32Array = []	# 降采样波形，每元素为该毫秒峰值 [0,1]

# --- 当前文件 ---
static var current_file_path: String = ""


static func has_audio() -> bool:
	return not audio_path.is_empty()


static func has_jacket() -> bool:
	return not jacket_path.is_empty()


## 清空音频分析结果（换歌 / 新建谱面时调用）
static func clear_audio_analysis() -> void:
	audio_duration_ms = 0
	waveform_samples = PackedFloat32Array()


# --- 生命周期 ---

## 重置为新谱面
static func new_chart() -> void:
	title = ChartDefs.DEFAULT_TITLE
	producer = ""
	vocalist = ""
	creator = ""
	difficulty = ChartDefs.DEFAULT_DIFFICULTY
	version = ChartDefs.DEFAULT_VERSION
	bpm = ChartDefs.DEFAULT_BPM
	jacket_path = ""
	audio_path = ""
	timing_points.clear()
	notes.clear()
	current_file_path = ""
	clear_audio_analysis()


# --- 序列化 ---

## 从 JSON dict 加载谱面
static func load_from_dict(data: Dictionary) -> void:
	var general: Dictionary = data.get("General", {})
	title = general.get("Title", ChartDefs.DEFAULT_TITLE)
	producer = general.get("Producer", "")
	vocalist = general.get("Vocalist", "")
	creator = general.get("Creator", "")
	difficulty = general.get("Difficulty", ChartDefs.DEFAULT_DIFFICULTY)
	version = general.get("Version", ChartDefs.DEFAULT_VERSION)
	bpm = general.get("BPM", ChartDefs.DEFAULT_BPM)
	jacket_path = general.get("JacketPath", "")
	audio_path = general.get("AudioPath", "")

	notes.clear()
	for obj in data.get("HitObjects", []):
		notes.append(obj.duplicate(true))

	timing_points.clear()


## 将当前谱面序列化为 JSON dict
static func to_dict() -> Dictionary:
	var general := {
		"Title": title,
		"Producer": producer,
		"Vocalist": vocalist,
		"Creator": creator,
		"Difficulty": difficulty,
		"Version": version,
		"BPM": bpm,
		"JacketPath": jacket_path,
		"AudioPath": audio_path,
	}

	var hit_objects: Array[Dictionary] = []
	for note in notes:
		hit_objects.append(note.duplicate(true))

	return {
		"General": general,
		"HitObjects": hit_objects,
	}


# --- 查询 ---

## 视口可滚动的最大时间：有音频取音频时长 + 尾部余量，否则取最晚音符 + 尾部余量
static func get_max_scroll_time() -> int:
	if audio_duration_ms > 0:
		return audio_duration_ms + ChartDefs.SCROLL_TAIL_MS
	if notes.is_empty():
		return ChartDefs.MIN_SCROLL_TIME_MS

	var latest: int = 0
	for note in notes:
		latest = maxi(latest, ChartDefs.note_end_time(note))
	return maxi(latest + ChartDefs.SCROLL_TAIL_MS, 1000)


# --- 撤销快照 ---

## 文档部分的状态快照（编辑器还会合并自己的会话字段）
static func capture_snapshot() -> Dictionary:
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
	}


static func restore_snapshot(state: Dictionary) -> void:
	title = state.get("title", title)
	producer = state.get("producer", producer)
	vocalist = state.get("vocalist", vocalist)
	creator = state.get("creator", creator)
	difficulty = state.get("difficulty", difficulty)
	version = state.get("version", version)
	bpm = state.get("bpm", bpm)
	jacket_path = state.get("jacket_path", jacket_path)
	audio_path = state.get("audio_path", audio_path)

	notes.clear()
	for note in state.get("notes", []):
		notes.append(note)
