# NewLevelUpScreen.gd (Rebuilt Version)
# Dynamically creates cards to avoid timing issues.
extends CanvasLayer

signal upgrade_chosen(chosen_upgrade_data)

# Preload the card scene. Ensure this path points to your NEW UpgradeCard scene.
const UPGRADE_CARD_SCENE = preload("res://Scenes/UI/NewUpgradeCard.tscn")

@onready var cards_container: HBoxContainer = $CardsContainer
@onready var dim_background: ColorRect = $DimBackground

func _ready():
	# Start hidden by setting visible property directly
	visible = false

# This is called deferred from game.gd
func display_options(options: Array):
	# 1. Clear any old cards from the container from a previous level-up
	for child in cards_container.get_children():
		child.queue_free()
		
	if not is_instance_valid(UPGRADE_CARD_SCENE):
		print_debug("ERROR (NewLevelUpScreen): UPGRADE_CARD_SCENE is not a valid scene. Check path in script.")
		visible = true # Show empty so game doesn't freeze
		return
	
	print_debug("NewLevelUpScreen: Creating ", options.size(), " new upgrade cards.")

	# 2. Create and populate new cards for the current options
	for option_data in options:
		if not option_data is Dictionary: continue
		
		var card_instance = UPGRADE_CARD_SCENE.instantiate()
		if not is_instance_valid(card_instance): continue
		
		# Add card to the tree *before* calling methods on it.
		# This ensures its _ready() function runs and @onready vars are set.
		cards_container.add_child(card_instance)
		
		# Now that it's in the tree, we can safely call display_data.
		if card_instance.has_method("display_data"):
			card_instance.display_data(option_data)
		else:
			print_debug("ERROR: Instanced UpgradeCard scene is missing display_data() method.")
			
		# Connect to its signal
		if not card_instance.is_connected("card_selected", Callable(self, "_on_card_selected")):
			card_instance.card_selected.connect(Callable(self, "_on_card_selected"))
			
	# 3. Show the entire screen
	self.visible = true


func _on_card_selected(chosen_upgrade_data: Dictionary):
	emit_signal("upgrade_chosen", chosen_upgrade_data) 
	visible = false # Hide by setting visible property directly
