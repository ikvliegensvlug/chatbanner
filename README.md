# ChatBanner

Big, clickable on-screen alerts for chat messages, so you never miss a whisper, guild or party message again.

Chat scrolls by fast in combat, while questing or when you look away for a moment. ChatBanner shows each new message as a large alert at the top of your screen, coloured like its chat type, and fades it out after a few seconds.

## Features

- **Alerts for every kind of chat**: whispers (including Battle.net), party, raid and raid warnings, guild, officer, say, yell, emotes, channels such as General, Trade and LFG, NPCs, boss emotes, battleground messages, system messages, quest progress (optional) and loot rolls (the item up for a roll and who won it; other loot lines stay in your chat).
- **Quick setup**: on your first login a small window asks the two things that matter most: where the alerts go and which messages get one. Open it again with `/chatbanner setup`.
- **Choose your sources**: switch each kind on or off in the options. Quest progress ("Kobold Vermin slain: 3/10") is a separate choice and off by default.
- **Click to reply**: left-click an alert to answer in the same channel (or whisper back), right-click to dismiss it.
- **Fits any screen**: set the width, row height (or let it follow the font size), scale, number of alerts and how long they stay. Drag them anywhere and let them grow up or down.
- **Your style**: font, font size, background opacity, border style, channel label on or off, coloured or white text, optional sound.
- **Respects your chat filters**: messages that Blizzard or other add-ons hide from your chat (spam filters, for example) don't become alerts either.
- Light and self-contained: no libraries, no other add-ons needed.

## Commands

| Command | What it does |
| --- | --- |
| `/chatbanner` or `/cbanner` | Open the options |
| `/chatbanner setup` | Open the quick setup again |
| `/chatbanner test` | Show sample alerts |
| `/chatbanner unlock` | Move the alerts, or drag the corner to resize them |
| `/chatbanner lock` | Fix the position again |
| `/chatbanner reset` | Restore all default settings |
| `/chatbanner news` | Show what changed in recent versions (also shown once after each update) |

You can also find the options under **Options > AddOns > ChatBanner**.

## Tips

- Too many alerts in a busy city? Switch off **Channels** in the options.
- To test real alerts, whisper yourself: `/w YourName hello`.

## Compatibility

Made for World of Warcraft: Forever (interface 16001). Other clients are not tested yet.

## Development

The repository contains offline tests that load the add-on on a fake WoW API. They are not part of the add-on package.

```
npm install
npm test
```

## License

MIT, see [LICENSE](LICENSE).
