# --- Path: res://Scripts/Weapons/Advanced/Summons/ShadowCloneSlash.gd ---
class_name ShadowCloneSlash
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionPolygon2D = $CollisionShape2D

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _enemies_hit: Array[Node2D] = []

func _ready():
	animated_sprite.animation_finished.connect(queue_free)
	body_entered.connect(_on_body_entered)
	
func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	var area_scale = float(_specific_stats.get(&"clone_area_scale", 1.0))
	scale = Vector2.ONE * area_scale
	
	animated_sprite.play("default")

func _on_body_entered(body: Node2D):
	if not (body is BaseEnemy) or _enemies_hit.has(body): return
	
	var enemy = body as BaseEnemy
	if enemy.is_dead(): return
	
	_enemies_hit.append(enemy)
	
	var owner_player = _owner_player_stats.get_parent()
	var clone_damage_percent = float(_specific_stats.get(&"clone_damage_percentage", 1.5))
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")
	var base_damage = _owner_player_stats.get_calculated_base_damage(clone_damage_percent)
	var damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	
	# --- FIX for Shadow's Embrace on killing blow ---
	var has_embrace = _specific_stats.get(&"has_shadows_embrace", false)
	var death_mark_applied = false
	
	if has_embrace:
		var death_mark_status = load("res://DataResources/StatusEffects/death_mark_status.tres") as StatusEffectData
		if is_instance_valid(death_mark_status) and is_instance_valid(enemy.status_effect_component):
			enemy.status_effect_component.apply_effect(death_mark_status, owner_player, _specific_stats)
			death_mark_applied = true

	enemy.take_damage(int(round(damage)), owner_player, {}, weapon_tags) # Pass tags

	# Check if the enemy is now dead AND the mark was just applied
	if has_embrace and death_mark_applied and enemy.is_dead():
		CombatEvents.emit_signal("death_mark_triggered", enemy.global_position, _specific_stats)
