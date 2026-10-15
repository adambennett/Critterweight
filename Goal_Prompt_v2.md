# Launching the complete game implementation

The implementation specification is [Initial_Prompt_v2.md](Initial_Prompt_v2.md). Keep that file available to the implementing agent throughout the run. It is self-contained; the agent does not need this review conversation to understand the objective or exceptions.

## Recommended goal prompt

Use the following in Claude Code or Codex with access to the PokeMMA workspace and the Cage Rules reference folder. Select your intended model in that client. This prompt starts implementation; it is not a request for another planning-only pass.

```text
/goal Read C:\Users\eX_Di\git\PokemonMMA\PokeMMA\Initial_Prompt_v2.md in full and implement the complete game it specifies. Treat that file as the authoritative scope and completion contract. Deliver a polished, fully implemented, technically verified release candidate for my evaluation, including the packaged Windows game, source, required local tools/content, dedicated server, documentation, and verification evidence.

All required features in the brief belong in this delivery, including both campaigns, both co-op formats, physical creature combat, PvP/NPCs, custom rules and bonus modes, playlists/hosting, local mods, arena editing, cosmetic gore, spectator/autobattler play, and a real local AI Lab with multiple training approaches. A prototype, vertical slice, roadmap, scaffold, or passing subset of tests is not completion.

Make the delegated design/engineering decisions, record reasons, and work autonomously through all milestones. Use bounded subagent tasks and independent reviews where available, with one integration owner. Preserve the original scope and maintain a requirement-by-requirement evidence ledger. Do not remove features, weaken acceptance criteria, or replace required behavior with mocks to make the goal pass.

Apply the brief's explicit exceptions: Windows runtime verification is required; Linux/Steam Deck implementation and feasible build/portability checks are required, while unavailable non-Windows build/device checks may remain disclosed gaps. macOS/mobile ports are optional. Steam account/payment/service integration and commercial release preparation are deferred. My playtest approval is not a prerequisite for delivering this release candidate. Do not spend money or rent infrastructure.

Before claiming completion, audit every required item against the actual integrated packaged game, fix failures, and surface a concise requirement/evidence digest in the conversation with artifact paths and test results. A written report alone does not prove the game works. Only the brief's expressly permitted external gaps may remain. If usage or a genuine blocker interrupts work, preserve the incomplete state and exact next actions; do not report success. Begin concrete implementation now and continue until this completion contract is satisfied.
```

## Goal behavior and limits

Claude Code currently documents `/goal` as a continuation mechanism with a separate completion evaluator. That evaluator reads the conversation; it does not independently inspect files or run tests. This is why the prompt requires visible evidence. Goal mode does not change tool permissions and can stop on completion, an impossible verdict, or certain errors. Check the installed client's available commands/settings before relying on unattended operation. [Claude Code goal documentation](https://code.claude.com/docs/en/goal).

Codex also supports `/goal` with file-referenced criteria. Its goal controls and lifecycle are client-specific; use the controls documented for the client you actually run. [Codex goal guidance](https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex), [Codex command reference](https://learn.chatgpt.com/docs/developer-commands).

Do not re-arm a new smaller goal at each milestone or clear an unfinished goal to label it successful. Let the client's normal completion mechanism finish the goal after the full audit. If the client stops or clears it because of an error or usage/access limit, the repository records still describe unfinished work. Resume the existing session where possible; inspect the active goal before setting the same full objective again. Do not assume a subscription guarantees uninterrupted execution.

This file does not change permissions, billing, model selection, or session settings. No extra paid usage or external service setup is authorized by the launch prompt.

## If the chosen client does not support /goal

Paste the same objective without the `/goal` prefix and ask the agent to use any persistent-task mechanism that the client actually supports. A normal prompt alone does not guarantee automatic continuation after the client stops. Keep the same specification and repository progress records; do not install an improvised unattended runner or claim a continuation mechanism exists without verifying it.

For a manual continuation after an interruption, use:

```text
Resume implementing C:\Users\eX_Di\git\PokemonMMA\PokeMMA\Initial_Prompt_v2.md with its full original scope and explicit verification exceptions. Inspect the current repository, requirements/evidence ledger, decisions, and progress records. Verify the latest state and continue the next unmet requirement through integration and testing. Preserve the same release-candidate completion contract; the prior interruption did not complete or reduce it. Check whether the original persistent goal is still active before setting it again.
```

## What the first handoff should mean

The agent may finish when the complete release candidate meets the brief's required implementation and Windows verification gates, with the expressly permitted external gaps disclosed. It should not wait for your subjective approval, Steam enrollment, optional ports, or unavailable devices. It also must not use those exceptions to excuse missing local gameplay or tools.

You then evaluate the game and decide what to iterate on. Extensive cross-platform playtesting, any commercial/legal review, and Steam release preparation belong to that later phase.

Documentation links checked October 14, 2026. Installed client behavior may differ; the game specification and its completion criteria remain the authority for the implementation task.
