extends Node
class_name AudioManager

## 音频播放控制。
##
## 职责边界：
##   * 播放 / 暂停 / 定位 / 播放计时——由 AudioStreamPlayer 完成；
##   * 音频分析结果（时长、波形）写入 ChartData，供 ruler 绘制与滚动范围计算；
##   * WAV 字节解析交给 core/wav_reader.gd，这里不再出现 RIFF 细节。

## 播放器节点由主场景中的 AudioManager/Player 节点提供
@onready var player: AudioStreamPlayer = $Player

var playing: bool = false
var _start_time_ms: int = 0		# 本次播放开始时的系统时间 (Time.get_ticks_msec())
var _start_offset_ms: int = 0		# 本次播放从音频的哪个位置开始 (ms)


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
	return true


func pause_playback() -> void:
	player.stop()
	playing = false


func stop_playback() -> void:
	player.stop()
	playing = false


## 播放中跳转到指定位置
func seek(from_ms: int) -> void:
	player.play(float(from_ms) / 1000.0)
	_start_time_ms = Time.get_ticks_msec()
	_start_offset_ms = from_ms


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
