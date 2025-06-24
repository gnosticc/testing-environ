# File: res://Scripts/Singletons/CombatEvents.gd (NEW SCRIPT - ADD AS AUTOLOAD)
# Purpose: A global event bus to decouple game systems.

extends Node

# Emitted when any StatusEffectComponent successfully applies a status.
# owner: The node that has the status (e.g., an enemy).
# effect_id: The StringName ID of the status (e.g., &"stun", &"root").
# source: The node that caused the status to be applied (e.g., the player).
signal status_effect_applied(owner: Node, effect_id: StringName, source: Node)
