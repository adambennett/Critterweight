# PokeMMA

We're building a production-grade, 3D Game for Windows, macOS and Linux (Ubuntu 24+). This is professional-grade software that needs to be stable, fully-tested, and real-world deployable. No hacks, no shortcuts - solid as a rock. I expect to be able to sell this game on Steam eventually, so it needs to be legally above-board and high enough quality that I would feel justified charging players $10 or less to purchase it. This is not an asset flip or a money grab, get rich quick scheme - the primary goal is to produce a game that is fun to play. It will be listed on Steam if we can accomplish that goal well enough to justify sharing it with the world.

## Dev Workflow
- Ask questions only when absolutely necessary - work autonomously. Keep building until the project is production-ready.
- Start by coming up with a real working name for the project instead of my placeholder "PokeMMA".
- Testing is of the utmost importance - use lots of unit tests (any framework, simple is good), run automated testing
- Do things properly, this is production-grade and not a hack project
- Create AGENTS.md and relevant rules, skills, etc to support development, and contain concrete development guidelines
- Create git repository, commit and push to [GitHub repo](https://github.com/adambennett/PokeMMA). IMPORTANT: do a code review before committing, and make sure all changes comply with code style, production-grade quality standards, and have been properly tested/have unit tests that have passed where necessary

## Tech stack
- Either C++ or Rust or something similar: we want super high performance code for the game. This is the only concrete suggestion you must follow: the 4 points below are up to you to change and use something different if you prefer and have a good reason for doing so.
* [GLFW](https://github.com/glfw/glfw) and [nvrhi](https://github.com/NVIDIA-RTX/NVRHI), using Vulkan primarily on all platforms
* [glm](https://github.com/g-truc/glm) for math
* [miniaudio](https://github.com/mackron/miniaudio) for audio
* Lua or something similar for scripting, if needed. Lua was chosen as a recommendation because it's fast/performant and should allow for easy mod injection.

## Basic Architecture
- Made to be played with an Xbox controller first, but should also support Mouse+Keyboard.
- Codebase should be written assuming no humans will ever really read the code: AI agents will 100% be in charge of writing and updating the codebase, as well as fixing the bugs. So the code should be structured for agent readers.
- Needs to be playable on the Steam Deck
- Mods need to be supported from the community as a first class citizen within the codebase, game interface, and eventual Steam integration via Steam Workshop. The codebase should be written in a way where it expects to be modified by mods after release. We should also expect that modders will likely use their own LLM agents to produce these mods, so we should include documentation in the code and release files to explain how to properly mod and interact with the base game.

## Design
- Heavily inspired by my roommate's MMA cage fight sim game, "Cage Rules" which you can find in the workspace. Our goal is not to recreate this game, especially not the browser-based tech stack, but to emulate the fun of the gameplay and quality/style of the graphics.
- Instead of human fighters, this game will feature "pokemon" fighters. Not actually pokemon - this needs to be legally distinct so it's possible for me to monetize if I wish. But the fighters should have abilities, and some sort of "element" tree similar to pokemon. Try not to copy anything from Pokemon that we don't actually need, such as "balls", I know Palworld got in legal hot water over their usage of balls to capture and hold Pals, so we need to steer clear of that aspect at least for sure. The main goals from Pokemon we are trying to emulate are the types/elements (doesn't have to be water/fire/grass/etc exactly but something like it that serves the same role) and the art style to some extent. Think "Batomon Showdown" - inspired by, but not copying.
- My roommate's game has a LOT of controls, and feels highly complex to play. This game will take the opposite approach, with few overall buttons to actually remember to control the fighters, but still maintaining a high skill ceiling for experienced players via combos and other game mechanics that are not punishing for new players.
- There should be a heavy focus on Rougelike elements for the Campaign mode. Star Wars Galactic Racers recently came out, and I really like how they implemented the rougelike elements in their campaign. Slay the Spire & Slay the Spire 2 are both also excellent examples of the type of rougelike we are going for: branching paths, decisions that matter and drive the player's build, random chance playing a role through events and other shenanigans, etc. The one distinction between SW:GR and StS is that StS offers no "meta progression" and the rougelike elements are all happening within each run, with each new run starting on even footing. I really like that approach the best, but meta-progression can also be really fun for the player. To satisfy players who like either type of mode, we should build out two different types of campaign modes that can be played which work to support each approach.
- There should be parody elements of the actual UFC without breaking legal lines. Think "Spruce Spruffer" as an announcer and other small references like that strewn throughout the game.
- It needs to feel really "arcade-y" a fun to play and fight the creatures.
- There should be support for NPC opponents, as well as the possibility to do fights with more than just 1v1 combatants, although 1v1 should be the standard for most normal modes like Campaign. We do want to implement some additional "bonus" or "zany" modes that have more ridiculous rules in place for more fun replayability as well though - similar to how people make mini-game modes in Halo 3 such as Duck Hunt, Jenga, or SWAT: these are all quite different from standard Halo 3 gameplay, but are equally valid and fun ways to experience the game. Our fighting game should have some modes that take advantage of the same player desires.
- There should be a fairly extensive system similar to "game types" in Halo, where players can create matches with various customized rules and settings, and perhaps even "maps". The default "map" is always the cage fight though.
- There needs to be menu music, battle music, sound effects on the fight, and other various audio integrations to improve the overall feel of the game.
- I should be able to play the game very naively by moving my left joystick around to move around the arena, and mashing buttons to attack the enemy. There should be deeper gameplay available beyond that, but this startegy should "work" and feel fun.
- It needs to support PvP as well as Co-Op campaigns with your friends. It should be possible to "host" a server directly from in the game, or if the players wish they should be able to run their own dedicated server to host ongoing matches 24/7. Investigate "Project Reclaimer" a bit, and see how they have implemented multiplayer - we want a similar system. I really like their idea of "playlists" where players can setup a rotation of game modes to shuffle through randomly each round, allowing players to vote on the chosen game mode that will be used, and playlist authors to set "weights" to control roughly how often each mode appears.
- For the meta-progression mode campaign, there should be a full explorable overworld that functions as a way for the player to interact with the meta game between runs, and explore for secrets and upgrades as well. Think similar to Hades, but more expansive and "open world" in feeling, without ballooning to the full scope of an open world in something like Skyrim or whatever. Somewhere in between - small and practical like Hades, but with some extra juice that encourages players to explore a bit.
- For the initial delivery, you don't need to design a large roster of creature fighters. Somewhere between 4-10 unique fighters is plenty to start with, even with the rest of the project aiming at production-ready quality. If we need more than the initial roster, that can be handled by future design passes. I want you to focus on designing a roster that is intentional, and each fighter has a reason to exist in the game. It's easy to design 10s of "lazy" abilities and brag about a ton of characters being playable, but it's not interesting enough. The fighters need to feel unique, interesting, and creative. This in some ways is the most important part of the game design, alongside the types/elements system you design alongside the fighters. If this isn't designed well, nothing in the game will feel good.
- We should also implement my roommate's idea for the "Watch AI vs AI" mode, where you can watch NPC fighters duke it out. This should be a rougelike mode of it's own, if they player enables it, allowing them to be a passive spectator to the fights while choosing their fighter's upgrades and build through the normal rougelike systems. Essentiall an "autobattler" mode that can also function almost as a screensaver if they wanted.
- There should be some minor concepts of "drug use", whether it be some steroids analog or otherwise. This is a mature game, despite the cartoony art style. There can be cursing and vulgarity as well, if the design calls for it.

## 3D Graphics
- See the "Cage Rules" project for art-style examples: that project has a good art style that would work well for our project as well, but we need "pokemon" instead of those human fighters.
- Use free and royalty-free assets from the internet, unity/unreal asset stores as needed, but try to produce a lot of original art and assets yourself so that we aren't just making an asset flip.
- Mainly "cartoony" art style, to match "Cage Rules" for the most part.
- I like the idea from "Cage Rules" that as the fighters take damage you can actually see different parts of their body becoming red, bloody, injured, etc. We should implement a similar system. In fact, the game should have "gore" by default (and can be disbled or reduced via settings), having fighters limbs be possible break off and stuff. This could be integrated with the gameplay directly, or just be a fun thing that happens visually (especially at battle end, when one fighter has lost). Similar to Mortal Kombat maybe in function essentially, but way more cartoony and silly.
- Import gltf meshes with materials and textures
- PBR material workflow
- Soft shadow maps
- Good SSAO
- HDR pipeline with tonemapping

## 3D Physics
- Use any 3D physics library of your choosing, or even create your own if you feel that is the best approach to creating a fun game with consistent, predictable physics for players to interact with

## Menus
- Make sure to include a Settings menu in the main menu (at least, can be accessible elsewhere too) that contains ALL standard game settings from AAA releases: video, audio, system, network settings - the works. This needs to feel like a commerical-quality, real triple-A game.
- Our goal is to give players full configuration control of their game, at least when they are playing Singleplayer - in that case it's their game and I don't care how they want to play it so we need to give them a lot of options!
- Keep a consistent style throughout the game for menus, fonts, etc. Spend some time on this bit - nice, smooth, clean looking menus are really important to the project. Use tabs, coloring, text sizing, and other strategies to make the menus feel organized, complete, and functional.

## Difficulty
- The game should support multiple difficulties, going from very easy to extremely difficult
- It would be cool if the game included a way to allow players to use their computer to train AI bots of their own, and save and fight them later. Essentially an "AI Lab" built into the game that offers the ability to train even more difficulty NPC enemies if the wish, using different training approaches and styles.
- There needs to be a short tutorial mode included, similar to how "Cage Rules" implemented their tutorial mode.
- The campaign mode without meta progression should offer a similar scaling difficulty system to Slay the Spire's "ascension" mode where clearing the campaign at the highest available level unlocks the next difficulty level until maxed out. Don't call it "ascension" mode though, use a different name. In fact, try not to copy any naming from any of these other games/projects that have been referenced. Come up with all your own naming.