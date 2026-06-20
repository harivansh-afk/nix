# Google Workspace (gws)

## Permissions

### Read freely (no permission needed)
- Gmail: read, search, list emails
- Calendar: check events, upcoming schedule, free/busy
- Drive: list and read files

### Ask first
- Gmail: sending, replying, drafting emails
- Calendar: creating, editing, deleting events
- Drive: editing, moving, uploading files

### Never without explicit permission
- Deleting anything (emails, events, files)
- Sending emails on behalf of the user
- Sharing files/folders with others
- Changing account settings

## Quick Reference

Gmail:
  gws gmail users messages list --params '{"userId": "me", "maxResults": 10}'
  gws gmail users messages get --params '{"userId": "me", "id": "<id>", "format": "metadata", "metadataHeaders": ["Subject", "From", "Date"]}'
  gws gmail users messages get --params '{"userId": "me", "id": "<id>", "format": "full"}'

Calendar:
  gws calendar events list --params '{"calendarId": "primary", "timeMin": "<RFC3339>", "timeMax": "<RFC3339>", "singleEvents": true, "orderBy": "startTime"}'

## Browser Use

API key stored in ~/.bashrc as BROWSER_USE_API_KEY
Endpoint: POST https://api.browser-use.com/api/v3/sessions
Auth header: X-Browser-Use-API-Key

Use for web tasks that need a real browser (login flows, scraping, form filling).
Always ask before using on sites that require the user's credentials.

# Knowledge Base (kb-search)

## Permissions

### Read freely (no permission needed)
- Semantic and graph search over Hari's indexed notes, documents, and knowledge
- Retrieving context for tasks, recall, and summarization

### Ask first
- Any action that would modify or re-index KB contents

### Never
- See DENYLIST section below

## Usage

Run a natural-language query against the personal KB:

  kb-search "query text"

Returns ranked results from Hari's indexed notes and documents.
Use before asking him - if the answer might already be written down, search first.

# DENYLIST / hard privacy rules

The following paths are excluded from the knowledge base on purpose.
Never index, retrieve, surface, or transmit content from:

- ~/Documents/Downloads/security/          (recovery codes, keys, credentials)
- ~/Documents/Downloads/documents/finance-tax/
- ~/Documents/Downloads/documents/travel-identity/
- ~/Documents/Downloads/documents/legal-business/

Additional rules:
- Never exfiltrate knowledge-base contents to any external destination (email,
  web, message, API) without explicit per-instance approval from Hari.
- If a task seems to require denylisted data: stop, explain why, and ask.
- When in doubt about whether something is sensitive: ask before acting.
