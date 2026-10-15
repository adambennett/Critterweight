extends Node
## Autoload "Mods": discovers user mod packages, validates manifests, resolves dependencies and
## load order, persists enabled mod sets, and feeds Content.reload(). Trust model: docs/MODDING.md.

signal mods_changed()

var enabled_packages: Array = []


func _ready() -> void:
	pass
