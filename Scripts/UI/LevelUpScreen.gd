# LevelUpScreen.gd
# Forcefully sets visibility on itself and its children to ensure UI appears.
extends CanvasLayer

signal upgrade_chosen(chosen_upgrade_data_dict: Dictionary)

@onready var cards_container_node: Container = $CardsContainer 
@onready var dim_background: ColorRect = $DimBackground 

var card_nodes_array: Array[PanelContainer] = [] 

func _ready():
	# Start hidden, but ensure children's visibility is what's set in the scene editor initially.
	self.hide() 
	call_deferred("_get_card_nodes_from_container") 

func _get_card_nodes_from_container():
	card_nodes_array.clear() 
	if not is_instance_valid(cards_container_node): 
		print_debug("ERROR (LevelUpScreen - _get_card_nodes): cards_container_node ($CardsContainer) is invalid!")
		return

	for child in cards_container_node.get_children():
		if child is PanelContainer and child.has_method("set_data"): 
			card_nodes_array.append(child)
			if child.has_signal("card_selected"):
				var callable_to_check = Callable(self, "_on_card_selected")
				var is_already_connected = false
				for connection_info in child.get_signal_connection_list("card_selected"):
					if connection_info.callable == callable_to_check:
						is_already_connected = true; break
				if not is_already_connected:
					child.card_selected.connect(callable_to_check)
			# Don't hide the cards here anymore, let display_options manage it.

# Changed signature to 'options: Array'
func display_options(options: Array): 
	# --- Force Visibility ---
	self.visible = true
	if is_instance_valid(dim_background):
		dim_background.visible = true
	if is_instance_valid(cards_container_node):
		cards_container_node.visible = true
	else:
		print_debug("ERROR (LevelUpScreen - display_options): cards_container_node is invalid! Cannot display cards.")
		return
	
	# Ensure the card node array is up-to-date
	_get_card_nodes_from_container()
	
	if card_nodes_array.is_empty() and not options.is_empty():
		print_debug("ERROR (LevelUpScreen): No card UI nodes found/available in $CardsContainer. Cannot display options.")
		return

	# Hide all card slots first, then show only the ones we need
	for card in card_nodes_array:
		card.hide()

	var cards_to_display_count = min(options.size(), card_nodes_array.size())
	print_debug("LevelUpScreen: Populating and showing ", cards_to_display_count, " cards.")

	for i in range(cards_to_display_count):
		var card_node: PanelContainer = card_nodes_array[i] 
		var option_data_dict: Dictionary = options[i] 
		
		if not option_data_dict is Dictionary:
			print_debug("ERROR (LevelUpScreen): Option data at index ", i, " is not a Dictionary.")
			continue

		if card_node.has_method("set_data"):
			card_node.set_data(option_data_dict) 
		
		card_node.visible = true # Forcefully show the card that has been populated

	print_debug("LevelUpScreen: Visibility explicitly set.")


func _on_card_selected(chosen_upgrade_data_dict: Dictionary): 
	print_debug("LevelUpScreen: Card selected, emitting upgrade_chosen with: ", chosen_upgrade_data_dict)
	emit_signal("upgrade_chosen", chosen_upgrade_data_dict) 
	self.hide() 
