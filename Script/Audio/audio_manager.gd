extends Node
class_name AudioManager

# 音频播放管理，负责 WAV 文件的直接读取、波形生成和播放控制
# 绕过 Godot 的 ResourceLoader 系统以支持 WAV 文件直接加载

var player: AudioStreamPlayer
var playing: bool = false
var _start_time_ms: int = 0			# 本次播放开始时的系统时间 (Time.get_ticks_msec())
var _start_offset_ms: int = 0		# 本次播放从音频的哪个位置开始 (ms)

func _ready() -> void:
	player = AudioStreamPlayer.new()
	add_child(player)

# 返回从播放开始到现在的经过时间 (ms)
# 使用 Time.get_ticks_msec() 而非 get_playback_position()，避免音频驱动缓冲导致的抖动
func elapsed_time_ms() -> int:
	return _start_offset_ms + (Time.get_ticks_msec() - _start_time_ms)

# 从指定时间位置开始播放音频
func start_playback(from_ms: int) -> bool:
	if EditorChartState.audio_path.is_empty():
		return false
	var stream := _parse_wav_to_stream()
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

# 播放中跳转到指定位置
func seek(from_ms: int) -> void:
	player.play(float(from_ms) / 1000.0)
	_start_time_ms = Time.get_ticks_msec()
	_start_offset_ms = from_ms

# 加载音频文件：优先直接解析 WAV（绕过 .import），失败时回退到 Godot 标准加载
func load_audio() -> bool:
	EditorChartState.audio_duration_ms = 0
	EditorChartState.waveform_samples.clear()
	if EditorChartState.audio_path.is_empty():
		return false

	if _parse_wav_direct():
		return true

	var stream := _load_stream_by_extension()
	if stream == null:
		return false

	var duration_sec := stream.get_length()
	if duration_sec > 0:
		EditorChartState.audio_duration_ms = int(duration_sec * 1000.0)
	if stream is AudioStreamWAV:
		_waveform_from_stream(stream as AudioStreamWAV)
	return duration_sec > 0

# --- WAV 文件直接解析 ---

# RIFF/WAVE 格式：RIFF 头 -> fmt 块（格式信息） -> data 块（PCM 数据）
func _parse_wav_direct() -> bool:
	var file := _open_audio_file()
	if file == null:
		return false
	if file.get_buffer(4).get_string_from_ascii() != "RIFF":
		file.close()
		return false
	file.get_32()	# 跳过文件大小
	if file.get_buffer(4).get_string_from_ascii() != "WAVE":
		file.close()
		return false

	var sample_rate := 0
	var num_channels := 1
	var bits_per_sample := 16
	var data_offset := 0
	var data_size := 0
	var file_end := file.get_length()

	# 遍历所有 chunk，查找 fmt 和 data 块
	while file.get_position() + 8 <= file_end:
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()

		if chunk_id == "fmt ":
			if file.get_16() != 1:	# 仅支持 PCM 格式
				file.close()
				return false
			num_channels = file.get_16()
			sample_rate = file.get_32()
			file.get_32()	# 跳过 byte rate
			file.get_16()	# 跳过 block align
			bits_per_sample = file.get_16()
			if chunk_size > 16:
				file.get_buffer(chunk_size - 16)
		elif chunk_id == "data":
			data_offset = file.get_position()
			data_size = chunk_size
			break
		else:
			# 不关心的 chunk，跳过
			file.get_buffer(chunk_size)

	if sample_rate <= 0 or data_size <= 0:
		file.close()
		return false

	var bytes_per_sample := bits_per_sample / 8
	var bytes_per_frame := bytes_per_sample * num_channels
	var total_frames := data_size / bytes_per_frame
	EditorChartState.audio_duration_ms = int(float(total_frames) / sample_rate * 1000.0)

	# 读取原始 PCM 数据并降采样为波形
	file.seek(data_offset)
	var raw_data := file.get_buffer(data_size)
	file.close()

	_downsample_waveform(raw_data, total_frames, sample_rate, num_channels, bits_per_sample)
	return true

# 按 Godot 内置格式从本地文件加载音频流（支持 ogg/mp3/wav）
func _load_stream_by_extension() -> AudioStream:
	var path := EditorChartState.audio_path
	if not FileAccess.file_exists(path):
		return null
	var ext := path.get_extension().to_lower()
	match ext:
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		_:
			return null

# --- 波形降采样 ---

# 将原始 PCM 数据降采样为 1000Hz 的峰值数据（每毫秒一个峰值）
# 输出范围 [0, 1]，用于 waveform 绘制
func _downsample_waveform(raw_data: PackedByteArray, total_frames: int, sample_rate: int,
		num_channels: int, bits_per_sample: int) -> void:
	var output_rate := 1000
	var duration_sec := float(total_frames) / sample_rate
	var num_output := maxi(int(duration_sec * output_rate), 1)
	var result := PackedFloat32Array()
	result.resize(num_output)

	var bytes_per_sample := bits_per_sample / 8
	var bytes_per_frame := bytes_per_sample * num_channels
	var frames_per_output := float(total_frames) / float(num_output)
	var is_16bit := bits_per_sample == 16

	for i in range(num_output):
		var start_frame := int(i * frames_per_output)
		var end_frame := int(min(float(total_frames), (i + 1) * frames_per_output))
		var peak: float = 0.0

		# 在该时间窗口内取最大峰值
		for f in range(start_frame, end_frame):
			var offset := f * bytes_per_frame
			var frame_sum: float = 0.0

			for ch in range(num_channels):
				var ch_offset := offset + ch * bytes_per_sample
				var sample: float
				if is_16bit:
					# 16-bit 小端序
					var lo := raw_data[ch_offset] as int
					var hi := raw_data[ch_offset + 1] as int
					var s16 := (hi << 8) | lo
					if s16 >= 32768:
						s16 -= 65536
					sample = float(s16) / 32768.0
				else:
					# 8-bit
					sample = float(raw_data[ch_offset]) / 128.0 - 1.0
				frame_sum += sample

			peak = maxf(peak, absf(frame_sum / float(num_channels)))

		result[i] = peak

	EditorChartState.waveform_samples = result

# 从 AudioStreamWAV 对象提取波形（备选路径）
func _waveform_from_stream(stream: AudioStreamWAV) -> void:
	var data := stream.data
	if data.is_empty():
		return

	var bytes_per_sample := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var num_channels := 2 if stream.stereo else 1
	var bytes_per_frame := bytes_per_sample * num_channels
	var total_frames := data.size() / bytes_per_frame
	if total_frames <= 0:
		return

	_downsample_waveform(data, total_frames, stream.mix_rate, num_channels, bytes_per_sample * 8)

# --- 播放流构建 ---

# 将 WAV 文件解析为 AudioStreamWAV 对象用于播放
func _parse_wav_to_stream() -> AudioStreamWAV:
	var file := _open_audio_file()
	if file == null:
		return null

	if file.get_buffer(4).get_string_from_ascii() != "RIFF":
		file.close()
		return null
	file.get_32()
	if file.get_buffer(4).get_string_from_ascii() != "WAVE":
		file.close()
		return null

	var sample_rate := 0
	var num_channels := 1
	var bits_per_sample := 16
	var data_offset := 0
	var data_size := 0
	var file_end := file.get_length()

	while file.get_position() + 8 <= file_end:
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()

		if chunk_id == "fmt ":
			if file.get_16() != 1:
				file.close()
				return null
			num_channels = file.get_16()
			sample_rate = file.get_32()
			file.get_32()
			file.get_16()
			bits_per_sample = file.get_16()
			if chunk_size > 16:
				file.get_buffer(chunk_size - 16)
		elif chunk_id == "data":
			data_offset = file.get_position()
			data_size = chunk_size
			break
		else:
			file.get_buffer(chunk_size)

	if sample_rate <= 0 or data_size <= 0:
		file.close()
		return null

	file.seek(data_offset)
	var raw_data := file.get_buffer(data_size)
	file.close()

	var wav := AudioStreamWAV.new()
	wav.data = raw_data
	wav.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample == 16 else AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.stereo = num_channels >= 2
	return wav

# 以 UTF-8 本地路径打开音频文件
func _open_audio_file() -> FileAccess:
	var path := EditorChartState.audio_path
	if path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	return FileAccess.open(path, FileAccess.READ)
