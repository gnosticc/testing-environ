# NewUpgradeCard.gd
# A lean script for our rebuilt upgrade card.
# Corrected node paths to include "CardLayout".
# This script handles displaying the data for a single upgrade option and emitting selection.

extends PanelContainer

signal card_selected(upgrade_data: Dictionary) # Emitted when this card's select button is pressed

# Corrected paths to match your scene tree: NewUpgradeCard > CardLayout > UI_Element
@onready var title_label: Label = $CardLayout/TitleLabel
@onready var description_label: Label = $CardLayout/DescriptionLabel
@onready var icon_texture_rect: TextureRect = $CardLayout/IconTextureRect
@onready var select_button: Button = $CardLayout/SelectButton

var _current_card_data: Dictionary # Stores the upgrade data dictionary for this specific card

func _ready():
	# Ensure the select button is valid and connect its 'pressed' signal.
	if not is_instance_valid(select_button):
		push_error("ERROR (NewUpgradeCard): SelectButton not found at '$CardLayout/SelectButton'. Check scene setup.")
	elif not select_button.is_connected("pressed", Callable(self, "_on_select_button_pressed")):
		select_button.pressed.connect(Callable(self, "_on_select_button_pressed"))
	
	# Set a custom minimum size for consistent card layout.
	custom_minimum_size = Vector2(160, 200)

# Displays the given upgrade data on the card's UI elements.
func display_data(data: Dictionary):
	_current_card_data = data # Store the data for later emission

	# Update UI elements with data, checking for validity first.
	if is_instance_valid(title_label):
		title_label.text = data.get("title", "N/A") # Use .get() with default for safety
	else:
		push_warning("NewUpgradeCard: TitleLabel is not valid. Cannot set title.")
	
	if is_instance_valid(description_label):
		description_label.text = data.get("description", "")
	else:
		push_warning("NewUpgradeCard: DescriptionLabel is not valid. Cannot set description.")
		
	if is_instance_valid(icon_texture_rect):
		var icon_path = data.get("icon_path", "")
		if not icon_path.is_empty():
			var tex = load(icon_path) as Texture2D
			icon_texture_rect.texture = tex
			icon_texture_rect.visible = is_instance_valid(tex) # Only show if texture loaded successfully
		else:
			icon_texture_rect.visible = false # Hide if no icon path provided
	else:
		push_warning("NewUpgradeCard: IconTextureRect is not valid. Cannot set icon.")


# Called when the select button on this card is pressed.
func _on_select_button_pressed():
	if _current_card_data:
		emit_signal("card_selected", _current_card_data) # Emit the stored data
	else:
		push_error("ERROR (NewUpgradeCard): Select button pressed but '_current_card_data' is empty. Card was not properly initialized.")
