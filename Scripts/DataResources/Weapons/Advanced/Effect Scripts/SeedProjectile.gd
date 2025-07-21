# --- Path: res://Scripts/Weapons/Advanced/Effects/SeedProjectile.gd ---
class_name SeedProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# FIX: Add a reference to the collision shape
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _target_position: Vector2
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats

const SEED_EXPLOSION_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/SeedExplosion.tscn")
const ENTANGLING_ROOTS_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/EntanglingRoots.tscn")

func initialize(p_target_pos: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	var projectile_scale = float(p_stats.get(&"seed_projectile_scale", 1.0))
	animated_sprite.scale = Vector2.ONE * projectile_scale
	# FIX: Scale the collision shape to match the sprite
	if is_instance_valid(collision_shape):
		collision_shape.scale = Vector2.ONE * projectile_scale
	
	var spawn_radius = float(p_stats.get(&"seed_spawn_radius", 200.0))
	var random_offset = Vector2(randf_range(-spawn_radius, spawn_radius), randf_range(-spawn_radius, spawn_radius))
	_target_position = p_target_pos + random_offset
	
	var tween = create_tween()
	tween.tween_property(self, "global_position", _target_position, 0.5).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_on_landed)

func _on_landed():
	if _specific_stats.get(&"seeds_explode", false):
		var explosion = SEED_EXPLOSION_SCENE.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = self.global_position
		explosion.initialize(_specific_stats, _owner_player_stats)
		
	var root_pool = ENTANGLING_ROOTS_SCENE.instantiate()
	get_tree().current_scene.add_child(root_pool)
	root_pool.global_position = self.global_position
	root_pool.initialize(_specific_stats, _owner_player_stats)
	
	queue_free()
