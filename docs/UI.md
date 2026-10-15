# UI — structure, widgets, focus rules and prompts

Owner: UI. Scope: `game/src/ui/**`, `game/assets/ui/**`, `game/assets/fonts/**`. Requirements: UI-01…UI-12,
CMB-12 (controller-first, mouse/keyboard complete). Visual spec: `docs/design/ART_DIRECTION.md` §8–9.
Living style guide: `godot --path game -- --ui-screen gallery`.

## 1. File map

| Path | What |
|---|---|
| `src/ui/ui_theme.gd` | `UiTheme`: palette, typography, spacing, the code-built `Theme`, style boxes, small factories |
| `src/ui/ui_nav.gd` | `UiNav`: global UI runtime (UI actions, stick navigation, focus guardian, binding capture, toasts, match hooks) |
| `src/ui/screen.gd` | `Screen`: base class of every screen (contract in §3) |
| `src/ui/setting_rows.gd` | `SettingRows`: builds and wires a row for any `Settings.SCHEMA` key |
| `src/ui/bindings_flow.gd` | `BindingsFlow`: rebind / reset with conflict reporting, persisted through Settings |
| `src/ui/bot_tiers.gd` | `BotTiers`: **the one place** mapping player-facing bot tiers to `BotBrain` profiles |
| `src/ui/match_flow.gd` | `MatchFlow`: launch / pause / online detection / quit-to-menu around `App.start_match` |
| `src/ui/menu_backdrop.gd` | `MenuBackdrop`: orbiting, spot-lit Gullet behind the title and menus (skipped headless) |
| `src/ui/spectator_overlay.gd` | Spectator HUD bar: director/free camera, hide HUD, pause |
| `src/ui/tutorial_hook.gd` | `TutorialHook`: hand-off from the tutorial menu to tutorial gameplay |
| `src/ui/ui_dev_flags.gd` | Development/QA flags (`--ui-screen`, …; §9) |
| `src/ui/widgets/*.gd` | Widget library (§4) |
| `src/ui/screens/*.gd` | Screens registered in `App.SCREENS` (§5) |
| `assets/ui/icons/*.svg` | Icon masters (DPITexture import → crisp at any scale); `assets/ui/source/make_icons.py` regenerates them |
| `assets/ui/logo_mark.svg`, `assets/ui/credits.json` | Cage+can badge; credits/notices data (`source/make_credits.py` embeds the OFL texts) |
| `assets/fonts/` | Barlow, Barlow Condensed (OFL, via Cage Rules), Bungee (OFL) — see `docs/THIRD_PARTY.md` |
| `src/test/ui/test_ui_navigation.gd` | End-to-end UI tests (§8) |

## 2. Design system (`UiTheme`)

**Design units (du).** Every size is in units of the 1920×1080 base canvas. The project's `canvas_items`
stretch maps du to pixels (1280×800 → 0.667 px/du with a 1920×1200 du canvas; 4K → 2 px/du), and Settings multiplies
that by `display.ui_scale` and 60% of `access.text_scale` (`content_scale_factor`). Text additionally gets
`UiTheme.font_scale()` so the text-size option scales text by exactly `text_scale` while layout grows less.
**Minimum text is 28 du = 18.7 px at 1280×800** (ART_DIRECTION Deck floor); a test enforces ≥ 18 px on every screen.

**Text styles are theme type variations, never per-node font overrides** — that is what lets `UiTheme.refresh()`
rescale all text live. Use them by name:

| Labels | Font / base size (du) | Use |
|---|---|---|
| `Display` | Bungee 132 | wordmark-like title cards ("TEST DUMMY WINS!") — sparingly |
| `H1` / `H2` | Barlow Condensed 900, 80 / 54 | screen titles, poster titles (UPPERCASE) |
| `H3` | Barlow Condensed 700, 38 | section titles, help titles |
| `Eyebrow` | Barlow Condensed 700, 28, gold | kicker above titles, section headers (UPPERCASE) |
| `Body` / `BodyStrong` / `BodyMuted` | Barlow 400/600, 30 | text, row labels |
| `Caption` / `CaptionStrong` | Barlow 400/600, 28 (muted) | secondary text (the floor) |
| `Value` / `ValueGold` | Barlow Condensed 700, 34 | values in rows/tables |
| `Danger` / `Success` / `Warning` | Barlow 600, 30 | status text (always with words/icons) |

| Buttons | Use |
|---|---|
| `Button` (default) | ordinary actions |
| `MenuItem` | main-menu categories (Barlow Condensed 900, 54) |
| `SubItem` | sub-menus, pause menu, lesson lists |
| `PrimaryButton` | the call to action (Start fight, Rematch, Confirm) — brass border, not gold |
| `DangerButton` | destructive confirmations (rust) |
| `TabButton` / `TabButtonActive`, `FlatButton` | tabs, small icon buttons |

Panels: `PanelSolid`, `PanelPoster` (gold top rule — "fight poster"), `PanelHelp` (gold left rule), `PanelDialog(Danger)`,
`PanelToast`, `PanelBanner`, `PanelChip`, `PanelCard`, plus `ClipboardPanel` ("settings are a clipboard").
Palette constants (`UiTheme.GOLD`, `TEXT`, `MUTED`, `DANGER`, `SUCCESS`, `RIM`, …) follow ART_DIRECTION §3/§8.
`UiTheme.panel(variation, margin)` gives a themed panel with custom margins (it reads the style from the theme, so it
is correct before the node enters the tree).

**Focus is unmistakable and never colour-only:** gold 4 du ring + 2–5% scale-up + a gold chevron at the left edge
(rows, buttons, cards, binding slots). Hover with the mouse moves focus to the hovered control, so pointer and pad never
disagree. Motion: 120–240 ms eases; screens fade/slide in; results "stamp" in; `access.reduce_motion` removes slides,
stamps, the wordmark animation, toast fades and slows the menu backdrop.

## 3. Screen contract (`Screen`)

```gdscript
extends Screen
func on_enter(p: Dictionary) -> void:      # build the UI (theme is already applied)
    MenuBackdrop.ensure()                  # menus: 3D backdrop (no-op in headless/tests)
    add_backdrop_gradient()                # or add_dimmer() for overlays
    var f := build_frame("Eyebrow", "Title", std_prompts())   # margins + header/body/footer + prompt bar
    var list := FocusScroll.new()
    (f["body"] as VBoxContainer).add_child(list)
    var b := UiButton.new("Do the thing", "", "fight")
    b.pressed.connect(_do)
    list.content.add_child(b)
    play_intro()
func default_focus() -> Control: return <first control>
func on_back() -> bool: return false       # true = handled (close a sub-panel, cancel a dialog)
```

* Register the script in `App.SCREENS` (name → path). Open with `App.push(name, params)` (keeps the screen below and its
  focus) or `App.goto(name)` (replaces the stack). `ui_cancel` (B / Esc) calls `App.back()` → `on_back()` → pop.
  **`App.back()` never pops the last screen** — a screen that can be the only one (pause, results) must handle back itself.
* `is_overlay = true` (dialogs, pause, results, text entry): the screen below stays visible but dimmed. Otherwise covered
  screens are hidden. In both cases every covered screen gets `focus_behavior_recursive`/`mouse_behavior_recursive`
  disabled, so focus can never wander into a screen underneath.
* Focus memory: `App.push` calls `remember_focus()` on the covered screen; `on_resume()` restores it (deferred, and only
  if the screen is still on top). `UiNav` re-focuses the top screen (`ensure_focus()`) if focus is ever lost.

## 4. Widget library (`src/ui/widgets/`)

| Widget | Purpose / API |
|---|---|
| `UiButton(text, variation, icon)` | Menu button: focus ring + scale + chevron, hover focuses, `ui_move`/`ui_accept` sounds; `route` (free id), `help_title/help_text` |
| `UiRow(label)` | Base row: ONE focus stop; routes A/←/→/X to `_on_accept/_on_step/_on_extra`; `key`, `set_help()`, `set_badge()`, `on_extra` |
| `OptionRow` | Enum ◀ value ▶ with position pips; ←/→ cycle (wraps), A/click advance, arrows clickable. LB/RB are left free for tabs |
| `SliderRow` | Slider with ←/→ steps (accelerates when held), draggable bar; `value_changed` live, `committed` after 0.45 s (persist) |
| `ToggleRow` | ON/OFF pill (words + knob position, not colour only) |
| `TextFieldRow` | Opens `text_entry` (keyboard text box + on-screen keyboard + Confirm/Cancel); `secret`, `numeric`, ranges |
| `PickRow` | Row that opens a picker (character select) and shows icon/name/subtitle |
| `KeybindRow` / `BindSlot` | Action label + keyboard&mouse and controller columns; A/click captures (5 s timeout, Esc cancels), X restores defaults, conflict notes |
| `TabStrip` | `[LB] tabs [RB]`; tabs are clickable but not focus stops; owner calls `step()` on `ui_tab_prev/next` |
| `FocusScroll` | Vertical list with `follow_focus`, padding for focus scale, `focusables()`, `wrap_focus()` |
| `HelpPanel(scope)` | Shows `help_title/help_text/help_extra/badge_text` of the focused control inside `scope` |
| `ScrollText` | Focusable long text (credits/licences): ↑/↓, right stick, wheel, Home/End |
| `PromptGlyph` | One input glyph drawn procedurally (key caps, mouse, Xbox/PlayStation face buttons, LB/RB, LT/RT, sticks with direction, D-pad) |
| `ButtonPrompt(actions, text)` / `PromptBar` | "[glyph] Select" prompts; refresh on device/binding/setting changes; clickable when given a callback |
| `ToastLayer` via `UiNav.toast(text, kind)` | info / success / warning / error toasts, icon shape per kind, top-right, never focusable |
| `dialog` screen via `App.dialog(...)` | Modal; focus trapped; B picks the `cancel` button; `countdown` + `timeout_choice` = countdown-confirm |
| `ElementIcon` via `UiIcons.element_badge(id)` | Element icon (ELEMENTS.md shape, colour, outline + halo) **plus** the element name |
| `UiIcons.rect(name, size, color)` | Any SVG icon (`assets/ui/icons/*.svg`, tinted) |
| `StatBar`, `TeamChip`, `CreatureCard`, `Wordmark`, `ClipboardPanel`, `ArrowButton`, `ToggleSwitch`, `OptionPips` | Supporting pieces |

## 5. Screens

| Name (`App.SCREENS`) | Notes |
|---|---|
| `title` | Wordmark stamp-in, glint, falling JUICE can; "press any button"; boot hook for dev flags |
| `main_menu` | Poster layout; categories Fight (Quick Fight / Versus / Practice / Spectate), Campaign (Off the Street / Fight Camp / Bookie's Table), Online, Tutorial, Create (Rules Editor / Arena Editor), AI Lab, Mods, Profile, Settings, Credits, Quit. **Entries whose screen does not exist are hidden** (dev only; listed once in the log). Campaign entries open `campaign_menu` with `{variant: "off_the_street"|"fight_camp"}` and `bookie` |
| `settings` | Tabs generated from `Settings.SCHEMA` categories; Controls tab adds full rebinding for `Controls.GAME_ACTIONS`; per-tab reset (confirm); display rollback; restart badges (`"restart": true` in the schema); diagnostics report (copy / open logs). Params: `{tab, in_game}` |
| `profile` | Switch / create / rename / delete (confirm, never the last); stats, records, Dosage, per-fighter |
| `credits` | From `credits.json`; Notices tab: font OFL texts + Godot licence and component licences read from the engine |
| `dialog`, `text_entry` | Generic modal / on-screen keyboard (§4) |
| `pause` | Offline: freezes sim + physics. Online: does not pause and says so. Resume, Restart fight, Settings, Controls, Quit (confirm); quick controls reference; `{notice}` banner |
| `controls` | Read-only reference of every action (both device columns), shortcut to rebinding |
| `results` | Pushed by `App.start_match`; winner stamp, round score, stats per fighter; Rematch (`MatchFlow.launch(config)`), Change fighters (back to the setup in `config.ui`), Main menu |
| `versus_setup` | `{mode: versus|practice|spectate, setup, fighters}`; rules preset (`Content.ids("rules")`), arena (`Content.ids("arenas")`), up to 8 fighters: pick, team, bot tier, dummy (practice), remove; validation; Y starts |
| `spectate` | `versus_setup` with every fighter a bot; launches with the director camera + spectator bar |
| `character_select` | Cards for `Content.playable_creatures()` + Random; poster: name, epithet, element icon + name + status, weight class, stat bars, playstyle (`blurb`), kit. `{mode: quick|pick, on_pick}` |
| `tutorial_menu` | Lessons from Content kind `tutorial` or the built-in ten; launching goes through `TutorialHook` |
| `ui_gallery` | Development style guide |

## 6. Prompt glyphs (button prompts)

* A prompt shows **the current binding on the current device**: `PromptGlyph.event_for(action)` mirrors
  `Controls.prompt_for()` (first binding of the device class chosen by the *Button prompts* setting; `auto` = last
  device used), and the label text comes from `Controls.prompt_for()` / `Controls.event_label()`.
* Families: keyboard & mouse (key caps; arrows drawn as triangles; mouse with the pressed button highlighted), Xbox
  (lettered face buttons), PlayStation (✕ ○ □ △ shapes; L1/R1/L2/R2/L3/R3). Shapes and letters differ per button, so prompts
  never rely on colour. All glyphs are drawn, so they are crisp at 4K and need no platform art.
* Prompts refresh instantly on `Controls.device_changed`, `Controls.bindings_changed` and the setting. `UiNav` mirrors the
  device switch for stick input it swallows in menus.
* UI-only actions (added by `UiNav`, not rebindable gameplay actions):

| Action | Controller | Keyboard | Meaning |
|---|---|---|---|
| `ui_accept` / `ui_cancel` | A / B | Enter, Space / Esc | select / back |
| `ui_tab_prev` / `ui_tab_next` | LB / RB | Q, PgUp / E, PgDn | switch tabs (also move the caret in text entry) |
| `ui_alt` | Y | R | screen action: Reset tab, Start fight, Random, Change bindings, Camera |
| `ui_extra` | X | Delete, Backspace | row action: restore default, remove binding defaults, hide HUD |
| `pause` (gameplay action) | Start | Esc | opens the pause menu during a fight |

## 7. Focus, input and match rules

* **Stick:** `UiNav` turns the left stick into discrete `ui_*` steps with hysteresis (press 0.6 / release 0.35) and
  hold-repeat (0.38 s, then 0.11 s, faster after 8 steps). Godot alone fires a navigation step for every motion event past
  the dead zone (one flick = several items). Held D-pad directions repeat the same way.
* **Focus guardian:** if the top screen has focusable controls but nothing inside it is focused, focus returns to its
  remembered/default control (freed rows after a rebuild, a click on empty space, a closed dialog).
* **Dialogs/tabs/errors:** dialogs trap focus (left/right wrap, up/down blocked) and B = the cancel button; tab
  switches restore the last row used on that tab; validation errors keep focus where it was and explain the problem.
* **Rows:** left/right adjust values, so horizontal movement between columns exists only where no row consumes it
  (binding slots, button rows). Lists are vertical; this is deliberate.
* **Hot-plug:** connecting/disconnecting a controller shows a toast. During an **offline** fight with no menu open, a
  disconnect opens the pause menu with a notice; so does losing window focus when *Pause when unfocused* is on.
* **Pause:** offline = `MatchSim.paused` + `SceneTree.paused` (physics stops); UI runs in `PROCESS_MODE_ALWAYS`. A match
  is online when its config has `"online": true`, the scene is not a local `MatchScene`, or `Net.is_session_active()`
  returns true (net owner: provide it). Online pause menus never pause.

## 8. For other owners

* **New screen:** extend `Screen`, register in `App.SCREENS`, use `build_frame` + widgets above. Give every focus stop
  `help_title/help_text` when a `HelpPanel` is present. Put any list that can grow in a `FocusScroll` (or a
  `ScrollContainer`) — the layout test fails if a footer is pushed off screen.
* **Main-menu entry:** add it to `ENTRIES` in `screens/main_menu.gd` (it appears automatically once `App.has_screen()`
  is true). The lead verifies every entry exists before release.
* **Starting matches from UI:** `MatchFlow.launch(cfg)` (records `last_config` for Rematch/Restart, applies spectating).
  Put UI metadata in `cfg.ui = {mode, setup}` so Results can offer "Change fighters".
* **Bot tiers:** `BotTiers.ids()/names()/brain_tier(id)`; Hall-of-Famer asks for a `hall_of_famer` BotBrain profile and
  falls back to `champion` until the AI owner adds it.
* **Tutorial:** set `TutorialHook.launcher = func(lesson_id: String, fighter_id: String) -> void: ...` at startup.
  Entry point: `App.push("tutorial_menu")` (main menu → Tutorial, Settings › Gameplay → Open the tutorial).
* **Creature presentation fields** (all optional): `name`, `title` (epithet), `element`, `stats`, `blurb` (playstyle),
  `abilities.ability1/2.name`, `juice.name`, `tags` (`dev` shows a TEST chip).
* **Settings:** add the option to `Settings.SCHEMA`; the tab and row appear automatically. Add `"restart": true` or
  `"rollback": true` when needed; add a help string (or an entry in `SettingRows.FALLBACK_HELP`).
* **Toasts / dialogs:** `UiNav.toast(text, "info"|"success"|"warning"|"error")`, `App.dialog(title, body, buttons, cb)`.

## 9. Testing, development flags, evidence

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game -- --test ui --user-root <tmp>   # 8 UI tests (≈12 s)
& $g --path game -- --ui-screen gallery                       # widget gallery
```
Tests (`src/test/ui/test_ui_navigation.gd`, shared `TestCase` runner) inject joypad/keyboard/mouse events and assert focus
after every step: main menu → settings (tabs, change + persist, default restore, keyboard and controller rebinding with
conflicts, capture cancel, per-action reset, tab reset dialog, display keep/revert) → back → quit dialog; stick flick =
one step and hold repeats; prompt glyph family follows the device; mouse hover focuses; on-screen keyboard; versus →
character select → invalid line-up refused → real match → Start/Esc pause → B resume → controller disconnect pause → quit;
online pause does not pause; every screen opens focused and B returns; text/UI scale live; **layout audit at 1280×800 and
1920×1080** (footer on screen, all text ≥ 18 px).

Dev flags (handled by the title screen): `--ui-screen <name>` (any screen, plus `practice`, `countdown`, `pause`,
`ingame_settings`, `match`, `results` = a real 7 s bot round, `gallery`), `--ui-tab <id>`, `--ui-open <category>`,
`--ui-fighters <n>`, `--ui-device gamepad|keyboard`, `--ui-prompts xbox|playstation`, `--ui-toasts`,
`--ui-seed-window <WxH|borderless>` (writes windowed display settings into the active `--user-root`, then quits).
Capture: `godot --path game -- --user-root <dir> --ui-screen settings --capture out.png --capture-at 3`.

Evidence: `docs/evidence/ui/` — 24 screens at 1920×1080 and 1280×800 (real GUI renders; results from a real bot round,
pause over a real paused match) and a native 4K crop of controller prompts.

## 10. Known gaps (UI)

* The fight HUD (`fight_hud.gd`, combat owner) still uses 14–20 du text: below the 18 px Deck floor at 1280×800.
* Audio calls (`Audio.sfx("ui_move")` etc.) are no-ops until the audio owner implements them.
* Hidden main-menu entries: Campaign, Online, Create, AI Lab, Mods (screens owned by other teams do not exist yet).
* Tutorial lessons are listed but not playable until `TutorialHook.launcher` is wired.
* Results do not record statistics (`Profiles.record_match`) — the match-flow owner should record exactly once per match.
* Local multi-human versus is not offered: `Controls` reads all devices for one player; the setup has one "You" slot.
* Real Steam Deck/device testing, real controller hot-plug and audio-device switching are unverified (headless tests
  inject events; resolution checks are layout checks).
