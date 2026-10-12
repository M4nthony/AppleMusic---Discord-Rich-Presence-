# AppleMusicRPC
Discord server: https://discord.gg/gNWzdTWS7
**Show what you're playing in Apple Music on your Discord profile, on Windows.**

AppleMusicRPC displays your current Apple Music song on Discord as **"Listening to …"**, with the song title, artist, album cover, a time bar, and a **Listen on Apple Music** button.

- 🪶 **Lightweight**: no app to install, no installer program, no background window
- 🔌 **No mods needed**: works with the normal Discord app. No BetterDiscord or Vencord required
- 🚀 **Set it and forget it**: runs hidden and starts with Windows automatically
- 🎵 **Song title in the member list**: friends see "Listening to *song name*", not just "Apple Music"

## Download

Get the latest version from the releases page:

**[Download the latest release](https://github.com/M4nthony/AppleMusic---Rich-Presence/releases/latest)**

Download **`AppleMusicRPC.zip`**.

## Before you install: create a Discord Application ID

This takes about a minute and only needs to be done once.

1. Go to **https://discord.com/developers/applications** and log in.
2. Click **New Application**, name it **`Apple Music`**, and click **Create**.
   (This name is what shows after "Listening to" on your profile.)
3. On the **General Information** page, click **Copy** under **Application ID**.

You don't need to fill in anything else on that page.

## Install

1. Download `AppleMusicRPC.zip`.
2. Extract the ZIP.
3. Double-click **`install.bat`**.
   If Windows shows *"Windows protected your PC"*, click **More info → Run anyway**.
4. Paste your **Application ID** (right-click in the window to paste) and press **Enter**.
5. Play a song in Apple Music. Your Discord status updates within a few seconds.

**Updating:** extract the new version and run `install.bat` again. It remembers your Application ID, so just press **Enter**.

## Uninstall

Double-click **`uninstall.bat`**.

It stops AppleMusicRPC, removes it from Windows startup, deletes its files, and clears your Discord status.

## Requirements

- Windows 10 or 11
- **Apple Music** app (from the Microsoft Store) or iTunes
- **Discord desktop app** (the browser version can't receive statuses from other apps)
- In Discord: **User Settings → Activity Privacy → "Share your detected activities with others"** turned **ON**

## Settings

Open `%APPDATA%\AppleMusicRPC\config.json` (press **Win + R**, paste the path, press **Enter**):

| Setting | Default | What it does |
|---|---|---|
| `showPaused` | `false` | `true` keeps showing the song while it's paused |
| `showButton` | `true` | `false` hides the "Listen on Apple Music" button |

Run `install.bat` again (press **Enter** to keep your ID) to apply changes.

## How it works

Windows already knows what Apple Music is playing, which is what you see in the volume popup. AppleMusicRPC asks Windows for that info every 2 seconds and sends it to the Discord app on your PC through Discord's official Rich Presence connection, the same one games use.

Album covers and the "Listen on Apple Music" link come from Apple's public music catalog, looked up by song name.

## License

[MIT](LICENSE)

---

*Not affiliated with Apple or Discord. Apple Music is a trademark of Apple Inc. Discord is a trademark of Discord Inc.*
