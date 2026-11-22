# Changelog

## 1.0.5

- New source **Loot rolls**, on by default: an alert when an item comes up for a roll ("Roll for [Item]"), and one for who won it or when everyone passed. Other loot lines (looting, money, single rolls) stay in your chat only.
- **Loot summary** after a dungeon or raid, on by default: when you leave, ChatBanner shows who received green or better items, on screen and in chat. In the options you can choose blue or purple and better instead. Dying and running back does not end the dungeon. `/chatbanner loot` shows the last summary again; switch it off under Behaviour.

## 1.0.4

- New quick setup on the first login: where the alerts go and which messages get one. `/chatbanner setup` or the **Quick setup** button in the options opens it again.
- **Move and resize** in one go: drag the box to move the alerts, drag its corner to make them bigger or smaller. Everything scales together, so the proportions stay the same.
- Moving and resizing ends when you close the options or the quick setup, or reset the settings, so the blue box no longer stays on screen.
- Quest progress after killing mobs or looting quest items ("Kobold Vermin slain: 3/10") is now its own source, **off by default**. Other system messages still alert.

## 1.0.3

- The **Follow the font size** option now sits right under the **Row height** slider it controls.

## 1.0.2

- After an update, ChatBanner tells you in chat what changed. `/chatbanner news` shows it again.
- New players get a short welcome line with the commands.
- The row height now follows the font size (option, on by default), so larger text always fits.
- The channel label and its box grow with the font size, so the label always fits.
- With a fixed row height, rows still grow just enough to fit the text.

## 1.0.1

- Scrolling the options panel no longer changes a slider when the mouse passes over it.

## 1.0.0

First public release.

- On-screen alerts for whispers, party, raid, guild, officer, say, yell, emotes, channels, NPCs, bosses, battlegrounds and system messages.
- Left-click to reply, right-click to dismiss.
- Options panel (`/chatbanner`): position and size, sources, style and behaviour.
- Chat filters of Blizzard and other add-ons are respected; empty and multi-line messages are handled.
