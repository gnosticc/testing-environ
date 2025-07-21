# File: res/Scripts/Weapons/Projectiles/RimeheartAura.gd
# REVISED: Implemented a grace period. The aura now tracks enemies that have
# recently left its radius and will still trigger the Rimeheart effect if they
# are defeated within 2 seconds of exiting.

class_name RimeheartAura
extends Area2D

const RIMEHEART_EXPLOSION_SCENE = preload("res://Scenes/Weapons/Projectiles/RimeheartExplosion.tscn")
const GRACE_PERIOD_SECONDS: float = 2.0

var _owner_player: PlayerCharacter
var _weapon_stats: Dictionary
var _orb_damage: int

# --- NEW: Separate tracking for current and recent enemies ---
var _enemies_in_area: Array[BaseEnemy] = []
var _recently_exited_enemies: Dictionary = {} # { instance_id: exit_timestamp_usec }

@onready var _cleanup_timer: Timer = Timer.new()

func initialize(p_player: PlayerCharacter, p_weapon_stats: Dictionary, p_orb_damage: int, p_duration: float, p_game_node: Node):
	_owner_player = p_player
	_weapon_stats = p_weapon_stats
	_orb_damage = p_orb_damage
	
	var orbit_radius = float(_weapon_stats.get(&"orbit_radius", 75.0))
	var area_scale = float(_weapon_stats.get(&"area_scale", 1.0))
	var final_radius = orbit_radius * area_scale
	
	if get_node("CollisionShape2D").shape is CircleShape2D:
		get_node("CollisionShape2D").shape.radius = final_radius
	
	get_tree().create_timer(p_duration, true, false, true).timeout.connect(queue_free)

	if is_instance_valid(p_game_node) and p_game_node.has_signal("enemy_was_killed"):
		p_game_node.enemy_was_killed.connect(_on_any_enemy_killed)
	else:
		push_error("RimeheartAura: Could not connect to 'enemy_was_killed' signal on game node.")

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# NEW: Timer to periodically clean up old entries from the recently exited list.
	_cleanup_timer.name = "RimeheartCleanupTimer"
	_cleanup_timer.wait_time = 5.0 # Check every 5 seconds
	_cleanup_timer.timeout.connect(_cleanup_recent_enemies_list)
	add_child(_cleanup_timer)
	_cleanup_timer.start()

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not _enemies_in_area.has(body):
		var enemy = body as BaseEnemy
		_enemies_in_area.append(enemy)
		# If the enemy re-enters, remove it from the "recently exited" list.
		if _recently_exited_enemies.has(enemy.get_instance_id()):
			_recently_exited_enemies.erase(enemy.get_instance_id())

func _on_body_exited(body: Node2D):
	if body is BaseEnemy and _enemies_in_area.has(body):
		var enemy = body as BaseEnemy
		_enemies_in_area.erase(enemy)
		# NEW: Add the enemy to the "recently exited" list with a timestamp.
		_recently_exited_enemies[enemy.get_instance_id()] = Time.get_ticks_usec()

func _on_any_enemy_killed(_attacker_node: Node, killed_enemy_node: Node):
	if not is_instance_valid(self) or not is_instance_valid(killed_enemy_node):
		return

	var should_proc = false
	var enemy_id = killed_enemy_node.get_instance_id()

	# Check 1: Was the enemy defeated while currently inside the aura?
	if _enemies_in_area.has(killed_enemy_node):
		should_proc = true
	# Check 2: If not, was the enemy defeated shortly after leaving?
	elif _recently_exited_enemies.has(enemy_id):
		var exit_time = _recently_exited_enemies[enemy_id]
		var time_since_exit = (Time.get_ticks_usec() - exit_time) / 1000000.0
		if time_since_exit <= GRACE_PERIOD_SECONDS:
			should_proc = true
		# Remove the enemy from the list after checking to prevent multiple procs.
		_recently_exited_enemies.erase(enemy_id)

	if should_proc:
		var chance = float(_weapon_stats.get(&"rimeheart_chance", 0.25))
		if randf() < chance:
			_trigger_explosion(killed_enemy_node.global_position)

func _trigger_explosion(position: Vector2):
	var damage_percent = float(_weapon_stats.get(&"rimeheart_damage_percent", 0.5))
	var explosion_damage = int(_orb_damage * damage_percent)
	var explosion_radius = float(_weapon_stats.get(&"rimeheart_radius", 35.0))
	
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = explosion_radius
	query.transform = Transform2D(0, position)
	query.collision_mask = 8

	var weapon_tags: Array[StringName] = []
	if _weapon_stats.has("tags"):
		weapon_tags = _weapon_stats.get("tags")
		
	var results = space_state.intersect_shape(query)
	for result in results:
		if result.collider is BaseEnemy and is_instance_valid(result.collider) and not result.collider.is_dead():
			result.collider.take_damage(explosion_damage, _owner_player, {}, weapon_tags)
	
	if is_instance_valid(RIMEHEART_EXPLOSION_SCENE):
		var explosion = RIMEHEART_EXPLOSION_SCENE.instantiate() as RimeheartExplosion
		explosion.setup_visual(explosion_radius)
		explosion.global_position = position
		get_tree().current_scene.add_child.call_deferred(explosion)

# NEW: Housekeeping function to prevent the recently exited list from growing indefinitely.
func _cleanup_recent_enemies_list():
	var current_time = Time.get_ticks_usec()
	var keys_to_remove = []
	for enemy_id in _recently_exited_enemies:
		var exit_time = _recently_exited_enemies[enemy_id]
		var time_since_exit = (current_time - exit_time) / 1000000.0
		if time_since_exit > GRACE_PERIOD_SECONDS:
			keys_to_remove.append(enemy_id)
	
	for key in keys_to_remove:
		_recently_exited_enemies.erase(key)
