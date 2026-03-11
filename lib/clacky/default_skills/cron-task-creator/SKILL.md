---
name: cron-task-creator
description: 'Create, manage, and run scheduled automated tasks (cron jobs) in Clacky. Use this skill whenever the user wants to create a new automated task or cron job, set up recurring automation, schedule something to run daily/weekly/hourly, view all scheduled tasks, edit an existing task prompt or cron schedule, enable or disable a task, delete a task, check task run history or logs, or run a task immediately via the WebUI. Trigger on phrases like 定时任务, 自动化任务, 每天自动, 创建任务, cron, 定时执行, scheduled task, automate this, run every day, set up automation, edit my task, list my tasks, what tasks do I have, disable task, run task now, task history, etc.'
disable-model-invocation: false
user-invocable: true
---

# Cron Task Creator

A skill for creating, managing, and running scheduled automated tasks in Clacky.

## Architecture Overview

```
Storage:
  ~/.clacky/tasks/<name>.md      # Task prompt file (self-contained AI instruction)
  ~/.clacky/schedules.yml        # All scheduled plans (YAML list)
  ~/.clacky/logger/clacky-*.log  # Execution logs (daily rotation)

WebUI Task Panel (Clacky Web Interface):
  - Automatically reads tasks/ + schedules.yml and renders the task list
  - Each row shows task name, cron expression, and content preview
  - Action buttons: ▶ Run (execute now), ✎ Edit (edit in session), ✕ (delete)
  - Run button triggers POST /api/tasks/run → executes task in a new session

API Endpoints (available when clacky server is running):
  GET    /api/tasks              → list all tasks
  POST   /api/tasks              → create task {name, content}
  GET    /api/tasks/:name        → get task content
  DELETE /api/tasks/:name        → delete task
  POST   /api/tasks/run          → run immediately {name}
  GET    /api/schedules          → list all schedules
  POST   /api/schedules          → create schedule {name, task, cron}
  DELETE /api/schedules/:name    → delete schedule
```

## Cron Expression Quick Reference

| Expression       | Meaning                    |
|-----------------|---------------------------|
| `0 9 * * 1-5`  | Weekdays at 09:00         |
| `0 9 * * *`    | Every day at 09:00        |
| `0 */2 * * *`  | Every 2 hours             |
| `*/30 * * * *` | Every 30 minutes          |
| `0 19 * * *`   | Every day at 19:00        |
| `0 8 * * 1`    | Every Monday at 08:00     |
| `0 0 1 * *`    | First day of every month  |

Field order: `minute hour day-of-month month day-of-week`

---

## Operations

### 1. LIST — Show all tasks

When user asks "what tasks do I have", "list scheduled tasks", etc.:

1. Run `ruby ~/.clacky/skills/cron-task-creator/scripts/list_tasks.rb`
2. Display results: task name, cron schedule, enabled status, last run status

If no tasks exist, inform the user and offer to create one or show templates.

**Key tip**: Remind the user that the Clacky WebUI Task Panel (sidebar → Tasks) also shows all tasks and supports direct management.

---

### 2. CREATE — New task

**Step 1: Gather required info** (only ask for what's missing)
- What should the task DO? (goal, behavior, output format)
- How often should it run? (or is it manual-only?)
- Any specific parameters? (URLs, file paths, output location, language)

**Step 2: Generate task name**
- Rule: only `[a-z0-9_-]`, lowercase, no spaces
- Examples: `daily_report`, `price_monitor`, `weekly_summary`

**Step 3: Write the task prompt file**
Path: `~/.clacky/tasks/<name>.md`

The prompt must be:
- **Self-contained**: the agent running it has zero prior context — include everything needed
- **Written as direct instructions** to an AI agent (imperative, not conversational)
- **Detailed**: include URLs, file paths, output format, language, expected output location

Good task prompt example:
```markdown
You are a price monitoring assistant. Complete the following task:

## Goal
Check the current BTC price on CoinGecko, compare with yesterday's price, and log an alert if the change exceeds 5%.

## Steps
1. Fetch https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true
2. Parse the JSON response to get current price and 24h change
3. If |change| > 5%, write an alert to ~/price_alerts/alert_YYYY-MM-DD.txt
4. Print the current price and change percentage

Execute immediately.
```

**Step 4: Write file and add schedule**

```bash
# Write task file
ruby ~/.clacky/skills/cron-task-creator/scripts/manage_task.rb create "<name>" "<content>"

# Add schedule (if applicable)
ruby ~/.clacky/skills/cron-task-creator/scripts/manage_schedule.rb add "<name>" "<task_name>" "<cron_expr>"
```

**Step 5: Confirm creation**

```
✅ Task created successfully!

📋 Task name: daily_standup
📄 File: ~/.clacky/tasks/daily_standup.md
⏰ Schedule: Weekdays at 09:00 (cron: 0 9 * * 1-5)

View and manage this task in the Clacky WebUI → Tasks panel. Click ▶ Run to execute immediately.
```

---

### 3. EDIT — Modify an existing task

When the user wants to change task content, cron schedule, or rename:

**Step 1**: Identify the task to modify (if unclear, LIST first and ask)

**Step 2**: Show current state (first 10 lines + cron expression)

**Step 3**: Determine what to change
- Prompt only → rewrite `~/.clacky/tasks/<name>.md`
- Schedule only → update `cron` field in `schedules.yml`
- Both → do both
- Rename → rename .md file + update schedules.yml

```bash
# Update task content
ruby ~/.clacky/skills/cron-task-creator/scripts/manage_task.rb update "<name>" "<new_content>"

# Update cron schedule
ruby ~/.clacky/skills/cron-task-creator/scripts/manage_schedule.rb update "<schedule_name>" "<new_cron>"
```

**Step 4**: Confirm changes

```
✅ Task updated!
📋 daily_standup
  Prompt: updated ✓
  Schedule: 0 9 * * 1-5 → 0 8 * * 1-5 (now weekdays at 08:00)
```

---

### 4. ENABLE / DISABLE — Toggle a task

```bash
ruby ~/.clacky/skills/cron-task-creator/scripts/manage_schedule.rb toggle "<schedule_name>" true|false
```

Confirm:
```
✅ daily_standup has been disabled.
   To re-enable: say "enable daily_standup"
```

---

### 5. DELETE — Remove a task

Always confirm before deleting (unless the user has explicitly said to delete):

```
⚠️ Are you sure you want to delete daily_standup? This cannot be undone.
```

```bash
ruby ~/.clacky/skills/cron-task-creator/scripts/manage_task.rb delete "<name>"
```

---

### 6. HISTORY — View run history

```bash
ruby ~/.clacky/skills/cron-task-creator/scripts/task_history.rb "<task_name>"
```

Display format:
```
📊 Run History: ai_news_x_daily

Mar 10  19:00  ❌ Failed  — JSON::ParserError: unexpected end of input
Mar 09  19:00  ✅ Success — took 1m 42s
Mar 08  19:00  ✅ Success — took 2m 10s
Mar 07  19:00  ⚠️ Skipped — (task was disabled)

Recent error:
  JSON::ParserError at line 226
  Possible cause: API response was truncated or empty
```

---

### 7. RUN NOW — Execute immediately

```
▶️ Go to the Clacky WebUI → Tasks panel, find the task, and click ▶ Run.

The task will execute in a new session. You can watch it run in real time via the WebUI.
```

If the user wants to run the task in the current session, read the task file and execute the instructions directly.

---

### 8. TEMPLATES — Browse common task templates

When user says "what templates are there" or "what can I automate":

```
📚 Common Task Templates — pick one to get started:

1. 📰 AI News Digest       — Daily fetch of AI news from X/RSS, generate Markdown report
2. 💰 Price Monitor        — Check crypto/stock prices on a schedule, log alerts on anomalies
3. 📊 Weekly Work Summary  — Every Monday, summarize last week's work into a report
4. 🌤 Weather Reminder     — Fetch weather every morning and save to file
5. 🔍 Competitor Monitor   — Periodically scrape competitor sites for changes
6. 📝 Journal Prompt       — Evening reminder to journal with daily reflection questions
7. 🔗 Link Health Check    — Periodically verify specified URLs are accessible
8. 📂 File Backup          — Regularly back up a specified directory to another location

Tell me which one interests you, or describe your own use case!
```

---

## Important Notes

- Task names: only `[a-z0-9_-]`, no spaces, no uppercase
- When modifying `schedules.yml`: always read → modify → write back the full file (never append directly)
- Task prompt files must be **self-contained** — the executing agent has no prior memory
- Clacky server must be running for cron to trigger automatically (checked every minute)
- The WebUI Task Panel is the preferred interface for managing tasks — always remind the user to check it after changes
- Path expansion: always use absolute paths, expand `~` to the actual home directory
