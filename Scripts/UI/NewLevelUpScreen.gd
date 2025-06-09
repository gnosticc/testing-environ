# NewLevelUpScreen.gd (Rebuilt Version)
# Dynamically creates cards to avoid timing issues.
# This script handles displaying level-up options and emitting the chosen upgrade.

extends CanvasLayer

signal upgrade_chosen(chosen_upgrade_data) # Emitted when a player selects an upgrade

# Preload the card scene. Ensure this path points to your NEW UpgradeCard scene.
const UPGRADE_CARD_SCENE = preload("res://Scenes/UI/NewUpgradeCard.tscn")

@onready var cards_container: HBoxContainer = $CardsContainer # Container for the upgrade cards
@onready var dim_background: ColorRect = $DimBackground # Visual element for dimming the background

func _ready():
	# Start hidden by setting visible property directly.
	# The display_options method will make it visible when called.
	visible = false

# This function is called by game.gd (typically deferred) to populate and show the level-up screen.
# options: An Array of Dictionaries, each representing an upgrade card's data.
func display_options(options: Array):
	# 1. Clear any old cards from the container from a previous level-up.
	for child in cards_container.get_children():
		child.queue_free()
		
	# Validate the upgrade card scene preload.
	if not is_instance_valid(UPGRADE_CARD_SCENE):
		push_error("ERROR (NewLevelUpScreen): UPGRADE_CARD_SCENE is not a valid scene. Check path in script.")
		visible = true # Show empty so game doesn't freeze the player.
		return
	
	print("NewLevelUpScreen: Creating ", options.size(), " new upgrade cards.")

	# 2. Create and populate new cards for the current options.
	for option_data in options:
		if not option_data is Dictionary:
			push_warning("NewLevelUpScreen: Received invalid option_data (not a Dictionary). Skipping."); continue
		
		var card_instance = UPGRADE_CARD_SCENE.instantiate()
		if not is_instance_valid(card_instance):
			push_error("ERROR (NewLevelUpScreen): Failed to instantiate UpgradeCard scene."); continue
		
		# Add card to the tree *before* calling methods on it.
		# This is a critical step to ensure its _ready() function runs and @onready vars are set.
		cards_container.add_child(card_instance)
		
		# Now that it's in the tree, we can safely call display_data to populate its UI.
		if card_instance.has_method("display_data"):
			card_instance.display_data(option_data)
		else:
			push_error("ERROR (NewLevelUpScreen): Instanced UpgradeCard scene is missing display_data() method. Check UpgradeCard.gd.")
			
		# Connect to its 'card_selected' signal to know when the player chooses an upgrade.
		if not card_instance.is_connected("card_selected", Callable(self, "_on_card_selected")):
			card_instance.card_selected.connect(Callable(self, "_on_card_selected"))
			
	# 3. Show the entire screen once all cards are set up.
	self.visible = true


# Called when an upgrade card is selected by the player.
# chosen_upgrade_data: A Dictionary containing the details of the chosen upgrade.
func _on_card_selected(chosen_upgrade_data: Dictionary):
	emit_signal("upgrade_chosen", chosen_upgrade_data) # Propagate the chosen upgrade to game.gd
	self.visible = false # Hide the level-up screen.
