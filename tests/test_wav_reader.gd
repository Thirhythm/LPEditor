@tool
extends McpTestSuite

## core/wav_reader.gd 测试：降采样峰值计算与错误路径（不需要真实音频素材）。

func suite_name() -> String:
	return "wav_reader"


func test_downsample_emits_one_peak_per_millisecond() -> void:
	# 1000Hz / 16bit / 单声道 / 4 帧 → 4ms → 4 个输出点
	var raw := _pcm16([0, 32767, -32768, 16384])
	var peaks := WavReader.downsample(raw, 4, 1000, 1, 16)

	assert_eq(peaks.size(), 4)
	assert_eq(peaks[0], 0.0)
	assert_true(peaks[1] > 0.999, "正满量程接近 1.0（32767/32768）")
	assert_eq(peaks[2], 1.0, "负满量程取绝对值后同样为 1.0")
	assert_true(absf(peaks[3] - 0.5) < 0.001, "半量程约为 0.5")


func test_downsample_averages_stereo_channels() -> void:
	# 左右声道一正一负 → 平均后抵消
	var raw := _pcm16([32767, -32768])
	var peaks := WavReader.downsample(raw, 1, 1000, 2, 16)

	assert_eq(peaks.size(), 1)
	assert_true(peaks[0] < 0.001)


func test_downsample_handles_empty_input() -> void:
	assert_true(WavReader.downsample(PackedByteArray(), 0, 44100, 2, 16).is_empty())
	assert_true(WavReader.downsample(PackedByteArray(), 100, 0, 2, 16).is_empty())


func test_read_reports_missing_file() -> void:
	var result := WavReader.read("user://definitely-missing.wav")

	assert_false(result["ok"])
	assert_eq(result["reason"], WavReader.REASON_NOT_FOUND)
	assert_eq(result["duration_ms"], 0)
	assert_true((result["waveform"] as PackedFloat32Array).is_empty())


func test_read_rejects_non_riff_data() -> void:
	var path := "user://not-a-wav.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_true(file != null, "无法写入临时文件")
	file.store_string("NOPE")
	file.close()

	var result := WavReader.read(path)
	assert_false(result["ok"])
	assert_eq(result["reason"], WavReader.REASON_NOT_RIFF)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_to_stream_returns_null_for_missing_file() -> void:
	assert_true(WavReader.to_stream("user://definitely-missing.wav") == null)


func test_waveform_from_empty_stream() -> void:
	var stream := AudioStreamWAV.new()
	assert_true(WavReader.waveform_from_stream(stream).is_empty())


func _pcm16(values: Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(values.size() * 2)
	for i in values.size():
		data.encode_s16(i * 2, values[i])
	return data
