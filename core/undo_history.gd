@tool
class_name UndoHistory
extends RefCounted

## 通用快照式撤销/重做栈。
##
## 只负责「存快照 / 取快照」，不关心里面是什么内容；捕获与恢复由持有者实现，
## 因此可以脱离编辑器单独测试。

const DEFAULT_CAPACITY: int = 100

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _capacity: int = DEFAULT_CAPACITY


func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = maxi(capacity, 1)


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo_depth() -> int:
	return _undo_stack.size()


func redo_depth() -> int:
	return _redo_stack.size()


## 记录一个新状态：入栈并作废重做链
func push(snapshot: Dictionary) -> void:
	_undo_stack.append(snapshot)
	_redo_stack.clear()
	if _undo_stack.size() > _capacity:
		_undo_stack.pop_front()


## 撤销：current 是当前状态快照（会压入重做链），返回要恢复的状态；不可撤销时返回 {}
func undo(current: Dictionary) -> Dictionary:
	if _undo_stack.is_empty():
		return {}
	_redo_stack.append(current)
	return _undo_stack.pop_back()


## 重做：current 是当前状态快照（会压回撤销链），返回要恢复的状态；不可重做时返回 {}
func redo(current: Dictionary) -> Dictionary:
	if _redo_stack.is_empty():
		return {}
	_undo_stack.append(current)
	return _redo_stack.pop_back()


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
