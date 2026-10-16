# Verification run 20261016-115413

| Step | Status | Detail |
|---|---|---|
| packaged script check | pass | checked 378 scripts, 0 failures |
| packaged test suite | pass | tests: 677 run, 0 failed, 672 passed, 5 skipped in 1762.6 s |
| server load, 8 fighters (< 35 % of one core) | pass | main thread busy 30.0% (MEASURE ffa8 (LOOPBACK, 8 fighters, 20 s): per client down 34.2 KB/s (wire 35.4), up 4.9 KB/s (wire 7.1), 46/80 pkt/s; snapshot 1018 B; server sim 1.75 ms/tick,) |
| boot to first menu (< 10 s) | pass | 3948 ms to 'title', peak working set 617 MB |
| memory: 8-fighter match, 25 s (< 4 GB) | pass | peak working set 585 MB |
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
| net: dedicated server start (server package) online duel, 2 packaged clients (LOOPBACK) online spectator frame (windowed packaged client) server TCP admin (token, 127.0.0.1) server TCP admin refuses a wrong token server graceful shutdown no errors logged (server, clients, spectator) | pass pass pass pass pass pass pass | 'Verification Server' on UDP 47538, playlist verify_duel, pid 16952 authoritative result reached both; attacker won: True; Alice hits 17; Bob lowest health 0.0; 30.0 snapshots/s, interpolation 39 ms, RTT 9.0 ms capture_online_spectator.png Verification Server | phase results | up 29s | players 1/4 (+0 reserved) | spectators 0 ERR auth exit code 0 5 logs scanned |
| bench busy8 | pass | avg 255.3 fps, p95 5.683 ms, p99 6.703 ms, >16.7 ms 0.0% |
| bench duel | pass | avg 541.4 fps, p95 2.747 ms, p99 3.542 ms, >16.7 ms 0.0% |
| bench server sim (8 fighters) | pass | 1.96 ms/tick wall, 2.42 ms/tick CPU: 29% of one core at 120 Hz (target < 35%) |
