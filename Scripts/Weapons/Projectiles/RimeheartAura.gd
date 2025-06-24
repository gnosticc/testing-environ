# File: res://Scripts/Weapons/Projectiles/RimeheartAura.gd
# MODIFIED: Logic updated to use a more robust setup() function on the explosion
# instance before adding it to the scene, avoiding timing issues.

class_name RimeheartAura
extends Area2D

const RIMEHEART_EXPLOSION_SCENE = preload("res://Scenes/Weapons/Projectiles/RimeheartExplosion.tscn")

var _owner_player: PlayerCharacter
var _weapon_stats: Dictionary
var _orb_damage: int

func initialize(p_player: PlayerCharacter, p_weapon_stats: Dictionary, p_orb_damage: int, p_duration: float):
	_owner_player = p_player
	_weapon_stats = p_weapon_stats
	_orb_damage = p_orb_damage
	
	var orbit_radius = float(_weapon_stats.get(&"orbit_radius", 75.0))
	var area_scale = float(_weapon_stats.get(&"area_scale", 1.0))
	var final_radius = orbit_radius * area_scale
	
	if get_node("CollisionShape2D").shape is CircleShape2D:
		get_node("CollisionShape2D").shape.radius = final_radius
	
	get_tree().create_timer(p_duration, true, false, true).timeout.connect(queue_free)

func _ready():
	body_entered.connect(_on_enemy_entered)

func _on_enemy_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		var enemy_target = body as BaseEnemy
		if not enemy_target.is_connected("tree_exiting", Callable(self, "_on_tracked_enemy_death")):
			enemy_target.tree_exiting.connect(
				_on_tracked_enemy_death.bind(enemy_target), 
				CONNECT_ONE_SHOT
			)

func _on_tracked_enemy_death(enemy_node: BaseEnemy):
	if not is_instance_valid(enemy_node): return
	
	var chance = float(_weapon_stats.get(&"rimeheart_chance", 0.25))
	if randf() < chance:
		var damage_percent = float(_weapon_stats.get(&"rimeheart_damage_percent", 0.5))
		var explosion_damage = int(_orb_damage * damage_percent)
		var explosion_radius = float(_weapon_stats.get(&"rimeheart_radius", 35.0))
		
		var space_state = get_world_2d().direct_space_state
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = CircleShape2D.new()
		query.shape.radius = explosion_radius
		query.transform = Transform2D(0, enemy_node.global_position)
		query.collision_mask = enemy_node.collision_layer
		
		var results = space_state.intersect_shape(query)
		for result in results:
			if result.collider is BaseEnemy and is_instance_valid(result.collider) and not result.collider.is_dead():
				result.collider.take_damage(explosion_damage, _owner_player, {})
		
		if is_instance_valid(RIMEHEART_EXPLOSION_SCENE):
			var explosion = RIMEHEART_EXPLOSION_SCENE.instantiate() as RimeheartExplosion
			
			# Call setup BEFORE adding to the scene tree.
			explosion.setup_visual(explosion_radius)
			explosion.global_position = enemy_node.global_position
			
			# Defer adding the configured node to the tree.
			get_tree().current_scene.add_child.call_deferred(explosion)
