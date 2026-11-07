# Collapse: Card Arena — Playtest Guide

A single-player tactical card arena made with Godot 4.6.3. Choose one of 8 characters and face 3 AI opponents. This is a development playtest; balance and some complex effects are still being refined.

## Language

Open Settings (设置), then select English under Language / 语言. Your choice is saved. You can change languages during a match without restarting it.

The language update is currently in the local project. Previously published dev.7 packages do not include it yet.

## How to play

- Choose a character and start a game. At turn start, keep your current class or switch to the character's secondary class. Switching reduces that turn's draw by 1 card.
- Stamina and Mana recover at turn start and drop to 0 outside your turn. There are no action points. Cards and character skills follow their displayed costs and use limits.
- Use your free move, play cards, activate skills or buy from the shared market. Ranges are square, including diagonal tiles; movement follows cardinal paths and cannot pass through characters.
- Click a card or skill to preview its range and legal targets. Hover over a card to read its complete effect. Suit and rank appear on each card.
- Mystery tiles draw a public event. Choose any required targets, responses or discards before continuing.
- At turn end, your normal hand limit is current Health minus 2, minimum 1. Select excess cards to discard. Purchased cards marked Reserved stay across turns until played.
- The board collapses only after eliminations: 15×15 → 11×11 → 7×7. Single-target damage gains +1 from round 5 and +2 from round 7 onward. Area damage does not gain this bonus.
- The last survivor wins; there is no round limit. A simultaneous wipe uses the game's tiebreak sequence.

## Controls and accessibility

Click cards and skills, then choose highlighted targets. Click an opponent to inspect their last 5 publicly played cards. Arrow keys move the board cursor; Enter confirms. Space ends your turn when no choice is pending. Escape opens or closes Settings. Settings includes text scaling, volume and reduced motion.

## Reporting a bug

Open Match details (scroll icon in the top bar) and copy the debug information. Include the version, seed, character lineup, operating system, what happened, what you expected and the steps to reproduce it. Attach a screenshot when a translation is unclear or text is cut off. Do not include private files or account information.

Windows builds still require testing on a real Windows machine. macOS builds may show an unsigned-developer notice; use only downloads from the project's official repository.
