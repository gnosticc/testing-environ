# NewUpgradeCard.gd
# A lean script for our rebuilt upgrade card.
# CORRECTED node paths to include "CardLayout".
extends PanelContainer

signal card_selected(upgrade_data: Dictionary)

# Corrected paths to match your scene tree: NewUpgradeCard > CardLayout > UI_Element
@onready var title_label: Label = $CardLayout/TitleLabel
@onready var description_label: Label = $CardLayout/DescriptionLabel
@onready var icon_texture_rect: TextureRect = $CardLayout/IconTextureRect
@onready var select_button: Button = $CardLayout/SelectButton

var _current_card_data: Dictionary

func _ready():
	if not is_instance_valid(select_button):
		print_debug("ERROR (NewUpgradeCard): SelectButton not found at '$CardLayout/SelectButton'")
	elif not select_button.is_connected("pressed", Callable(self, "_on_select_button_pressed")):
		select_button.pressed.connect(Callable(self, "_on_select_button_pressed"))
			
	custom_minimum_size = Vector2(160, 200)

func display_data(data: Dictionary):
	_current_card_data = data
	
	if is_instance_valid(title_label):
		title_label.text = data.get("title", "N/A")
	
	if is_instance_valid(description_label):
		description_label.text = data.get("description", "")
		
	if is_instance_valid(icon_texture_rect):
		var icon_path = data.get("icon_path", "")
		if not icon_path.is_empty():
			var tex = load(icon_path) as Texture2D
			icon_texture_rect.texture = tex
			icon_texture_rect.visible = is_instance_valid(tex)
		else:
			icon_texture_rect.visible = false

func _on_select_button_pressed():
	if _current_card_data:
		emit_signal("card_selected", _current_card_data)
	else:
		print_debug("ERROR (NewUpgradeCard): Select button pressed but no data.")
