extends VBoxContainer

## 列表项被点击时触发, 参数为索引
signal item_pressed(index: int)

## 列表项
@export var item: Array[Dictionary] = []

## 列表排列方式, 0: 水平, 1: 垂直
@export var arrangement: int = 0

## 列表项按钮
var _item_buttons: Array[Button] = []

func _ready() -> void:

	if arrangement == 1:
		self.custom_minimum_size.x = 70
	else:
		self.custom_minimum_size.x = 150
	
	for i in item.size():
		var item_button: Button = Button.new()
		item_button.text = item[i]["text"]
		item_button.icon = load(item[i]["icon"])

		if arrangement == 1:
			item_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			item_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

		if i == 0:
			item_button.disabled = true
		
		item_button.pressed.connect(_on_item_button_pressed.bind(i))
		_item_buttons.append(item_button)
		add_child(item_button)

func refresh() -> void:
	
	for i in _item_buttons:
		self.remove_child(i)
	_item_buttons.clear()
	
	if arrangement == 1:
		self.custom_minimum_size.x = 70
	else:
		self.custom_minimum_size.x = 150
	
	for i in item.size():
		var item_button: Button = Button.new()
		item_button.text = item[i]["text"]
		item_button.icon = load(item[i]["icon"])

		if arrangement == 1:
			item_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			item_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

		if i == 0:
			item_button.disabled = true
		
		item_button.pressed.connect(_on_item_button_pressed.bind(i))
		_item_buttons.append(item_button)
		add_child(item_button)


func _on_item_button_pressed(index: int) -> void:
	item_pressed.emit(index)

	for i in _item_buttons.size():
		_item_buttons[i].disabled = false

	_item_buttons[index].disabled = true
