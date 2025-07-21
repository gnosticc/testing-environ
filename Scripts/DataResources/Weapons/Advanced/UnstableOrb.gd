# File: res://Scripts/Weapons/Advanced/UnstableOrb.gd
# Attach to: UnstableOrb.tscn (Root Area2D)
# Purpose: Controls the orb projectile's movement, collision, and detonation logic.

class_name UnstableOrb
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

const FIRE_EXPLOSION_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/ChromaticFireExplosion.tscn")
const ICE_SHARD_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/ChromaticIceShard.tscn")
const NATURE_POOL_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/ChromaticNaturePool.tscn")

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager
var _target_enemy: BaseEnemy
var _direction: Vector2
var _speed: float

func _ready():
	lifetime_timer.timeout.connect(_detonate)
	body_entered.connect(_on_body_entered)

func initialize(p_target: BaseEnemy, p_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	_target_enemy = p_target
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager

	_speed = float(_specific_stats.get(&"orb_projectile_speed", 300.0)) * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	
	var base_scale = float(_specific_stats.get(&"orb_projectile_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2.ONE * base_scale * global_size_mult
	
	var lifetime = float(_specific_stats.get(&"orb_lifetime", 2.0))
	lifetime_timer.wait_time = lifetime
	lifetime_timer.start()
	animated_sprite.play("fly")

func _physics_process(delta: float):
	if is_instance_valid(_target_enemy) and not _target_enemy.is_dead():
		_direction = ( _target_enemy.global_position - global_position).normalized()
	
	global_position += _direction * _speed * delta
	rotation = _direction.angle()

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead():
		var owner_player = _owner_player_stats.get_parent()
		var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
		var damage_percent = float(_specific_stats.get("orb_contact_damage_percentage", 1.0))
		var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
		var damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)		
		body.take_damage(damage, owner_player, {}, weapon_tags)
		
		call_deferred("_detonate")

func _detonate():
	if not is_instance_valid(self): return

	var has_attunement = _specific_stats.get(&"has_elemental_attunement", false)
	
	if has_attunement:
		_spawn_fire_effect()
		_spawn_ice_effect()
		_spawn_nature_effect()
	else:
		var choice = randi() % 3
		match choice:
			0: _spawn_fire_effect()
			1: _spawn_ice_effect()
			2: _spawn_nature_effect()

	if _specific_stats.get(&"has_chromatic_overload", false):
		# Prevent infinite loops by creating a copy of stats without the overload flag.
		var next_orb_stats = _specific_stats.duplicate(true)
		next_orb_stats[&"has_chromatic_overload"] = false
		
		var controller_scene = load("res://Scenes/Weapons/Advanced/ChromaticAberrationController.tscn")
		var controller = controller_scene.instantiate()
		get_tree().current_scene.add_child(controller)
		controller.global_position = self.global_position # Spawn from impact point
		if controller.has_method("set_attack_properties"):
			controller.set_attack_properties(Vector2.ZERO, next_orb_stats, _owner_player_stats, _weapon_manager)

	queue_free()

func _spawn_fire_effect():
	var explosion = FIRE_EXPLOSION_SCENE.instantiate()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = self.global_position
	if explosion.has_method("initialize"):
		explosion.initialize(_specific_stats, _owner_player_stats)

func _spawn_ice_effect():
	var num_projectiles = int(_specific_stats.get(&"ice_shard_count", 8))
	if _specific_stats.get(&"has_violent_snap", false):
		num_projectiles *= 2
		
	var angle_step = TAU / float(num_projectiles)
	for i in range(num_projectiles):
		var shard = ICE_SHARD_SCENE.instantiate()
		get_tree().current_scene.add_child(shard)
		shard.global_position = self.global_position
		var direction = Vector2.RIGHT.rotated(i * angle_step)
		if shard.has_method("initialize"):
			shard.initialize(direction, _specific_stats, _owner_player_stats)

func _spawn_nature_effect():
	var pool = NATURE_POOL_SCENE.instantiate()
	get_tree().current_scene.add_child(pool)
	pool.global_position = self.global_position
	if pool.has_method("initialize"):
		pool.initialize(_specific_stats, _owner_player_stats)
