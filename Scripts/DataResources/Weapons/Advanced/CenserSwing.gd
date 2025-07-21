# --- Path: res://Scripts/Weapons/Advanced/CenserSwing.gd ---
class_name CenserSwing
extends Node2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var pivot: Area2D = $Pivot

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _enemies_hit: Array[Node2D] = []

const SEED_PROJECTILE_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/SeedProjectile.tscn")
const THORN_PROJECTILE_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/ThornProjectile.tscn")
const ENTANGLING_ROOTS_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/EntanglingRoots.tscn") # For Garden of Thorns

func _ready():
	pivot.body_entered.connect(_on_body_entered)
	animation_player.animation_finished.connect(_on_animation_finished)
	
	var shape_node = pivot.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(shape_node) and is_instance_valid(shape_node.shape):
		shape_node.shape = shape_node.shape.duplicate()

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	var weapon_length_scale = float(p_stats.get(&"swing_length_scale", 1.0))
	var weapon_width_scale = float(p_stats.get(&"swing_width_scale", 1.0))
	
	var global_aoe_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	
	var final_length_scale = weapon_length_scale * global_aoe_mult
	var final_width_scale = weapon_width_scale * global_aoe_mult
	
	pivot.scale = Vector2(final_length_scale, final_width_scale)
	
	animation_player.play("swing")

func _on_body_entered(body: Node2D):
	if not (body is BaseEnemy) or _enemies_hit.has(body): return
	var enemy = body as BaseEnemy
	if enemy.is_dead(): return
	
	_enemies_hit.append(enemy)
	
	var owner_player = _owner_player_stats.get_parent()
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")

	# --- REFACTORED DAMAGE CALCULATION ---
	var base_damage = _owner_player_stats.get_calculated_base_damage(float(_specific_stats.get(&"swing_damage_percentage", 1.2)))
	var calculated_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	# --- END REFACTOR ---
	
	var was_rooted = false
	
	if is_instance_valid(enemy.status_effect_component) and enemy.status_effect_component.has_status_effect(&"rooted"):
		was_rooted = true
		var bonus_multiplier = float(_specific_stats.get(&"rooted_bonus_damage_multiplier", 2.0))
		calculated_damage *= bonus_multiplier
		enemy.status_effect_component.remove_effect_by_unique_id(&"rooted")
	
	enemy.take_damage(int(round(calculated_damage)), owner_player, {}, weapon_tags) # Pass tags
	
	call_deferred("_spawn_seed", enemy.global_position)
	
	if was_rooted:
		call_deferred("_spawn_thorn_burst", enemy.global_position)

func _spawn_seed(spawn_position: Vector2):
	if not is_instance_valid(SEED_PROJECTILE_SCENE): return
	var seed = SEED_PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(seed)
	# FIX: Set the seed's initial position to the player's position before starting the tween.
	seed.global_position = self.global_position
	seed.initialize(spawn_position, _specific_stats, _owner_player_stats)

func _spawn_thorn_burst(spawn_position: Vector2):
	if not is_instance_valid(THORN_PROJECTILE_SCENE): return
	
	var num_thorns = 8
	var angle_step = TAU / float(num_thorns)
	
	for i in range(num_thorns):
		var thorn = THORN_PROJECTILE_SCENE.instantiate()
		get_tree().current_scene.add_child(thorn)
		thorn.global_position = spawn_position
		var direction = Vector2.RIGHT.rotated(i * angle_step)
		thorn.initialize(direction, _specific_stats, _owner_player_stats)
		
	# --- FIX: Garden of Thorns Logic ---
	if _specific_stats.get(&"burst_creates_pool", false):
		var root_pool = ENTANGLING_ROOTS_SCENE.instantiate()
		get_tree().current_scene.add_child(root_pool)
		root_pool.global_position = spawn_position
		# The new pool uses the same stats as the original
		root_pool.initialize(_specific_stats, _owner_player_stats)

func _on_animation_finished(_anim_name: StringName):
	queue_free()
