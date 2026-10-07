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
static var artist: String = ""
static var vocalist: String = ""
static var illustrator: String = ""
static var creator: String = ""
static var difficulty: String = ChartDefs.DEFAULT_DIFFICULTY
static var version: String = ChartDefs.DEFAULT_VERSION
static var bpm: float = ChartDefs.DEFAULT_BPM
static var jacket_path: String = ""
static var audio_path: String = ""

# --- 预览区与解锁条件（写进 General）---
static var preview_ms: int = 0			# 试听开始时间
static var preview_end_ms: int = 0		# 试听结束时间
static var crystal: int = 0				# 解锁本曲需要的虚拟货币
static var chapter: int = ChartDefs.DEFAULT_CHAPTER

# --- 谱面数据 ---
static var timing_points: Array[Dictionary] = []	# 变速点
static var notes: Array[Dictionary] = []			# 音符列表
static var effects: Array[Dictionary] = []			# 特效列表（导出为与 HitObjects 同级的 Effects）

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
	artist = ""
	vocalist = ""
	illustrator = ""
	creator = ""
	difficulty = ChartDefs.DEFAULT_DIFFICULTY
	version = ChartDefs.DEFAULT_VERSION
	bpm = ChartDefs.DEFAULT_BPM
	jacket_path = ""
	audio_path = ""
	preview_ms = 0
	preview_end_ms = 0
	crystal = 0
	chapter = ChartDefs.DEFAULT_CHAPTER
	timing_points.clear()
	notes.clear()
	effects.clear()
	current_file_path = ""
	clear_audio_analysis()


# --- 序列化 ---

## 从 JSON dict 加载谱面。
##
## `chart_path` 是这份 JSON 来自哪个文件：谱面里记的曲绘 / 音频是**相对该文件**的路径，
## 要在这里还原成当前机器上的路径，面板与播放器才能用。不传就按原样收下。
static func load_from_dict(data: Dictionary, chart_path: String = "") -> void:
	var general: Dictionary = data.get("General", {})
	title = general.get("Title", ChartDefs.DEFAULT_TITLE)
	# Producer 是旧格式的字段名，读不到 Artist 时回退到它，旧谱面不至于丢作者
	artist = general.get("Artist", general.get("Producer", ""))
	vocalist = general.get("Vocalist", "")
	illustrator = general.get("Illustrator", "")
	creator = general.get("Creator", "")
	difficulty = general.get("Difficulty", ChartDefs.DEFAULT_DIFFICULTY)
	version = general.get("Version", ChartDefs.DEFAULT_VERSION)
	bpm = general.get("BPM", ChartDefs.DEFAULT_BPM)
	jacket_path = ChartDefs.to_absolute_asset_path(general.get("JacketPath", ""), chart_path)
	audio_path = ChartDefs.to_absolute_asset_path(general.get("AudioPath", ""), chart_path)
	preview_ms = ChartDefs.sanitize_int(general.get("Preview"), 0, 0, ChartDefs.MAX_PREVIEW_MS)
	preview_end_ms = ChartDefs.sanitize_int(
		general.get("PreviewEnd"), 0, 0, ChartDefs.MAX_PREVIEW_MS)
	crystal = ChartDefs.sanitize_int(general.get("Crystal"), 0, 0, ChartDefs.MAX_CRYSTAL)
	chapter = ChartDefs.sanitize_int(general.get("Chapter"), ChartDefs.DEFAULT_CHAPTER,
		ChartDefs.MIN_CHAPTER, ChartDefs.MAX_CHAPTER)

	notes.clear()
	for obj in data.get("HitObjects", []):
		var note: Dictionary = obj.duplicate(true)
		# 心键的 map 字段已废弃，载入旧谱面时一并剔除，重新保存即升级成新格式
		note.erase(ChartDefs.NOTE_LEGACY_MAP_FIELD)
		notes.append(note)

	effects.clear()
	for obj in data.get("Effects", []):
		effects.append(obj.duplicate(true))

	timing_points.clear()


## 将当前谱面序列化为 JSON dict。
##
## `chart_path` 是这份 JSON 将要写到的文件：曲绘 / 音频按**相对该文件**的形式记录，
## 谱面连同素材一起搬走（或换盘符根目录）后仍然指得到。保存时传**目标**路径 ——
## 另存为的目标可能和 `current_file_path` 不同，所以不在这里读那个字段。
static func to_dict(chart_path: String = "") -> Dictionary:
	var general := {
		"Title": title,
		"Artist": artist,
		"Vocalist": vocalist,
		"Illustrator": illustrator,
		"Creator": creator,
		"Difficulty": difficulty,
		"Version": version,
		"BPM": bpm,
		"Preview": preview_ms,
		"PreviewEnd": preview_end_ms,
		"Crystal": crystal,
		"Chapter": chapter,
		"JacketPath": ChartDefs.to_relative_asset_path(jacket_path, chart_path),
		"AudioPath": ChartDefs.to_relative_asset_path(audio_path, chart_path),
	}

	var hit_objects: Array[Dictionary] = []
	for note in notes:
		hit_objects.append(note.duplicate(true))

	var effect_objects: Array[Dictionary] = []
	for effect in effects:
		effect_objects.append(effect.duplicate(true))

	return {
		"General": general,
		"HitObjects": hit_objects,
		"Effects": effect_objects,
	}


# --- 查询 ---

## 视口可滚动的最大时间：有音频取音频时长 + 尾部余量，否则取最晚音符/特效 + 尾部余量
static func get_max_scroll_time() -> int:
	if audio_duration_ms > 0:
		return audio_duration_ms + ChartDefs.SCROLL_TAIL_MS
	if notes.is_empty() and effects.is_empty():
		return ChartDefs.MIN_SCROLL_TIME_MS

	var latest: int = 0
	for note in notes:
		latest = maxi(latest, ChartDefs.note_end_time(note))
	for effect in effects:
		latest = maxi(latest, ChartDefs.effect_end_time(effect))
	return maxi(latest + ChartDefs.SCROLL_TAIL_MS, 1000)


# --- 撤销快照 ---

## 文档部分的状态快照（编辑器还会合并自己的会话字段）
static func capture_snapshot() -> Dictionary:
	var notes_copy: Array[Dictionary] = []
	for note in notes:
		notes_copy.append(note.duplicate(true))
	var effects_copy: Array[Dictionary] = []
	for effect in effects:
		effects_copy.append(effect.duplicate(true))
	return {
		"notes": notes_copy,
		"effects": effects_copy,
		"title": title,
		"artist": artist,
		"vocalist": vocalist,
		"illustrator": illustrator,
		"creator": creator,
		"difficulty": difficulty,
		"version": version,
		"bpm": bpm,
		"jacket_path": jacket_path,
		"audio_path": audio_path,
		"preview_ms": preview_ms,
		"preview_end_ms": preview_end_ms,
		"crystal": crystal,
		"chapter": chapter,
	}


static func restore_snapshot(state: Dictionary) -> void:
	title = state.get("title", title)
	artist = state.get("artist", artist)
	vocalist = state.get("vocalist", vocalist)
	illustrator = state.get("illustrator", illustrator)
	creator = state.get("creator", creator)
	difficulty = state.get("difficulty", difficulty)
	version = state.get("version", version)
	bpm = state.get("bpm", bpm)
	jacket_path = state.get("jacket_path", jacket_path)
	audio_path = state.get("audio_path", audio_path)
	preview_ms = state.get("preview_ms", preview_ms)
	preview_end_ms = state.get("preview_end_ms", preview_end_ms)
	crystal = state.get("crystal", crystal)
	chapter = state.get("chapter", chapter)

	notes.clear()
	for note in state.get("notes", []):
		notes.append(note)

	effects.clear()
	for effect in state.get("effects", []):
		effects.append(effect)
