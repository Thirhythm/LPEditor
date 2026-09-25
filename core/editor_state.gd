@tool
class_name EditorState
extends RefCounted

## 编辑器会话状态：视口滚动/缩放、量化与吸附设置、当前选区，
## 以及基于快照的撤销/重做（快照同时覆盖 ChartData 的文档字段）。
##
## 与 `ChartData` 一样全部使用静态成员，不依赖 autoload 注册与场景树，
## 因此可以在编辑器内直接解析、也便于单元测试。

# --- 视口与缩放 ---
static var scroll_time: int = 0							# 当前滚动时间 (ms)，决定视口起点
static var px_per_ms: float = ChartDefs.DEFAULT_PX_PER_MS	# 像素/毫秒，控制缩放

# --- 编辑设置 ---
static var quantize_denominator: int = ChartDefs.DEFAULT_QUANTIZE_DENOMINATOR
static var snap_enabled: bool = true

# --- 选区 ---
static var selected_notes: Array[Dictionary] = []
static var clipboard: Array[Dictionary] = []

static var _history := UndoHistory.new()
static var _is_undoing: bool = false


# --- 视口与缩放 ---

## 滚轮滚动一步的时间跨度（像素换算成时间）
static func scroll_step_ms() -> int:
	return int(200.0 / maxf(px_per_ms, 0.01))


static func set_zoom(px_per_ms_value: float) -> void:
	px_per_ms = clampf(px_per_ms_value, ChartDefs.MIN_PX_PER_MS, ChartDefs.MAX_PX_PER_MS)


## 将 scroll_time 限制在合法范围内
static func clamp_scroll() -> void:
	scroll_time = clampi(scroll_time, 0, ChartData.get_max_scroll_time())


## 量化网格吸附（snap_enabled 关闭时原样返回）
static func snap_time(time_ms: int) -> int:
	if not snap_enabled:
		return time_ms
	return ChartDefs.snap_time(time_ms, ChartData.bpm, quantize_denominator)


# --- 撤销 / 重做 ---

static func can_undo() -> bool:
	return _history.can_undo()


static func can_redo() -> bool:
	return _history.can_redo()


static func push_undo_state() -> void:
	if _is_undoing:
		return
	_history.push(_capture_state())


static func undo() -> bool:
	if not _history.can_undo():
		return false
	_is_undoing = true
	_restore_state(_history.undo(_capture_state()))
	_is_undoing = false
	return true


static func redo() -> bool:
	if not _history.can_redo():
		return false
	_is_undoing = true
	_restore_state(_history.redo(_capture_state()))
	_is_undoing = false
	return true


static func clear_undo_history() -> void:
	_history.clear()


## 快照 = 文档字段（ChartData 提供）+ 会话设置
static func _capture_state() -> Dictionary:
	var state := ChartData.capture_snapshot()
	state["quantize_denominator"] = quantize_denominator
	state["snap_enabled"] = snap_enabled
	return state


static func _restore_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	ChartData.restore_snapshot(state)
	quantize_denominator = state.get("quantize_denominator", quantize_denominator)
	snap_enabled = state.get("snap_enabled", snap_enabled)
	selected_notes.clear()
