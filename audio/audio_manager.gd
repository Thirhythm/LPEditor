extends Node
class_name AudioManager

## 音频播放控制。
##
## 职责边界：
##   * 播放 / 暂停 / 定位 / 播放计时——由 AudioStreamPlayer 完成；
##   * 音符到达判定线的音效（advance_note_sfx），判定逻辑本身在 ChartDefs；
##   * 音频分析结果（时长、波形）写入 ChartData，供 ruler 绘制与滚动范围计算；
##   * WAV 字节解析交给 core/wav_reader.gd，这里不再出现 RIFF 细节。

## 音符到达判定线时播放的音效（已导入的 res:// 资源，不走 WavReader 的文件系统路径）
const NOTE_SFX: AudioStream = preload("res://assets/audio/note.wav")

## 播放器节点由主场景中的 AudioManager/Player 节点提供
@onready var player: AudioStreamPlayer = $Player
## 音效播放器：与音乐分开，避免互相打断
@onready var _sfx: AudioStreamPlayer = $Sfx

var playing: bool = false
var finished: bool = false			# 上次播放是否播到音频末尾自然结束（暂停/停止/定位都会清除）
var _start_time_ms: int = 0		# 本次播放开始时的系统时间 (Time.get_ticks_msec())
var _start_offset_ms: int = 0		# 本次播放从音频的哪个位置开始 (ms)
## 上一帧报出去的播放时间 (ms)；-1 表示没在跟踪（暂停/停止/播完）。
## 只在这里随播放计时基准一起重置，调用方不用自己记，改计时的地方漏改也不会误触发。
var _sfx_cursor_ms: int = -1


func _ready() -> void:
	_sfx.stream = NOTE_SFX


## 返回从播放开始到现在的经过时间 (ms)。
## 用 Time.get_ticks_msec() 而非 get_playback_position()，避开音频缓冲区导致的抖动。
func elapsed_time_ms() -> int:
	return _start_offset_ms + (Time.get_ticks_msec() - _start_time_ms)


## 从指定时间位置开始播放；无法取得音频流时返回 false
func start_playback(from_ms: int) -> bool:
	var stream := _open_stream()
	if stream == null:
		return false

	player.stream = stream
	player.play(float(from_ms) / 1000.0)
	_start_time_ms = Time.get_ticks_msec()
	_start_offset_ms = from_ms
	playing = true
	finished = false
	# 起点自身不算「到达」：从 from_ms 开始播放时，压在判定线上的那个音符不再补响
	_sfx_cursor_ms = from_ms
	return true


func pause_playback() -> void:
	player.stop()
	playing = false
	finished = false
	_sfx_cursor_ms = -1


func stop_playback() -> void:
	player.stop()
	playing = false
	finished = false
	_sfx_cursor_ms = -1


## 播放自然结束（播到音频末尾）：结束播放状态并记录 finished，
## 供调用方在下次按下播放键时决定是否回到开头
func mark_finished() -> void:
	player.stop()
	playing = false
	finished = true
	_sfx_cursor_ms = -1


## 清除"自然结束"标记（用户重新定位播放头/换歌后，播放应以其当前位置为准）
func clear_finished() -> void:
	finished = false


## 播放中跳转到指定位置
func seek(from_ms: int) -> void:
	player.play(float(from_ms) / 1000.0)
	_start_time_ms = Time.get_ticks_msec()
	_start_offset_ms = from_ms
	finished = false
	# 与 start_playback 同理：跳过去的那一段不补响
	_sfx_cursor_ms = from_ms


## 把播放位置推进到 to_ms，播放本帧新跨过判定线的音符音效，返回触发的音符数。
##
## 只有播放中才该调用（暂停 / 停止时游标是 -1，这里会静默地重新对齐、不发声）。
## 一帧跨过多个音符时只出一声：同一个播放器重复 play 只会从头重放，
## 同刻的多个音符本来也该听成一次敲击。
func advance_note_sfx(to_ms: int, notes: Array[Dictionary]) -> int:
	if _sfx_cursor_ms < 0:
		_sfx_cursor_ms = to_ms
		return 0

	var hits := ChartDefs.note_hits_in_range(notes, _sfx_cursor_ms, to_ms)
	_sfx_cursor_ms = to_ms
	if hits > 0:
		_sfx.play()
	return hits


## 加载当前音频：优先直接解析 WAV（绕过 .import），失败时回退到 Godot 标准导入流。
## 结果写入 ChartData.audio_duration_ms / ChartData.waveform_samples。
func load_audio() -> bool:
	ChartData.clear_audio_analysis()
	if not ChartData.has_audio():
		return false

	var wav := WavReader.read(ChartData.audio_path)
	if wav["ok"]:
		ChartData.audio_duration_ms = wav["duration_ms"]
		ChartData.waveform_samples = wav["waveform"]
		return true

	return _load_imported_stream()


# --- 内部 ---

## 取得可播放的音频流：WAV 直接解析 → 否则用 Godot 内置加载器
func _open_stream() -> AudioStream:
	var wav := WavReader.to_stream(ChartData.audio_path)
	if wav != null:
		return wav
	return _open_builtin_stream()


func _open_builtin_stream() -> AudioStream:
	var path := ChartData.audio_path
	if path.is_empty() or not FileAccess.file_exists(path):
		return null

	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		_:
			return null


## 标准导入流的回退路径：取时长，能取到波形则一并填充
func _load_imported_stream() -> bool:
	var stream := _open_builtin_stream()
	if stream == null:
		return false

	var duration_sec := stream.get_length()
	if duration_sec <= 0.0:
		return false

	ChartData.audio_duration_ms = int(duration_sec * 1000.0)
	if stream is AudioStreamWAV:
		ChartData.waveform_samples = WavReader.waveform_from_stream(stream as AudioStreamWAV)
	return true
