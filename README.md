# Therapy Journal

A macOS menu bar app that automates therapy session prep. You journal freely in a dedicated Claude Project, and the night before each therapy session, the app pulls your entries, generates a structured summary, and emails it to you and your therapist.

## How It Works

1. **Journal freely** in a dedicated Claude Project on claude.ai. The project uses a custom system prompt that acts as a warm, non-judgmental journaling companion.
2. **The night before a therapy session** (detected from your macOS Calendar), the app:
   - Pulls recent conversations from your Claude Project (since your last session)
   - Generates a structured summary via Claude on claude.ai
   - Emails the summary to you and your therapist via Mail.app as a formatted HTML email

## Summary Format

Each summary is a therapist-ready briefing:

- **What's been happening** — specific events, situations, and decisions (not abstract categories)
- **How they're relating to it** — the client's framing, emotional register, and narrative shifts
- **In their own words** — 3–5 verbatim quotes worth returning to in session
- **What feels unresolved or charged** — what kept coming up, what was avoided, open questions

## Requirements

- macOS 26 (Tahoe) or later
- [Mail.app](https://support.apple.com/guide/mail/welcome/mac) configured with an email account
- A [Claude](https://claude.ai) account (Pro or Free — no API key needed)
- A [Claude Project](https://claude.ai) for journaling

## Setup

### 1. Build & Run

```bash
git clone git@github.com:imatlopez/clounarle.git
cd clounarle

# Build the .app bundle and launch it
./scripts/build-app.sh
open ".build/Therapy Journal.app"
```

The app appears as a 📖 icon in your menu bar — no Dock icon, no main window.

> **Note:** Always launch via `./scripts/build-app.sh` so the bundle is properly code-signed. This keeps macOS permissions (Calendar, Mail.app) persistent across rebuilds — you'll only be asked once per permission type.

### 2. Create Your Claude Journal Project

1. Go to [claude.ai](https://claude.ai) and create a new **Project**
2. In the project's custom instructions, paste the contents of [`Resources/JournalingSystemPrompt.txt`](Resources/JournalingSystemPrompt.txt):

   > You are a warm, attentive journaling companion. Your role is to be a safe space for someone to process their thoughts and feelings — nothing more, nothing less.

3. Note the **Project URL** from your browser's address bar:
   ```
   https://claude.ai/project/{project-id}
   ```

### 3. Get Your Claude Cookies

The app uses your full browser session cookie for all Claude interactions (fetching journal entries and generating summaries). You need to copy the complete cookie header — not just a single cookie value.

1. Open [claude.ai](https://claude.ai) in your browser and sign in
2. Open DevTools (`Cmd+Option+I`) → **Network** tab
3. Click any request to claude.ai in the list
4. Under **Request Headers**, find the `Cookie:` header
5. Copy the **entire value** (it starts with something like `sessionKey=...` and contains multiple cookies including `cf_clearance`)

### 4. Configure the App

Click the 📖 menu bar icon → **Preferences...**

**General tab:**
| Setting | What to enter |
|---------|---------------|
| Your email | Where to send the summary |
| Therapist's email | Your therapist's email address |
| Session keyword | Text to match in Calendar events (e.g. `Therapy`, `Dr. Smith`) |
| Send time | When to check for tomorrow's session (default: 8:00 PM) |
| Project URL | Your Claude Project URL (e.g. `https://claude.ai/project/...`) |
| Summary language | English or Spanish |

**Credentials tab:**
| Setting | What to enter |
|---------|---------------|
| Claude Cookies | The full `Cookie:` header value from step 3 |

### 5. Grant Permissions

On first run, the app will ask for:
- **Calendar access** — to check for therapy sessions on your calendar
- **Automation access** — to send emails through Mail.app

These are stored per code-signing identity and persist across app rebuilds as long as you use `./scripts/build-app.sh`.

## Usage

### Menu Bar Options

| Menu item | What it does |
|-----------|-------------|
| **Generate Summary Now** | Full pipeline — fetch entries, summarize, email you + therapist |
| **Preview Summary** | Generate summary without emailing therapist — opens a preview window |
| **Open Claude Journal Project** | Opens your Claude Project in the browser |
| **Last summary** | Date and status of the most recent run (sent / skipped / failed) |
| **Preferences...** | Open settings |
| **Quit** | Exit the app |

### Preview / Test Mode

Click **Preview Summary** to generate a summary without emailing your therapist. A window opens showing the full summary text. From there you can click **Send to Me Only** to receive it at your configured email — useful for checking formatting or testing the pipeline before your first real session.

### Daily Workflow

1. Journal in your Claude Project whenever you want — it's just a conversation
2. The app checks your calendar every night at the configured time
3. If there's a therapy session tomorrow, it automatically:
   - Fetches your journal conversations since your last session (not a fixed 7-day window)
   - Generates a structured summary via Claude on claude.ai
   - Sends the HTML-formatted summary to you and your therapist through Mail.app
4. You get a notification confirming success, or an alert if no entries were found

### Refreshing Your Session Cookie

The session cookie expires periodically. When it does:
- You'll get a macOS notification: "Your Claude session cookie has expired"
- Follow step 3 above to copy a fresh cookie from your browser
- Paste it into **Preferences → Credentials → Claude Cookies**

## File Locations

| What | Where |
|------|-------|
| Config | `~/Documents/TherapyJournal/config.json` |
| Logs | `~/Documents/TherapyJournal/app.log` |
| Last status | `~/Documents/TherapyJournal/last_status.json` |
| Credentials | macOS Keychain (service: `com.therapyjournal.app`) |

## Error Handling

- **Session cookie expired** → notification prompting you to refresh it in Preferences
- **No journal entries found** → notification "Report skipped", status shows as skipped (not failed)
- **Calendar check fails** → logged silently, retried next night
- **Email fails** → macOS notification with error details
- **All activity** → logged to `~/Documents/TherapyJournal/app.log`

## Tech Stack

- Swift 6.2 + SwiftUI, targeting macOS 26 (Tahoe)
- `NSStatusItem` for menu bar integration
- `EventKit` for local calendar access (reads all synced calendars — iCloud, Google, Exchange, etc.)
- `NSAppleScript` → Mail.app for sending HTML emails
- Claude.ai session cookie for all Claude interactions (fetching journals + generating summaries)
- `UserNotifications` for alerts
- macOS Keychain for credential storage

## Project Structure

```
Sources/TherapyJournal/
├── TherapyJournalApp.swift          # @main, AppDelegate, NSStatusItem
├── Models/
│   └── AppModels.swift              # All data types
├── Services/
│   ├── CalendarService.swift        # EventKit — checks tomorrow for keyword match
│   ├── ClaudeConversationFetcher.swift  # Fetches conversations via claude.ai session cookie
│   ├── SummaryGenerator.swift       # Summary generation via claude.ai chat
│   ├── EmailService.swift           # Sends HTML email via Mail.app (AppleScript)
│   ├── SummaryOrchestrator.swift    # Full pipeline: fetch → summarize → email
│   ├── NightlyScheduler.swift       # Fires at configured time, checks calendar
│   └── KeychainManager.swift        # Secure credential storage
├── Utilities/
│   ├── Logger.swift                 # File logger → ~/Documents/TherapyJournal/app.log
│   └── NotificationManager.swift    # macOS notifications
└── Views/
    ├── MenuBarView.swift            # Popover menu
    ├── PreferencesView.swift        # 2 tabs: General, Credentials
    └── SummaryPreviewView.swift     # Preview window with "Send to Me Only"
```
