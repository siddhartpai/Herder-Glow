# Herdr-Glow

[![Downloads](https://img.shields.io/github/downloads/siddhartpai/Herdr-Glow/total?label=downloads&color=38db8c)](https://github.com/siddhartpai/Herdr-Glow/releases)
[![Latest release](https://img.shields.io/github/v/release/siddhartpai/Herdr-Glow?color=428fff)](https://github.com/siddhartpai/Herdr-Glow/releases/latest)
[![Latest release downloads](https://img.shields.io/github/downloads/siddhartpai/Herdr-Glow/latest/total?label=latest%20downloads)](https://github.com/siddhartpai/Herdr-Glow/releases/latest)
[![Stars](https://img.shields.io/github/stars/siddhartpai/Herdr-Glow?style=flat&color=ff4a59)](https://github.com/siddhartpai/Herdr-Glow/stargazers)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey)

Your coding agents, one glance away.

Herdr-Glow puts a small light on the right edge of your Mac screen. The light shows the state of your herdr agents. Hover over it to answer a waiting agent without a terminal switch.

**[Website and demo video →](https://siddhartpai.github.io/Herdr-Glow/)**

[![Herdr-Glow demo](docs/assets/poster.jpg)](https://siddhartpai.github.io/Herdr-Glow/)

## The light

| Color | Meaning |
|-------|---------|
| Blue  | Agents are working. Nothing needs you. |
| Red   | An agent waits for an answer. |
| Green | A job is done. Hover for the summary. |
| Grey  | herdr is not running. |

## Features

- The panel shows the question that a waiting agent asks, with one button for each option.
- Press 1–9 to answer, or type a free-text reply.
- A finished agent shows a short summary of its work.
- Click a card to open that agent's pane in herdr.
- The light shows on every Space and over full-screen apps.
- Six palettes: Default, Pastel, Neon, Sunset, Ocean and Mono.

## Install

1. Download `Herdr-Glow-0.1.1-macos.zip` from the [latest release](https://github.com/siddhartpai/Herdr-Glow/releases/latest).
2. Unzip it and move `Herdr-Glow.app` to `/Applications`.
3. Run this command in Terminal. The app is not notarized by Apple, so macOS blocks it until you remove the quarantine flag.
   ```sh
   xattr -cr /Applications/Herdr-Glow.app
   ```
4. Open the app. The light appears on the right edge of your main screen.

### Build from source

1. Clone the repository.
   ```sh
   git clone https://github.com/siddhartpai/Herdr-Glow.git
   cd Herdr-Glow
   ```
2. Build the app. The script puts `Herdr-Glow.app` in `~/Applications`.
   ```sh
   scripts/bundle.sh
   ```
3. Open the app.
   ```sh
   open ~/Applications/Herdr-Glow.app
   ```

## Requirements

- macOS 14 or later
- A Swift 6 toolchain (Xcode or the Command Line Tools)
- herdr running. The app connects to `$HERDR_SOCKET_PATH`, or to `~/.config/herdr/herdr.sock`.

## Development

```sh
swift test
```

The demo video source is in `video/demo`. It is a [HyperFrames](https://hyperframes.heygen.com) composition with mock agent data. The website is in `docs/`.

## Usage

Total release downloads, recorded once a day by the `Download stats` workflow:

![Downloads over time](https://raw.githubusercontent.com/siddhartpai/Herdr-Glow/stats/downloads.svg)

[![Star history](https://api.star-history.com/svg?repos=siddhartpai%2Fherdr-glow&type=Date&theme=dark)](https://star-history.com/#siddhartpai/Herdr-Glow&Date)

## License

MIT
