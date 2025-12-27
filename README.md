# Fetch: The Invisible Bridge 🌉

> **Use Gemini 2.0 Flash (Free Web) as the backend for Aider.** > No API Keys. No Limits. Pure "Telepathy".

Fetch is a lightweight macOS utility that acts as a **local proxy server**. It tricks [Aider](https://aider.chat/) into thinking it's talking to an OpenAI-compatible API, but actually forwards your code to a hidden **Google Gemini** web session in the background.

## 🧠 The Philosophy

- **Aider is the Hand**: The world's best AI coding agent (CLI).
- **Gemini is the Brain**: Google's powerful 2M context window model (Free).
- **Fetch is the Wire**: An invisible pipe connecting them.

We don't try to reimplement Aider's logic in Swift. We just provide the connection.

## 🚀 Quick Start

### 1. Start the Bridge
Open **Fetch.app**. You will see a small dashboard status window.
- Ensure the **"Gemini Link"** indicator is 🟢 Green.
- If it's 🔴 Red, click "Login" to sign in to your Google account in the hidden window.

### 2. Connect Aider (Terminal)
Open your favorite terminal (iTerm2, Terminal.app) in your project folder.

Run the following commands to point Aider to Fetch:

```bash
# 1. Point Aider to Fetch's local server
export OPENAI_API_BASE=http://127.0.0.1:3000/v1

# 2. Set a dummy key (Aider requires this to start)
export OPENAI_API_KEY=sk-bridge-dummy

# 3. Launch Aider (We force a compatible model name)
aider --model openai/gemini-2.0-flash --no-auto-commits

```

### 3. Magic Happens

Type `hi` in Aider.

* **Fetch** receives the request.
* **Fetch** types it into the hidden Gemini window.
* **Gemini** generates the response.
* **Fetch** streams the text back to Aider character-by-character.

---

## 🛠️ Architecture

```mermaid
graph LR
    A[Terminal (Aider)] -- HTTP POST --> B[Fetch (Local Server :3000)]
    B -- JS Injection --> C[Hidden WebView (Gemini.com)]
    C -- MutationObserver --> B
    B -- SSE Stream --> A

```

### Key Components

* **LocalAPIServer (:3000)**: Mimics the OpenAI Chat Completion API. It handles the `stream=true` requests from Aider.
* **GeminiWebManager**: A headless WebKit instance that loads `gemini.google.com`. It uses JavaScript to inject prompts and scrape responses in real-time.
* **ChromeBridge**: (Optional) Attempts to steal cookies from your Chrome/Arc browser to achieve "Zero-Click Login".

## ❓ Troubleshooting

**Q: Aider says "Timeout" or hangs at "Waiting..."**
A: This usually means the JS injection missed the "Send" button on the web page.

* Check if the Fetch UI is running.
* Try running the query again.

**Q: Aider says "Authentication Error"**
A: You forgot to set the environment variables (`OPENAI_API_BASE`). Aider is trying to connect to the real OpenAI server.

**Q: Does this work with other agents?**
A: Yes! Any tool that supports `OpenAI-compatible` endpoints (like Cursor, Cline, or LangChain) can technically use Fetch as a backend.

---

## ⚠️ Disclaimer

This is an experimental "hack" that relies on the DOM structure of the Gemini web interface. If Google changes their website class names, this bridge might break until updated.

**Happy Vibe Coding!** 🥂
