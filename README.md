# 💩 Poop

> Not gonna pay a shit to Grammarly. Fuck you, Grammarly.

A tiny macOS menu bar app that fixes your grammar instantly — select any text, press **⌘⇧F**, and it's corrected in place. Works in any app. Powered by any OpenAI-compatible LLM.

---

## How it works

1. Select text anywhere on your Mac
2. Press **⌘⇧F** (fully customisable)
3. Poop silently grabs the text, sends it to your LLM of choice, and pastes the corrected version back — all in under a second

No Grammarly subscription. No browser extension. No bullshit.

---

## Features

- **Works everywhere** — any app that accepts text input
- **Bring your own LLM** — OpenAI, Anthropic, OpenRouter, Groq, Ollama, LM Studio
- **Floating indicator** — a tiny pulsing dot at the bottom-right corner so you always know it's working, even with the menu bar hidden
- **Custom hotkey** — change the shortcut to whatever you want from Settings
- **Local model support** — run fully offline with Ollama or LM Studio (no API key needed)
- **Custom system prompt** — tweak the correction behaviour to your liking
- **Zero Dock presence** — lives purely in the menu bar, out of your way

---

## Supported Providers

| Provider | Notes |
|---|---|
| **OpenAI** | GPT-4o, GPT-4o mini, etc. |
| **Anthropic** | Claude 3.5 Haiku, Sonnet, etc. |
| **OpenRouter** | Access to 200+ models via one API key |
| **Groq** | Blazing fast inference |
| **Ollama** | Local, fully offline, no API key |
| **LM Studio** | Local, fully offline, no API key |

---

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ (to build from source)
- **Accessibility permission** (required to read selected text and paste back)

---

## Installation

Clone and build in Xcode:

```bash
git clone https://github.com/vkpdeveloper/poop.git
cd poop
open poop.xcodeproj
```

Hit **Run** (⌘R). Grant Accessibility access when prompted. That's it.

---

## Setup

1. Open **Settings** (click the ✦ menu bar icon → Settings, or press **⌘,**)
2. Pick your provider and paste your API key
3. Start fixing text

For **Ollama** or **LM Studio**, just make sure your local server is running — no API key needed.

---

## License

MIT — do whatever you want with it.
