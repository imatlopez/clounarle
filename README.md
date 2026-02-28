# Therapy Journal

A macOS menu bar app that automates therapy session prep. You journal freely in a dedicated Claude Project, and the night before each therapy session, the app pulls your entries, generates a structured summary, and emails it to you and your therapist.

## How It Works

1. **Journal freely** in a dedicated Claude Project on claude.ai. The project uses a custom system prompt that acts as a warm, non-judgmental journaling companion.
2. **The night before a therapy session** (detected via Google Calendar), the app:
   - Pulls recent conversations from your Claude Project
   - Sends them to the Claude API to generate a structured summary
   - Emails the summary to you and your therapist via Gmail

## Summary Format

Each summary includes:
- **This week's themes** — recurring topics across your entries
- **Emotional tone** — a brief reading of mood shifts throughout the week
- **Key highlights** — verbatim quotes or close paraphrases worth surfacing
- **Possible things to explore in session** — suggested discussion points

## Setup

### 1. Build & Install

```bash
cd TherapyJournal
swift build -c release
# Copy the built binary to /Applications or run directly
```

Or open in Xcode:
```bash
open Package.swift
```

### 2. Create Your Claude Journal Project

1. Go to [claude.ai](https://claude.ai) and create a new **Project**
2. In the project's system prompt, paste the contents of `Resources/JournalingSystemPrompt.txt`
3. Note the **Organization ID** and **Project ID** from the URL:
   ```
   https://claude.ai/project/{org-id}/{project-id}
   ```

### 3. Google Cloud Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project (or use an existing one)
3. Enable the **Google Calendar API** and **Gmail API**
4. Create **OAuth 2.0 credentials** (Desktop application)
5. Add `http://127.0.0.1:8089/oauth/callback` as an authorized redirect URI
6. Copy the Client ID and Client Secret

### 4. Configure the App

Open **Preferences** from the menu bar icon and fill in:

**General tab:**
- Your email address
- Therapist's email address
- Calendar keyword (e.g., "Therapy", "Dr. Smith")
- Summary send time (default: 8:00 PM)
- Claude Project URL, Organization ID, and Project ID
- Launch at Login toggle

**Credentials tab:**
- **Claude Session Key**: Open claude.ai in your browser → DevTools → Application → Cookies → copy the `sessionKey` value
- **Claude API Key**: Your Anthropic API key (`sk-ant-...`)

**Google tab:**
- Google Client ID and Client Secret
- Click "Sign In with Google" to authorize Calendar and Gmail access

## Menu Bar Options

- **Generate Summary Now** — manually trigger the summary pipeline
- **Open Claude Journal Project** — opens your Claude Project in the browser
- **Preferences** — configure emails, calendar, credentials
- **Last summary** — shows date and sent/failed status
- **Quit**

## How the Nightly Check Works

1. At your configured time (default 8:00 PM), the app checks Google Calendar for tomorrow
2. If an event matching your keyword exists, it triggers the pipeline
3. Journal conversations from the past 7 days are fetched from Claude.ai
4. The Claude API generates a structured summary
5. The summary is emailed to you and your therapist via Gmail
6. You get a macOS notification confirming success or failure

## File Locations

- **Config**: `~/Documents/TherapyJournal/config.json`
- **Logs**: `~/Documents/TherapyJournal/app.log`
- **Credentials**: macOS Keychain (service: `com.therapyjournal.app`)

## Error Handling

- **Session cookie expired**: Menu bar notification prompting you to refresh it in Preferences
- **Calendar check fails**: Logged silently, retried next night
- **Email fails**: macOS notification with option to retry
- **All activity**: Logged to `~/Documents/TherapyJournal/app.log`

## Tech Stack

- Swift + SwiftUI
- NSStatusItem for menu bar
- Google Calendar API + Gmail API via OAuth 2.0
- Claude API (claude-sonnet-4-6) for summary generation
- Claude.ai internal API (session cookie) for fetching journal conversations
- UserNotifications for alerts
- macOS Keychain for credential storage
