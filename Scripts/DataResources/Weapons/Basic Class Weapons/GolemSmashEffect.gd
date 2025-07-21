# File: res/Scripts/Weapons/Summons/GolemSmashEffect.gd
# NEW SCRIPT: Handles the one-time AoE damage for the Crushing Blows upgrade.

class_name GolemSmashEffect
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var _golem_node: Node2D

func initialize(p_position: Vector2, damage: int, golem_stats: Dictionary, owner_player: PlayerCharacter, p_golem_node: Node2D):
	_golem_node = p_golem_node

	global_position = p_position
	animated_sprite.play("smash")
	animated_sprite.animation_finished.connect(queue_free)

	var radius = float(golem_stats.get(&"crushing_blow_radius", 35.0))
	
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = radius
	query.transform = global_transform
	# Corrected: Layer 4 corresponds to bit 3. The mask value is 2^3 = 8.
	query.collision_mask = 8 

	var results = space_state.intersect_shape(query)
	for result in results:
		if result.collider is BaseEnemy and not result.collider.is_dead():
			var weapon_tags: Array[StringName] = []
			if is_instance_valid(_golem_node) and _golem_node.has_method("get"):
				var golem_specific_stats = _golem_node.get("specific_weapon_stats")
				if golem_specific_stats.has("tags"):
					weapon_tags = golem_specific_stats.get("tags")
			
			result.collider.take_damage(damage, owner_player, {}, weapon_tags)
