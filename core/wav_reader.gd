@tool
class_name WavReader
extends RefCounted

## RIFF/WAVE(PCM) 解析与波形降采样。
##
## 为什么不用 ResourceLoader：编辑器里用户可以直接挑选任意本地音频文件，
## 而这些文件未必被 Godot 导入过（`res://.godot/imported`），所以这里直接读字节流。
## 同一份解析结果同时服务于两条路径：
##   * 播放 —— `to_stream()` 组装 AudioStreamWAV
##   * 绘制 —— `read()` 给出时长与降采样波形
##
## 纯静态工具，不依赖场景树，便于单独测试。

## 波形降采样率：每毫秒一个峰值
const WAVEFORM_RATE: int = 1000

const REASON_OK := "ok"
const REASON_NOT_FOUND := "file_not_found"
const REASON_NOT_RIFF := "not_riff"
const REASON_NOT_PCM := "not_pcm"
const REASON_INVALID_DATA := "invalid_data"


## 解析文件为 { ok, reason, duration_ms, sample_rate, channels, waveform }
static func read(path: String) -> Dictionary:
	var samples := _load_samples(path)
	if not samples["ok"]:
		return _failure(samples["reason"])

	var sample_rate: int = samples["sample_rate"]
	var channels: int = samples["num_channels"]
	var bits: int = samples["bits_per_sample"]
	var raw: PackedByteArray = samples["raw_data"]
	var total_frames := _frame_count(raw.size(), bits, channels)

	return {
		"ok": true,
		"reason": REASON_OK,
		"duration_ms": _duration_ms(total_frames, sample_rate),
		"sample_rate": sample_rate,
		"channels": channels,
		"waveform": downsample(raw, total_frames, sample_rate, channels, bits),
	}


## 解析文件为可播放的音频流（仅支持 PCM WAV；失败返回 null）
static func to_stream(path: String) -> AudioStreamWAV:
	var samples := _load_samples(path)
	if not samples["ok"]:
		return null

	var wav := AudioStreamWAV.new()
	wav.data = samples["raw_data"]
	wav.format = AudioStreamWAV.FORMAT_16_BITS if samples["bits_per_sample"] == 16 \
			else AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = samples["sample_rate"]
	wav.stereo = samples["num_channels"] >= 2
	return wav


## 从已导入的 AudioStreamWAV 提取波形（回退路径使用）
static func waveform_from_stream(stream: AudioStreamWAV) -> PackedFloat32Array:
	var data := stream.data
	if data.is_empty():
		return PackedFloat32Array()

	var bytes_per_sample := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var channels := 2 if stream.stereo else 1
	var total_frames := _frame_count(data.size(), bytes_per_sample * 8, channels)
	if total_frames <= 0:
		return PackedFloat32Array()

	return downsample(data, total_frames, stream.mix_rate, channels, bytes_per_sample * 8)


## 将原始 PCM 数据降采样为 WAVEFORM_RATE 的峰值序列，输出范围 [0, 1]
static func downsample(raw_data: PackedByteArray, total_frames: int, sample_rate: int,
		num_channels: int, bits_per_sample: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if total_frames <= 0 or sample_rate <= 0 or num_channels <= 0:
		return result

	var duration_sec := float(total_frames) / float(sample_rate)
	var num_output := maxi(int(duration_sec * WAVEFORM_RATE), 1)
	result.resize(num_output)

	var bytes_per_sample := maxi(bits_per_sample / 8, 1)
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
			if offset + bytes_per_frame > raw_data.size():
				break
			var frame_sum: float = 0.0
			for ch in range(num_channels):
				frame_sum += _sample_at(raw_data, offset + ch * bytes_per_sample, is_16bit)
			peak = maxf(peak, absf(frame_sum / float(num_channels)))

		result[i] = peak

	return result


# --- 内部 ---

static func _sample_at(data: PackedByteArray, offset: int, is_16bit: bool) -> float:
	if is_16bit:
		# 16-bit 小端序
		var s16 := (data[offset + 1] << 8) | data[offset]
		if s16 >= 32768:
			s16 -= 65536
		return float(s16) / 32768.0
	# 8-bit 无符号
	return float(data[offset]) / 128.0 - 1.0


static func _frame_count(data_size: int, bits_per_sample: int, num_channels: int) -> int:
	var bytes_per_frame := maxi(bits_per_sample / 8, 1) * maxi(num_channels, 1)
	return data_size / bytes_per_frame


static func _duration_ms(total_frames: int, sample_rate: int) -> int:
	if sample_rate <= 0:
		return 0
	return int(float(total_frames) / float(sample_rate) * 1000.0)


static func _failure(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"duration_ms": 0,
		"sample_rate": 0,
		"channels": 0,
		"waveform": PackedFloat32Array(),
	}


## 打开文件并读出 PCM 采样数据，返回 { ok, reason, sample_rate, num_channels,
## bits_per_sample, data_offset, data_size, raw_data }
static func _load_samples(path: String) -> Dictionary:
	var file := _open(path)
	if file == null:
		return _samples_failure(REASON_NOT_FOUND)

	var header := _scan_chunks(file)
	if not header["ok"]:
		file.close()
		return _samples_failure(header["reason"])

	var data_size: int = header["data_size"]
	file.seek(header["data_offset"])
	var raw_data := file.get_buffer(data_size)
	file.close()

	return {
		"ok": true,
		"reason": REASON_OK,
		"sample_rate": header["sample_rate"],
		"num_channels": header["num_channels"],
		"bits_per_sample": header["bits_per_sample"],
		"data_offset": header["data_offset"],
		"data_size": data_size,
		"raw_data": raw_data,
	}


## 遍历 RIFF chunk，定位 fmt 与 data 块
static func _scan_chunks(file: FileAccess) -> Dictionary:
	if file.get_buffer(4).get_string_from_ascii() != "RIFF":
		return _header_failure(REASON_NOT_RIFF)
	file.get_32()	# 跳过文件大小
	if file.get_buffer(4).get_string_from_ascii() != "WAVE":
		return _header_failure(REASON_NOT_RIFF)

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
			if file.get_16() != 1:	# 仅支持 PCM
				return _header_failure(REASON_NOT_PCM)
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
			file.get_buffer(chunk_size)	# 不关心的 chunk，跳过

	if sample_rate <= 0 or data_size <= 0:
		return _header_failure(REASON_INVALID_DATA)

	return {
		"ok": true,
		"reason": REASON_OK,
		"sample_rate": sample_rate,
		"num_channels": num_channels,
		"bits_per_sample": bits_per_sample,
		"data_offset": data_offset,
		"data_size": data_size,
	}


static func _header_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _samples_failure(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"sample_rate": 0,
		"num_channels": 0,
		"bits_per_sample": 0,
		"data_offset": 0,
		"data_size": 0,
		"raw_data": PackedByteArray(),
	}


## 以本地路径打开文件（res:// 会先转换为系统绝对路径）
static func _open(path: String) -> FileAccess:
	if path.is_empty():
		return null
	var local_path := path
	if local_path.begins_with("res://"):
		local_path = ProjectSettings.globalize_path(local_path)
	return FileAccess.open(local_path, FileAccess.READ)
