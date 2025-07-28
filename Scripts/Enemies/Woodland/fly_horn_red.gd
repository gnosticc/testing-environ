# --- fly_horn_red.gd ---
# BaseEnemy.gd script to handle all logic, including signal connections.

extends BaseEnemy

func _ready():
	# --- Static Stats for Green Slime (as per user specification) ---
	#max_health = 22
	#contact_damage = 5
	#speed = 38.0
	#experience_to_drop = 2
	#armor = 0
	# --- End Static Stats ---

	super() # Calls BaseEnemy's _ready AFTER stats are set for this specific type
	# BaseEnemy's _ready will now correctly initialize current_health and health_bar
	
	# If you have specific animations for slime different from "move" or "idle"
	# _play_animation("slime_move")
