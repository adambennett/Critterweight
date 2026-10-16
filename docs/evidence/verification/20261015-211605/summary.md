# Verification run 20261015-211605

| Step | Status | Detail |
|---|---|---|
| packaged script check | pass | checked 378 scripts, 0 failures |
| packaged test suite | fail | tests: 677 run, 21 failed, 656 passed in 6696.7 s (exit 21) |
| boot to first menu (< 10 s) | pass | 5981 ms to 'title', peak working set 614 MB |
| memory: 8-fighter match, 25 s (< 4 GB) | pass | peak working set 586 MB |
| capture title | pass | capture_title.png |
| capture main_menu | pass | capture_main_menu.png |
| capture settings | pass | capture_settings.png |
| capture mods | pass | capture_mods.png |
| capture rules_editor | pass | capture_rules_editor.png |
| capture tutorial | pass | capture_tutorial.png |
| capture duel | pass | capture_duel.png |
| capture ffa8 | pass | capture_ffa8.png |
| capture spectate | pass | capture_spectate.png |
| capture spotlight_hog | pass | capture_spotlight_hog.png |
| capture chumball | pass | capture_chumball.png |
| capture absolute_unit | pass | capture_absolute_unit.png |
| capture chum_rush | pass | capture_chum_rush.png |
| capture tag_team | pass | capture_tag_team.png |
| capture arena_drydock | pass | capture_arena_drydock.png |
| capture arena_crusher | pass | capture_arena_crusher.png |
| capture arena_rooftop | pass | capture_arena_rooftop.png |
| capture character_select | pass | capture_character_select.png |
| capture versus_setup | pass | capture_versus_setup.png |
| capture arena_editor | pass | capture_arena_editor.png |
| capture lab | pass | capture_lab.png |
| capture online | pass | capture_online.png |
| capture campaign_menu | pass | capture_campaign_menu.png |
| capture spectate_setup | pass | capture_spectate_setup.png |
| capture profile | pass | capture_profile.png |
| capture hub | pass | capture_hub.png |
| capture bookie | pass | capture_bookie.png |
| capture camp_ledger | pass | capture_camp_ledger.png |
| net: dedicated server start (server package) online duel, 2 packaged clients (LOOPBACK) online spectator frame (windowed packaged client) server TCP admin (token, 127.0.0.1) server TCP admin refuses a wrong token server graceful shutdown no errors logged (server, clients, spectator) | pass fail pass pass pass pass pass | 'Verification Server' on UDP 47692, playlist verify_duel, pid 37056 connected True/True, results 0/0; see alice.log, bob.log, server.log capture_online_spectator.png Verification Server | phase results | up 174s | players 0/4 (+2 reserved) | spectators 0 ERR auth exit code 0 5 logs scanned |
| bench busy8 | pass | avg 186.7 fps, p95 6.502 ms, p99 63.013 ms, >16.7 ms 1.7% |
| bench duel | pass | avg 447.0 fps, p95 2.768 ms, p99 4.855 ms, >16.7 ms 0.7% |
| bench server sim (8 fighters) | pass | 1.93 ms/tick wall, ~96% of one core at 120 Hz |
