class_name ArenaEditCommands
## Undo/redo for the arena editor: a bounded command stack plus the command types. Every edit the
## editor makes goes through `Stack.execute(cmd)` (or `push_applied(cmd)` for drags that were
## previewed live), so any sequence of edits can be undone and redone exactly.
## Commands hold copies of the data they need; they never hold Node references.


class Command:
	extends RefCounted
	var label := ""

	func apply(_m: ArenaEditModel) -> void:
		pass

	func revert(_m: ArenaEditModel) -> void:
		pass


## Adds items (each carries its uid). Reverting removes them again.
class AddItems:
	extends Command
	var items: Array = []

	func _init(list: Array, lbl := "Add") -> void:
		for it in list:
			items.append((it as Dictionary).duplicate(true))
		label = lbl

	func apply(m: ArenaEditModel) -> void:
		for it in items:
			m.insert_item((it as Dictionary).duplicate(true))

	func revert(m: ArenaEditModel) -> void:
		for i in range(items.size() - 1, -1, -1):
			m.remove_item(int(items[i]["uid"]))


## Removes items; reverting reinserts them at their original indices.
class RemoveItems:
	extends Command
	var entries: Array = []      ## [[index, item]] ascending by index

	func _init(m: ArenaEditModel, uids: Array, lbl := "Delete") -> void:
		label = lbl
		for uid in uids:
			var i := m.index_of(int(uid))
			if i >= 0:
				entries.append([i, (m.items[i] as Dictionary).duplicate(true)])
		entries.sort_custom(func(a, b): return int(a[0]) < int(b[0]))

	func apply(m: ArenaEditModel) -> void:
		for e in entries:
			m.remove_item(int(e[1]["uid"]))

	func revert(m: ArenaEditModel) -> void:
		for e in entries:
			m.insert_item((e[1] as Dictionary).duplicate(true), int(e[0]))


## Replaces item contents (move / rotate / team / params). changes: [[uid, before, after]]
class ModifyItems:
	extends Command
	var changes: Array = []

	func _init(list: Array, lbl := "Edit") -> void:
		for c in list:
			changes.append([int(c[0]), (c[1] as Dictionary).duplicate(true), (c[2] as Dictionary).duplicate(true)])
		label = lbl

	func apply(m: ArenaEditModel) -> void:
		for c in changes:
			m.replace_item(int(c[0]), c[2])

	func revert(m: ArenaEditModel) -> void:
		for c in changes:
			m.replace_item(int(c[0]), c[1])


## Sets a layout field (name, variant, size, modes, flags, removed_builtins ...).
class SetField:
	extends Command
	var key := ""
	var before
	var after

	func _init(k: String, b, a, lbl := "") -> void:
		key = k
		before = b.duplicate(true) if b is Array or b is Dictionary else b
		after = a.duplicate(true) if a is Array or a is Dictionary else a
		label = lbl if lbl != "" else "Change %s" % k

	func apply(m: ArenaEditModel) -> void:
		m.set_field(key, after)

	func revert(m: ArenaEditModel) -> void:
		m.set_field(key, before)


## Whole-document swap (new layout, base change, loading an example) — still undoable.
class SetState:
	extends Command
	var before := {}
	var after := {}

	func _init(b: Dictionary, a: Dictionary, lbl := "Replace layout") -> void:
		before = b.duplicate(true)
		after = a.duplicate(true)
		label = lbl

	func apply(m: ArenaEditModel) -> void:
		m.restore(after)

	func revert(m: ArenaEditModel) -> void:
		m.restore(before)


class Batch:
	extends Command
	var cmds: Array = []

	func _init(list: Array, lbl := "Edit") -> void:
		cmds = list.duplicate()
		label = lbl

	func apply(m: ArenaEditModel) -> void:
		for c in cmds:
			(c as Command).apply(m)

	func revert(m: ArenaEditModel) -> void:
		for i in range(cmds.size() - 1, -1, -1):
			(cmds[i] as Command).revert(m)


## Bounded undo/redo stack bound to one model.
class Stack:
	extends RefCounted
	signal changed()
	var model: ArenaEditModel
	var done: Array = []
	var undone: Array = []
	var limit := 200
	var clean_index := 0          ## done.size() at the last save (dirty tracking)

	func _init(m: ArenaEditModel) -> void:
		model = m

	func execute(cmd: Command) -> void:
		cmd.apply(model)
		push_applied(cmd)

	## Records a command whose effect is already in the model (live-previewed drags).
	func push_applied(cmd: Command) -> void:
		done.append(cmd)
		undone.clear()
		if done.size() > limit:
			done.pop_front()
			clean_index -= 1
		changed.emit()

	func can_undo() -> bool:
		return not done.is_empty()

	func can_redo() -> bool:
		return not undone.is_empty()

	func undo() -> String:
		if done.is_empty():
			return ""
		var c: Command = done.pop_back()
		c.revert(model)
		undone.append(c)
		changed.emit()
		return c.label

	func redo() -> String:
		if undone.is_empty():
			return ""
		var c: Command = undone.pop_back()
		c.apply(model)
		done.append(c)
		changed.emit()
		return c.label

	func clear() -> void:
		done.clear()
		undone.clear()
		clean_index = 0
		changed.emit()

	func mark_clean() -> void:
		clean_index = done.size()

	func is_dirty() -> bool:
		return clean_index != done.size()
