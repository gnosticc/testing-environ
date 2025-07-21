# --- Path: res://Scripts/Weapons/Advanced/ShurikenProjectile.gd ---
class_name ShurikenProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _direction: Vector2
var _speed: float
var _enemies_hit: Array[Node2D] = []
var _pierce_count: int = 0

const SHADOW_CLONE_SCENE = preload("res://Scenes/Weapons/Advanced/Summons/ShadowClone.tscn")

func _ready():
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	rotation = _direction.angle()
	
	_speed = float(_specific_stats.get(&"projectile_speed", 450.0)) * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	_pierce_count = int(_specific_stats.get(&"pierce_count", 0))
	
	var lifetime = 1.0 * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = lifetime
	lifetime_timer.start()
	
	animated_sprite.play("fly")

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_lifetime_expired():
	_spawn_clone_and_destroy()

func _on_body_entered(body: Node2D):
	if not (body is BaseEnemy) or _enemies_hit.has(body): return
		
	var enemy = body as BaseEnemy
	if enemy.is_dead(): return
	
	_enemies_hit.append(enemy)
	
	var owner_player = _owner_player_stats.get_parent()
	var weapon_damage_percent = float(_specific_stats.get(&"weapon_damage_percentage", 1.2))
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")
	var base_damage = _owner_player_stats.get_calculated_base_damage(weapon_damage_percent)
	var calculated_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	
	var weapon_crit_chance = float(_specific_stats.get(&"crit_chance", 0.0))
	if randf() < (_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE) + weapon_crit_chance):
		calculated_damage *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)

	enemy.take_damage(int(round(calculated_damage)), owner_player, {}, weapon_tags) # Pass tags

	
	if _specific_stats.get(&"has_poison", false):
		var poison_status = load("res://DataResources/StatusEffects/poison_status.tres") as StatusEffectData
		if is_instance_valid(poison_status) and is_instance_valid(enemy.status_effect_component):
			if randf() < 0.35:
				enemy.status_effect_component.apply_effect(poison_status, owner_player)
	
	# FIX: Spawn a clone on every hit if the weapon can pierce.
	if _pierce_count > 0:
		_pierce_count -= 1
		_spawn_clone() # Spawn a clone but don't destroy the projectile yet.
		return
		
	# This runs only on the final hit or if there's no piercing.
	_spawn_clone_and_destroy()

func _spawn_clone():
	if not is_instance_valid(SHADOW_CLONE_SCENE): return
	var clone = SHADOW_CLONE_SCENE.instantiate()
	get_tree().current_scene.add_child(clone)
	clone.global_position = self.global_position
	if clone.has_method("initialize"):
		clone.initialize(_direction, _specific_stats, _owner_player_stats)

func _spawn_clone_and_destroy():
	_spawn_clone()
	queue_free()
