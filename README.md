# Therapy Journal

A macOS menu bar app that automates therapy session prep. You journal freely in a dedicated Claude Project, and the night before each therapy session, the app pulls your entries, generates a structured summary, and emails it to you and your therapist.

## How It Works

1. **Journal freely** in a dedicated Claude Project on claude.ai. The project uses a custom system prompt that acts as a warm, non-judgmental journaling companion.
2. **The night before a therapy session** (detected from your macOS Calendar), the app:
   - Pulls recent conversations from your Claude Project
   - Generates a structured summary via Claude on claude.ai
   - Emails the summary to you and your therapist via Mail.app

## Summary Format

Each summary includes:
- **This week's themes** — recurring topics across your entries
- **Emotional tone** — a brief reading of mood shifts throughout the week
- **Key highlights** — verbatim quotes or close paraphrases worth surfacing
- **Possible things to explore in session** — suggested discussion points

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

# Build the .app bundle
./scripts/build-app.sh

# Launch it
open ".build/Therapy Journal.app"
```

The app appears as a 📖 icon in your menu bar — no Dock icon, no main window.

### 2. Create Your Claude Journal Project

1. Go to [claude.ai](https://claude.ai) and create a new **Project**
2. In the project's custom instructions, paste the contents of [`Resources/JournalingSystemPrompt.txt`](Resources/JournalingSystemPrompt.txt):

   > You are a warm, attentive journaling companion. Your role is to be a safe space for someone to process their thoughts and feelings — nothing more, nothing less.
   >
   > It welcomes you warmly, asks gentle follow-up questions, reflects back what it hears, and never gives advice or diagnoses. See the full prompt in the file.

3. Note the **Organization ID** and **Project ID** from the URL:
   ```
   https://claude.ai/project/{org-id}/{project-id}
   ```

### 3. Get Your Claude Session Key

The app uses a session cookie for all Claude interactions (fetching conversations and generating summaries):

1. Open [claude.ai](https://claude.ai) in your browser
2. Open DevTools (`Cmd+Option+I`) → **Application** tab → **Cookies** → `https://claude.ai`
3. Copy the value of the `sessionKey` cookie

### 4. Configure the App

Click the 📖 menu bar icon → **Preferences...**

**General tab:**
| Setting | What to enter |
|---------|---------------|
| Your email | Where to send the summary |
| Therapist's email | Your therapist's email address |
| Session keyword | Text to match in Calendar events (e.g. `Therapy`, `Dr. Smith`) |
| Send time | When to check for tomorrow's session (default: 8:00 PM) |
| Project URL | Your Claude Project URL |
| Organization ID | From the project URL |
| Project ID | From the project URL |

**Credentials tab:**
| Setting | What to enter |
|---------|---------------|
| Session Key | The `sessionKey` cookie from step 3 |

### 5. Grant Permissions

On first run, the app will ask for:
- **Calendar access** — to check for therapy sessions on your calendar
- **Automation access** — to send emails through Mail.app

## Usage

### Menu Bar Options

| Menu item | What it does |
|-----------|-------------|
| **Generate Summary Now** | Manually trigger the full pipeline (fetch → summarize → email) |
| **Open Claude Journal Project** | Opens your Claude Project in the browser |
| **Last summary** | Shows date and sent/failed status of the most recent summary |
| **Preferences...** | Open settings |
| **Quit** | Exit the app |

### Daily Workflow

1. Journal in your Claude Project whenever you want — it's just a conversation
2. The app checks your calendar every night at the configured time
3. If there's a therapy session tomorrow, it automatically:
   - Fetches your journal conversations from the past 7 days
   - Generates a structured summary via Claude on claude.ai
   - Sends the summary to you and your therapist through Mail.app
4. You get a notification confirming success or failure

### Manual Trigger

Click **Generate Summary Now** from the menu bar to run the pipeline immediately, even without a calendar event. Useful for testing or if you want a summary on demand.

## File Locations

| What | Where |
|------|-------|
| Config | `~/Documents/TherapyJournal/config.json` |
| Logs | `~/Documents/TherapyJournal/app.log` |
| Last status | `~/Documents/TherapyJournal/last_status.json` |
| Credentials | macOS Keychain (service: `com.therapyjournal.app`) |

## Error Handling

- **Session cookie expired** → notification prompting you to refresh it in Preferences
- **Calendar check fails** → logged silently, retried next night
- **Email fails** → macOS notification with error details
- **All activity** → logged to `~/Documents/TherapyJournal/app.log`

## Tech Stack

- Swift 6.2 + SwiftUI, targeting macOS 26 (Tahoe)
- `NSStatusItem` for menu bar integration
- `EventKit` for local calendar access (reads all synced calendars — iCloud, Google, Exchange, etc.)
- `NSAppleScript` → Mail.app for sending emails
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
│   ├── EmailService.swift           # Sends email via Mail.app (AppleScript)
│   ├── SummaryOrchestrator.swift    # Full pipeline: fetch → summarize → email
│   ├── NightlyScheduler.swift       # Fires at configured time, checks calendar
│   └── KeychainManager.swift        # Secure credential storage
├── Utilities/
│   ├── Logger.swift                 # File logger → ~/Documents/TherapyJournal/app.log
│   └── NotificationManager.swift    # macOS notifications
└── Views/
    ├── MenuBarView.swift            # Popover menu
    └── PreferencesView.swift        # 2 tabs: General, Credentials
```
