# File: res://Scripts/Singletons/CombatEvents.gd (NEW SCRIPT - ADD AS AUTOLOAD)
# Purpose: A global event bus to decouple game systems.

extends Node

# Emitted when any StatusEffectComponent successfully applies a status.
# owner: The node that has the status (e.g., an enemy).
# effect_id: The StringName ID of the status (e.g., &"stun", &"root").
# source: The node that caused the status to be applied (e.g., the player).
signal status_effect_applied(owner: Node, effect_id: StringName, source: Node)

# Emitted by a dying enemy that has the "death_mark" status.
# The player will listen for this to spawn a new Shadow Clone.
signal death_mark_triggered(enemy_position: Vector2, clone_stats: Dictionary)
signal lingering_charge_triggered(p_position: Vector2, p_weapon_stats: Dictionary, p_source_player: Node, p_dying_enemy: Node)
# NEW: Emitted by a "Soaked" enemy when it takes damage from any weapon.
# The ExperimentalMaterialsManager will listen for this to trigger the appropriate reaction.
# enemy_node: The enemy that was hit.
# weapon_tags: The tags of the weapon that dealt the damage.
signal catalytic_reaction_requested(enemy_node: BaseEnemy, weapon_tags: Array[StringName])
