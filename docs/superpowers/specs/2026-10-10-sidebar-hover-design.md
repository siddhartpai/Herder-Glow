# SidebarHover — Design

Date: 2026-10-10
Status: Approved in chat, pending written-spec review

## Goal

An always-on traffic light on the right edge of the Mac screen. It shows the
state of all coding agents that run in herdr. When the user hovers over the
light, a panel opens. In the panel, the user answers or approves agents that
wait for input, without a switch to the terminal.

## Decisions (from brainstorming)

| # | Question | Decision |
|---|----------|----------|
| 1 | Content for a waiting agent | Last 20 screen lines, one button for each numbered option, and a free-text box |
| 2 | Edge indicator | One traffic light for all agents |
| 3 | Hover list layout | Blocked agents at the top, open. Other agents as one-line rows. A row click focuses the pane in herdr |
| 4 | Panel and window behavior | Panel closes 0.3 s after the mouse leaves. Light shows on all Spaces and over full-screen apps. Panel takes keyboard focus only on a click in the text box |
| — | Approach | Native Swift app. It talks to the herdr Unix socket directly |

## Light color rules

| Condition | Color |
|-----------|-------|
| herdr socket not reachable | Grey |
| One or more agents `blocked` | Red |
| Else, one or more agents `working` | Yellow |
| Else (all `done`, `idle` or `unknown`, or no agents) | Green |

## Components

1. **`HerdrClient`** — Connects to the Unix socket at `$HERDR_SOCKET_PATH`, or
   `~/.config/herdr/herdr.sock` if the variable is not set. Sends JSON
   requests and reads JSON responses. Runs a second connection for
   `events.subscribe`. Reconnects every 2 s if the socket closes.
2. **`AgentStore`** — Holds the agent list (pane id, workspace, title, cwd,
   status). Applies events. Computes the light color. Observable by SwiftUI.
3. **`EdgeLightWindow`** — Borderless `NSPanel`, about 12 × 60 px, at the
   vertical center of the right edge of the main screen. Level above
   full-screen apps. `collectionBehavior` includes `canJoinAllSpaces` and
   `fullScreenAuxiliary`. Does not become key. Mouse-enter opens the panel.
4. **`HoverPanel`** — Non-activating `NSPanel` with SwiftUI content, about
   380 px wide, to the left of the light. Sections:
   - Blocked agents: title, cwd, last 20 screen lines (monospace), option
     buttons, text box with a Send button.
   - Other agents: one row each with a color dot, title and status. A click
     calls `agent.focus`.
   The panel becomes key only when the user clicks in a text box. It closes
   0.3 s after the mouse leaves both the light and the panel.
5. **`PromptParser`** — Pure function. Input: screen text. Output: a list of
   options (`number`, `label`). Matches lines such as `❯ 1. Yes` and
   `  2. Yes, and don't ask again`. Returns an empty list when no options
   exist.

## herdr API used

| Purpose | Method |
|---------|--------|
| Initial agent list | `agent.list` |
| Live updates | `events.subscribe` (`pane.agent_status_changed`, `pane.agent_detected`, `pane.created`, `pane.closed`) |
| Screen text | `agent.read` with `source: recent`, `lines: 20` |
| Option answer | `agent.send_keys` with the option number |
| Free-text answer | `agent.prompt` |
| Focus pane | `agent.focus` |
| Re-check before send | `agent.get` |

The exact wire format (framing and envelope) comes from
`herdr api schema --json` and is confirmed in the first plan task.

## Data flow

1. On start: `agent.list`, then `events.subscribe`.
2. Each event updates `AgentStore`; the light color updates at once.
3. On hover: `agent.read` for each blocked agent. While the panel is open,
   read again on each state change of that agent.
4. Option click → re-check → `agent.send_keys`.
5. Text box Enter or Send → re-check → `agent.prompt`.

## Error handling

- **Socket missing or closed:** light is grey; reconnect every 2 s.
- **Prompt changed:** before a send, call `agent.get`. If the agent is not
  `blocked`, do not send. Show "Prompt changed" and reload the screen text.
- **Send fails:** show the herdr error text under that agent. Keep the panel
  open.
- **No options parsed:** show only the screen text and the text box.

## Safety rule

The app never sends keys or text to an agent whose current status is not
`blocked`.

## Testing

Automatic (`swift test`):
- `PromptParser` with real Claude Code prompt samples: numbered options,
  free-text question, no prompt.
- `AgentStore` color rules, including grey when disconnected.
- `HerdrClient` against a fake Unix-socket server that sends JSON lines.
- Safety rule: no send to a non-blocked agent.

Manual:
- Start a Claude agent in a new herdr pane and make it ask for a
  permission. Confirm the light goes red, the panel shows the prompt, and an
  option click approves it.

## Build and start-up

- Swift Package, no Xcode project. `swift build` builds it.
- `scripts/bundle.sh` makes `SidebarHover.app` in `~/Applications`.
- `LSUIElement` is true: no Dock icon.
- A menu bar icon gives "Start at login" (via `SMAppService.mainApp`) and
  "Quit".
- Target: macOS 14 or later.

## Out of scope for version 1

Sounds, notifications, SSH-hosted herdr sessions, light position settings,
agents that do not run in herdr.
