# v0.9.12 playtest fixes

Scope: the 24 issues/requests reported from the user's v0.9.11 playtest, including seven screenshots. Work began from clean `main` at `cb8ce7f`. Tests use isolated user directories and do not modify the player's saves.

## What changed and how it is checked

1. **Lobby cannot exit:** `CampaignUI.leave` pops the campaign screen instead of calling Back recursively. `test_playtest_campaign` opens the real screen stack and dispatches Back. Requirements UI-01/02.
2. **Disappearing submenu:** the main menu closes submenus on deliberate navigation/back, rather than incidental focus elsewhere. The UI test moves focus away and confirms the submenu remains available. UI-01/02.
3. **Controller text scrolling:** UiNav routes the right stick to the focused text/list/scroll region; HelpPanel and campaign scroll panels are focusable. Editor/model controls explicitly retain their sticks. A UI test scrolls the real ScrollText widget. UI-02.
4. **Campaign result/resume:** the presented MatchScene retains its CampaignFlow; previously the last owning map was freed and the result callback lost its owner. A regression releases the external flow reference, emits the completed fight result, verifies Reward, loads the actual saved slot and verifies the resumed pending reward. Existing full campaign tests exercise real fights and campaign progression. SAV-01/03, VER-02.
5. **Autobattler presentation:** BookieFlow keeps one presented MatchScene throughout Watch/Skip. A runtime test starts the default table, observes advancing AI combat, switches to 8x skip, then returns to the same visible scene. AI-03/04.
6. **Free camera:** Follow/Locked/Free cycle and movement/rise are exercised in a real spectator scene. The Bookie test also checks exclusive free-camera input and View returning focus to its controls. AI-02/04.
7. **Player addressed as You:** `Profiles.player_name` normalizes the legacy default to Rookie and preserves custom names. Dialogue, fight cards and hub/test-match setup use it. Unit tests cover both names. UI-01.
8. **Compendium:** all installed non-development creatures have a real model preview; the runtime test loads each one and checks every documentation section. Ability/stat values and status data use loaded content where possible. UI-01, PRV-03.
9. **Main-menu scrollbar:** eight groups fit the existing poster composition. Tests confirm no ScrollContainer in the main navigation and every option fits the viewport. UI-01.
10. **New-rules overflow:** three-column option grid; all eight options are focused and bounds-checked in the rendered test. UI-01/02.
11. **RB unclear:** actual RB events are passed through LocalPlayerInput for all six playable fighters. Each holds AB2, starts the ability and consumes its cooldown. No universal RB activation bug was reproduced. Ability names in the HUD and practical Compendium descriptions clarify defensive/setup effects. CMB-03/04, UI-01.
12. **Needles services:** board and guide explicitly identify the catalog preview, actual campaign Shop location, each service and currency. Existing shop tests cover purchases/services. UI-01.
13. **Chum Cannon depth:** three difficulties; tests check fire intervals, flight time, tracking and the committed final dodge window. Hub activity tests remain applicable.
14. **Crate Toss depth/reset/walls:** called targets and streak bonuses, one score per crate, reset on finish/cancel, physics line-of-sight pickup check. Tests check scores, reused-crate rejection, real main-floor wall obstruction and reset positions.
15. **Room-turn controls:** HubCamera derives movement from the displayed yaw every frame. The test compares camera and input bases throughout a turn.
16. **Buzz:** sustained generated tones removed from eight loops; old fade tweens cancelled before player reuse. Audio manifest hashes and bank tests verify the rendered assets; a graphical test verifies rapid transitions leave only the newest player audible and Stop clears both. AUD-01/02.
17. **Audio inventory/research:** 638 files enumerated with hashes and bank references; [replacement guide](../../../audio/REPLACEMENT_GUIDE.md) lists primary-source candidates/licenses. No stock asset was downloaded or adopted. PRV-02/03.
18. **Clipped last button:** shared focus reveal reserves outline clearance and FocusScroll has bottom padding. Tests measure clearance in a twelve-row list, the Cannery lesson board and the actual Tutorial screen's Practice instead button. UI-02.
19. **Suspended-run focus:** an actual Up navigation event from Bookie enters the saved-run buttons; Start bridges left and right columns. UI-02.
20. **Arena Editor focus/layout:** a left-stick event cannot escape the map, panels can collapse, and both device layouts fit after repeated switches. Captures record expanded and map-focused layouts. ARN-01/02/03.
21. **NVIDIA upscaling:** cross-vendor FSR labels and help clarify NVIDIA support. DLSS is unavailable in the stock Godot 4.5.1 renderer; no nonfunctional setting was added. UI-01.
22. **Resolution:** a real OptionButton dropdown replaces cyclic application of every intermediate mode. The test browses without changing Settings; the existing display transaction tests cover Keep/Revert. UI-01.
23. **FPS:** a global CanvasLayer counter obeys the setting immediately. Tests toggle its visibility. UI-01.
24. **AI Lab music:** application focus includes owned native windows. The rendered test opens an actual AI Lab dropdown with background mute enabled and checks that Master remains unmuted. AUD-02, LAB-03.

Additional shutdown warnings exposed a strong reference cycle between PracticeMode and its dummy input source, and unowned HUD containers in three/four-fighter matches. The dummy now keeps a weak reference to its owner and all HUD rows belong to their scene. Regressions verify the mode is released when the scene closes and repeated small-team matches leave no orphan containers.

## Evidence and limits

- Rendered Windows regression run: **20 tests, 20 passed, 0 skipped**, 19.3 seconds, at 1280x720. [Runtime log](rendered-source.log).
- Controller navigation suite: **8 tests, 8 passed**, including Settings category entry/exit, rebinding, display rollback, pause and disconnect behavior. [Runtime log](controller-navigation.log).
- Existing Arena Editor tests: **5 passed**. Existing hub interaction tests: **6 passed**. The Windows worker-lifecycle test also passed with normal process-inspection permissions.
- Script check: **391 scripts, 0 failures**. A final check is also part of packaging.

- Full source suite: **711 run, 710 passed, 0 failed, 1 skipped**, 3636.9 seconds. The skipped test requires graphical audio and passes in the rendered run above. [Machine-readable results](full-suite.json) and [runtime log](full-suite.log). This includes complete campaign runs, AI Lab training/recovery, multiplayer campaign resume, three/four-player route voting and localhost server/client sessions.
- Exported Windows preflight: **391 scripts checked, 0 failures; 20 rendered tests passed, 0 failed, 0 skipped**, 16.2 seconds at 1280x720. [Results](packaged-preflight.json) and [runtime log](packaged-preflight.log). No engine/script errors or resource-shutdown warnings. This was an untagged export of the same game sources; the release script repeats the checks on the clean tagged export before publication.
- Deterministic audio check: all **12 ambience loops** were rendered again and matched the checked-in WAV files; the complete inventory independently verifies all 638 file hashes.

Early verification runs were diagnostic, not release evidence: two assertions needed to follow the new editor/menu behavior, and sandbox process-inspection denial invalidated worker-exit checks. The final run uses normal local process and localhost-network access, without relaxing those checks.

The full suite has no GDScript exceptions. Its malformed-payload tests intentionally produce invalid-UTF-8 and rejected-object decoding diagnostics. At full-suite shutdown Godot also reports an ObjectDB warning and **four resources still in use**. That shutdown warning did not reproduce in the separately run 22 codec tests, eight co-op fight-state tests, or the 20 rendered playtest regressions. Its full-run-only cause has not been isolated; it remains a verification limitation, not a clean-shutdown claim. One Jolt job-pool capacity warning occurred during the passing `test_exercises_adapt_to_missing_slots` tutorial fixture. The exported playtest run has neither warning. The short localhost server soak passes; its measurements are in the full log and do not certify internet play or a quiet-machine performance baseline. Curated text logs normalize encoding, line endings and trailing whitespace without removing diagnostic messages.

## Captures

All images are real native Windows renders at 1280x720. The Cannery boards are opened by the test harness over a menu backdrop; their behavior in the hub is additionally covered by the hub interaction tests.

- [Main menu](captures/v0912-main-menu.png) and [new-rules picker](captures/v0912-new-rules.png).
- [Fighter Compendium](captures/v0912-compendium-fighter.png) and [element/reaction guide](captures/v0912-compendium-elements.png).
- [Live Bookie fight](captures/v0912-bookie.png) and [free spectator camera](captures/v0912-spectator-free.png).
- [Editor with panels](captures/v0912-editor-panels.png) and [map-focused editor](captures/v0912-editor-map.png).
- [Cannon difficulties](captures/v0912-cannery-drill.png), [Needles' catalog](captures/v0912-cannery-shop.png) and [Cannery lessons](captures/v0912-cannery-lessons.png).
- [Tutorial bottom focus outline](captures/v0912-tutorial-bottom.png) and [settings dropdown row](captures/v0912-settings.png).

## Remaining validation limits

Controller tests inject Godot input events and exercise runtime focus/input routing. They are not a claim of hands-on physical-controller testing. Screenshots use the native Windows renderer at 1280x720; earlier layout checks also ran at 3840x2160. Campaign regression results cover state ownership and saved pending decisions; the existing suite supplies complete simulated runs and loopback co-op tests. Audio playback/mute/fade tests do not establish subjective sound quality. Replacement music was researched, not auditioned. Linux exports are built but Linux gameplay is not verified by this Windows run.

Existing v0.9.11 saves remain compatible. A win whose result was lost by the old flow-owner bug cannot be inferred safely from a save still marked as `fight`; that encounter replays once, then future completed results are saved at the correct next decision.
