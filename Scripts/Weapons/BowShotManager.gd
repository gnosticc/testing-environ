#// --- File: BowShotManager.gd (for Rogue Bow) ---
#// (From Canvas ID: bow_shot_manager_rogue_v1)
#// Attach to the root Node2D of BowShotManager.tscn
extends Node2D

const ARROW_PROJECTILE_SCENE = preload("res://Scenes/Weapons/Projectiles/ArrowProjectile.tscn") # ADJUST PATH
const SHOT_DELAY: float = 0.25 

var owner_stats_for_arrow: Dictionary = {} 
var player_reference_global_position: Vector2 

func _ready():
	if not ARROW_PROJECTILE_SCENE: print("ERROR (BowShotManager): ARROW_PROJECTILE_SCENE not loaded!"); queue_free(); return
	if player_reference_global_position == Vector2.ZERO: 
		print("ERROR (BowShotManager): Player's global position not set.")
		var players = get_tree().get_nodes_in_group("player_char_group")
		if players.size() > 0 and is_instance_valid(players[0]): player_reference_global_position = players[0].global_position
		else: queue_free(); return
			
	_fire_arrow(player_reference_global_position, Vector2.LEFT)
	var delay_timer = get_tree().create_timer(SHOT_DELAY)
	await delay_timer.timeout 
	_fire_arrow(player_reference_global_position, Vector2.RIGHT)
	queue_free()

func _fire_arrow(spawn_position: Vector2, direction: Vector2):
	if not ARROW_PROJECTILE_SCENE: return
	var arrow_instance = ARROW_PROJECTILE_SCENE.instantiate()
	var attacks_parent = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if not is_instance_valid(attacks_parent): attacks_parent = get_tree().current_scene 
	if is_instance_valid(attacks_parent): attacks_parent.add_child(arrow_instance)
	else: arrow_instance.queue_free(); return

	arrow_instance.global_position = spawn_position
	if arrow_instance.has_method("set_direction"): arrow_instance.set_direction(direction)
	if arrow_instance.has_method("set_owner_stats"): arrow_instance.set_owner_stats(owner_stats_for_arrow)

func set_shooter_info(p_spawn_position: Vector2, stats_for_projectile: Dictionary):
	player_reference_global_position = p_spawn_position
	owner_stats_for_arrow = stats_for_projectile
