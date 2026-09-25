class_name ChartIO
extends RefCounted

## 谱面文件读写与导出（`.lp` / `.lpz`）。
##
## 这里只做「字节 ↔ 字典」与打包，不碰任何界面：出错时返回
## `{ ok: false, error: "..." }`，由调用方决定怎么提示用户。
## 因此可以脱离场景树单独测试。

const EXTENSION: String = ".lpz"
const CHART_ENTRY: String = "chart.lp"
const AUDIO_ENTRY: String = "audio"
const COVER_ENTRY: String = "cover"


## 读取谱面 JSON → { ok, error, data }
static func load_chart(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法打开文件: %s" % path)

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(content) != OK:
		return _failure("JSON 解析失败: %s" % json.get_error_message())

	var data = json.get_data()
	if not data is Dictionary:
		return _failure("无效的谱面格式")

	return {"ok": true, "error": "", "data": data}


## 写出谱面 JSON → { ok, error }
static func save_chart(path: String, data: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("无法保存文件: %s" % path)

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return {"ok": true, "error": ""}


## 打包导出：`chart.lp` + `audio.<ext>` + `cover.<ext>` → { ok, error }
static func export_lpz(path: String, chart: Dictionary, audio_path: String,
		jacket_path: String) -> Dictionary:
	var packer := ZIPPacker.new()
	var err := packer.open(path)
	if err != OK:
		return _failure("无法创建导出文件（错误码 %d）" % err)

	# 音频与曲绘随包携带，因此谱面里的绝对路径不再导出
	var payload := chart.duplicate(true)
	var general: Dictionary = payload.get("General", {})
	general.erase("AudioPath")
	general.erase("JacketPath")

	if not _write_entry(packer, CHART_ENTRY, JSON.stringify(payload, "\t").to_utf8_buffer()):
		packer.close()
		return _failure("写入谱面数据失败")

	var audio_error := _write_asset(packer, AUDIO_ENTRY, audio_path, "音频")
	if not audio_error.is_empty():
		packer.close()
		return _failure(audio_error)

	var cover_error := _write_asset(packer, COVER_ENTRY, jacket_path, "曲绘")
	if not cover_error.is_empty():
		packer.close()
		return _failure(cover_error)

	packer.close()
	return {"ok": true, "error": ""}


## 补全导出扩展名
static func ensure_extension(path: String) -> String:
	return path if path.ends_with(EXTENSION) else path + EXTENSION


# --- 内部 ---

## 写入一个随包资源；返回空串表示成功，否则是错误说明
static func _write_asset(packer: ZIPPacker, entry_base: String, source_path: String,
		label: String) -> String:
	if source_path.is_empty():
		return ""
	var data := _read_bytes(source_path)
	if data.is_empty():
		return "%s文件不存在或无法读取: %s" % [label, source_path]
	if not _write_entry(packer, _entry_with_extension(entry_base, source_path), data):
		return "写入%s失败" % label
	return ""


static func _write_entry(packer: ZIPPacker, name: String, data: PackedByteArray) -> bool:
	if packer.start_file(name) != OK:
		return false
	packer.write_file(data)
	return packer.close_file() == OK


static func _entry_with_extension(base: String, source_path: String) -> String:
	var ext := source_path.get_extension()
	return base if ext.is_empty() else base + "." + ext


static func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var data := file.get_buffer(file.get_length())
	file.close()
	return data


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
