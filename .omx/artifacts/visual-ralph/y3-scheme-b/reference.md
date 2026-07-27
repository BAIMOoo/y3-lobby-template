# Scheme B visual reference

- Approved direction: Scheme B, selected by the user before implementation.
- Live preview: `http://127.0.0.1:4173/`
- Design viewport: `1920x1080`
- Browser captures: `web-lobby-full.jpg` and `web-battle-full.jpg`
- Runtime captures: `y3-lobby.png` and `y3-battle.png`

## Product parity

- Lobby preserves mode, player, BOB, login, AID, team, member count, matching, launch, team management, dungeon, chat, and operation feedback.
- Lobby has no invite-player action and no visible shortcut guide.
- Lobby and battle reuse the same chat builder, dimensions, message limit, input, channel actions, and feedback row.
- Battle keeps only test status, dungeon token, copy, chat, feedback, return, and exit controls.
- Battle hides the default `GameHUD`; editor performance counters are excluded from the product UI verdict.

## Visual direction

- Runtime uses the preview's warm-black surfaces, restrained gold accent, muted cream text, teal success state, and red destructive action.
- Lobby follows the preview's edge layout: status ribbon at top, team panel at left, expedition summary in the center, chat at lower left, and actions at lower right.
- A non-interactive dark atmosphere layer preserves the real game world while bringing its contrast closer to the web presentation.

## Reproduction

1. Open `EntryMap` in the Y3 editor and cold-launch the game at `1920x1080`.
2. Wait for transient debug text to clear, then capture the lobby.
3. Enter a private dungeon. For presentation-only verification, temporarily make `MatchTestIsBattleContext()` return `true` and `y3.game.get_current_game_mode()` return `1003`, wait one refresh cycle, capture, and restore both functions.
4. The real private-dungeon transition remains separately dependent on the external helper's `map_data` payload.
