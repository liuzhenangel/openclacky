---
name: skill-add
description: Install skills from GitHub. Use when user provides a GitHub URL to install a skill or skill collection. Trigger on phrases like "install skill from github", "add skill from repo", "/skill-add https://github.com/..."
disable-model-invocation: false
user-invocable: true
---

# Skill Add — Install Skills from GitHub

Install skills from a GitHub repository into `~/.clacky/skills/`.

## Supported URL Formats

```
# Install all skills found in the repo's skills/ directories
https://github.com/user/repo

# Install all skills under a specific subdirectory
https://github.com/user/repo/skills

# Install a single specific skill by subpath
https://github.com/user/repo/skills/my-skill
```

## How to Run

Execute the installer script via shell:

```bash
ruby lib/clacky/default_skills/skill-add/scripts/install_from_github.rb <github_url>
```

The script will:
1. Clone the repo (shallow, depth=1)
2. Locate the skill(s) based on the URL (whole repo scan, or specific subpath)
3. Copy each skill to `~/.clacky/skills/<skill-name>/`
4. Report what was installed

After installation, the skill is immediately available as `/skill-name` in all sessions.

## Notes

- If a skill with the same name already exists, it is skipped (not overwritten)
- For creating new skills from scratch, use the `skill-creator` skill instead
