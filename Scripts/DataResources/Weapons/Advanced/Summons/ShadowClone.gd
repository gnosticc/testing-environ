# --- Path: res://Scripts/Weapons/Advanced/Summons/ShadowClone.gd ---
class_name ShadowClone
extends Node2D

@export var slash_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var slash_spawn_point: Marker2D = $SlashSpawnPoint

const CALTROP_CONTROLLER_SCENE = preload("res://Scenes/Weapons/Advanced/Summons/CaltropController.tscn")

func initialize(direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	self.rotation = 0
	if direction.x < 0:
		animated_sprite.flip_h = true
	else:
		animated_sprite.flip_h = false
	
	if _specific_stats.get(&"clone_has_stun_aura", false):
		_execute_stun_aura()
	
	var slash_count = int(_specific_stats.get(&"clone_slash_count", 1))
	var total_duration = 0.0
	
	var initial_slash_delay = 0.3
	
	# FIX: Corrected Timer Syntax for Godot 4
	get_tree().create_timer(initial_slash_delay).timeout.connect(
		func():
			for i in range(slash_count):
				var subsequent_delay = i * 0.25
				get_tree().create_timer(subsequent_delay).timeout.connect(_spawn_slash)
				total_duration = subsequent_delay
	)

	get_tree().create_timer(initial_slash_delay + total_duration + 0.5).timeout.connect(_on_lifetime_expired)

func _spawn_slash():
	if not is_instance_valid(self) or not is_instance_valid(slash_scene): return
	var slash = slash_scene.instantiate()
	
	var slash_direction = Vector2.RIGHT
	if animated_sprite.flip_h:
		slash_direction = Vector2.LEFT
		
	slash.rotation = slash_direction.angle()
	
	add_child(slash)
	slash.global_position = slash_spawn_point.global_position
	
	if slash.has_method("initialize"):
		slash.initialize(_specific_stats, _owner_player_stats)

func _execute_stun_aura():
	var stun_radius = 60.0
	var stun_status = load("res://DataResources/StatusEffects/stun_status.tres") as StatusEffectData
	if not is_instance_valid(stun_status): return

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new(); query.shape.radius = stun_radius
	query.transform = global_transform
	query.collision_mask = 8
	
	var results = space_state.intersect_shape(query)
	for result in results:
		var enemy = result.collider as BaseEnemy
		if is_instance_valid(enemy) and not enemy.is_dead() and is_instance_valid(enemy.status_effect_component):
			enemy.status_effect_component.apply_effect(stun_status, _owner_player_stats.get_parent(), {}, 0.5)

# FIX: Replaced _notification with a new function called by a timer
func _on_lifetime_expired():
	if _specific_stats.get(&"clone_leaves_caltrops", false):
		if is_instance_valid(self) and is_inside_tree():
			var caltrop_controller = CALTROP_CONTROLLER_SCENE.instantiate()
			# FIX: Add the controller to the main scene, NOT this node.
			get_tree().current_scene.add_child(caltrop_controller)
			caltrop_controller.global_position = self.global_position
			if caltrop_controller.has_method("initialize"):
				var clone_damage_percent = float(_specific_stats.get(&"clone_damage_percentage", 1.5))
				var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
				var base_damage = _owner_player_stats.get_calculated_base_damage(clone_damage_percent)
				var clone_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
				caltrop_controller.initialize(clone_damage, _owner_player_stats.get_parent())
		else:
			push_error("ShadowClone: Lifetime expired but node was not in tree. Cannot spawn caltrops.")
	
	queue_free()
