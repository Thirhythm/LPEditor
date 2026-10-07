extends VBoxContainer
class_name ToolList

# 工具栏组件
# 所有条目按钮均由场景节点编排（支持分组容器），脚本只负责索引分发与选中态管理

signal item_pressed(index: int)

var _item_buttons: Array[Button] = []

func _ready() -> void:
	_collect_item_buttons(self)

# 按节点树顺序收集所有按钮（含分组容器内的按钮，隐藏分组同样占位）
func _collect_item_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var index := _item_buttons.size()
			_item_buttons.append(child)
			child.pressed.connect(_on_item_button_pressed.bind(index))
		else:
			_collect_item_buttons(child)

func _on_item_button_pressed(index: int) -> void:
	_highlight(index)
	item_pressed.emit(index)

# 高亮（禁用）被点击的按钮，其余恢复可用
func _highlight(index: int) -> void:
	for i in _item_buttons.size():
		_item_buttons[i].disabled = (i == index)

# 以代码方式选中某个条目（快捷键用）：高亮状态与发出的信号都跟点击一致，
# 所以调用方不需要另外复刻一遍「选中之后要做什么」
func select(index: int) -> void:
	if index < 0 or index >= _item_buttons.size():
		return
	_highlight(index)
	item_pressed.emit(index)

# 重置选中态：首个可见按钮置为选中（禁用），其余可用。切换分类时调用
func reset_selection() -> void:
	var selected := false
	for button in _item_buttons:
		if not selected and button.is_visible_in_tree():
			button.disabled = true
			selected = true
		else:
			button.disabled = false
