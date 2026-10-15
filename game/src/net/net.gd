extends Node
## Autoload "Net": networking sessions (listen server, dedicated server, client), lobby state,
## LAN discovery. Implementation and protocol: docs/NETWORKING.md. Contract (ARCHITECTURE.md):
## host(cfg), join(addr, port, password), start_dedicated(cfg), leave(), shutdown().

signal status_changed(text: String)


func shutdown() -> void:
	pass
