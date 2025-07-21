# --- Path: res://Scripts/Weapons/Advanced/PolearmAttack.gd ---
class_name PolearmAttack
extends Node2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var pivot: Node2D = $Pivot
@onready var animated_sprite: AnimatedSprite2D = $Pivot/AnimatedSprite2D
@onready var sweep_hitbox: Area2D = $Pivot/SweepHitbox
@onready var thrust_hitbox: Area2D = $Pivot/ThrustHitbox
@onready var sweet_spot_hitbox: Area2D = $Pivot/SweetSpotHitbox
@onready var spear_tip_marker: Marker2D = $Pivot/AnimatedSprite2D/SpearTipMarker

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager
var _attack_type: String
var _enemies_hit: Array[Node2D] = []

func _ready():
	animation_player.animation_finished.connect(_on_animation_finished)
	sweep_hitbox.body_entered.connect(_on_body_entered)
	thrust_hitbox.body_entered.connect(_on_body_entered)
	sweet_spot_hitbox.body_entered.connect(_on_sweet_spot_body_entered)

func initialize(p_attack_type: String, p_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	print_debug("PolearmAttack stats: ", p_stats)
	_attack_type = p_attack_type
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	
	var owner_player = _owner_player_stats.get_parent()
	
	sweep_hitbox.get_node("CollisionShape2D").disabled = true
	thrust_hitbox.get_node("CollisionShape2D").disabled = true
	sweet_spot_hitbox.get_node("CollisionShape2D").disabled = true
	
	if _attack_type == "thrust":
		self.rotation = (owner_player.get_global_mouse_position() - owner_player.global_position).angle()
		animated_sprite.play("thrust")
		var length_scale = float(_specific_stats.get(&"thrust_length_scale", 1.0))
		thrust_hitbox.scale.y = length_scale
		thrust_hitbox.get_node("CollisionShape2D").disabled = false
		animation_player.play("thrust")
	else: # "sweep"
		pivot.position = Vector2.ZERO
		pivot.rotation = 0
		animated_sprite.play("sweep")
		var radius_scale = float(_specific_stats.get(&"sweep_radius_scale", 1.0))
		sweep_hitbox.scale = Vector2.ONE * radius_scale
		sweep_hitbox.get_node("CollisionShape2D").disabled = false
		animation_player.play("sweep")

func _activate_sweet_spot():
	if _specific_stats.get(&"has_tip_of_the_spear", false):
		sweet_spot_hitbox.global_position = spear_tip_marker.global_position
		sweet_spot_hitbox.get_node("CollisionShape2D").disabled = false

func _deactivate_sweet_spot():
	sweet_spot_hitbox.get_node("CollisionShape2D").disabled = true

func _on_sweet_spot_body_entered(body: Node2D):
	if not (body is BaseEnemy) or _enemies_hit.has(body): return
	var enemy = body as BaseEnemy
	if enemy.is_dead(): return
	
	_enemies_hit.append(enemy)
	
	var damage_percent = float(_specific_stats.get(&"thrust_damage_percentage", 2.5))
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var calculated_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	
	var crit_damage_bonus = 1.0
	calculated_damage *= (_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER) + crit_damage_bonus)
	
	
	# --- NEW DEBUG PRINT ---
	print("--- POLEARM SWEET SPOT CRIT ---")
	print("  Final Damage Dealt: ", int(round(calculated_damage)))
	print("-----------------------------")
	# --- END DEBUG PRINT ---
	
	enemy.take_damage(int(round(calculated_damage)), _owner_player_stats.get_parent(), {}, weapon_tags) # Pass tags

func _on_body_entered(body: Node2D):
	if not (body is BaseEnemy) or _enemies_hit.has(body): return
	var enemy = body as BaseEnemy
	if enemy.is_dead(): return
	
	_enemies_hit.append(enemy)
	
	var damage_percent = float(_specific_stats.get(&"sweep_damage_percentage", 1.4))
	if _attack_type == "thrust":
		damage_percent = float(_specific_stats.get(&"thrust_damage_percentage", 2.5))
	
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var calculated_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	
	if randf() < _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE):
		calculated_damage *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
	
	enemy.take_damage(int(round(calculated_damage)), _owner_player_stats.get_parent(), {}, weapon_tags) # Pass tags
	
	if _attack_type == "sweep" and _specific_stats.get(&"has_momentum", false):
		var rogue_levels = (_owner_player_stats.get_parent() as PlayerCharacter).get_total_levels_for_class(PlayerCharacter.BasicClass.ROGUE)
		var speed_bonus = float(rogue_levels) * 0.03
		var momentum_buff = load("res://DataResources/StatusEffects/momentum_buff.tres") as StatusEffectData
		if is_instance_valid(momentum_buff):
			_owner_player_stats.get_parent().status_effect_component.apply_effect(momentum_buff, _owner_player_stats.get_parent(), {}, 2.0, speed_bonus, &"momentum_buff")
	
	if _attack_type == "sweep" and _specific_stats.get(&"has_crippling_sweep", false):
		var slow_status = load("res://DataResources/StatusEffects/slow_status.tres") as StatusEffectData
		if is_instance_valid(slow_status):
			enemy.status_effect_component.apply_effect(slow_status, _owner_player_stats.get_parent())

func _on_animation_finished(_anim_name):
	if _attack_type == "thrust" and _specific_stats.get(&"has_retreating_sweep", false):
		if not self.scene_file_path.is_empty():
			var sweep_scene = load(self.scene_file_path) as PackedScene
			if is_instance_valid(sweep_scene):
				var sweep_instance = sweep_scene.instantiate()
				get_parent().add_child(sweep_instance)
				sweep_instance.global_position = global_position
				if sweep_instance.has_method("initialize"):
					sweep_instance.initialize("sweep", _specific_stats, _owner_player_stats, _weapon_manager)
		else:
			push_error("PolearmAttack: Cannot spawn Retreating Sweep because scene_file_path is empty.")

	queue_free()
