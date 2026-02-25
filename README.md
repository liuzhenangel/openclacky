# OpenClacky

[![Build](https://img.shields.io/github/actions/workflow/status/clacky-ai/open-clacky/main.yml?label=build&style=flat-square)](https://github.com/clacky-ai/open-clacky/actions)
[![Release](https://img.shields.io/gem/v/openclacky?label=release&style=flat-square&color=blue)](https://rubygems.org/gems/openclacky)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1.0-red?style=flat-square)](https://www.ruby-lang.org)
[![Downloads](https://img.shields.io/gem/dt/openclacky?label=downloads&style=flat-square&color=brightgreen)](https://rubygems.org/gems/openclacky)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE.txt)

OpenClacky = Lovable + Supabase

**OpenClacky** is a CLI tool for building full-stack web applications — no technical background required. We spent months crafting a **Rails for AI** full-stack architecture that is fully production-ready, with one-click deployment, isolated dev/production environments, and automatic backups.

OpenClacky's goal is to deliver the best balance of **AI quality, AI cost, and AI speed**.

## Quick start

```bash
$ openclacky
```

- `/config` — Set your API key, model, and base URL
- `/new <project-name>` — Create a new project
- Type your requirements and start building

## Why OpenClacky?

|  | **Claude Code** | **Lovable + Supabase** | **OpenClacky** |
|---|---|---|---|
| **Target Users** | Professional developers | Non-technical users | Non-technical users |
| **Tech Stack** | Any | React + Supabase | Rails (full-stack) |
| **Full-Stack Integration** | ❌ DIY | ⚠️ Frontend/backend split | ✅ Unified full-stack |
| **Production-Ready** | ❌ Manual setup | ⚠️ Relies on third-party | ✅ Built-in |
| **One-Click Deploy** | ❌ | ⚠️ Platform lock-in | ✅ Deploy anywhere |
| **Dev/Prod Isolation** | ❌ | ❌ | ✅ Automatic |
| **Automatic Backups** | ❌ | ⚠️ Paid feature | ✅ Built-in |
| **AI Cost Control** | ❌ Pay per token | ❌ Subscription | ✅ Optimally balanced |
| **Data Ownership** | ✅ | ❌ Platform-owned | ✅ Fully yours |
| **Interface** | Terminal | Web UI | Terminal |

## Features

- [x] `/new <project-name>` — Scaffold a full-stack Rails web app in seconds
- [x] **Skills system** — Specialized AI workflows for deploy, frontend design, PDF, PPTX, and more
- [x] **Cost monitoring & compression** — Real-time cost tracking, automatic message compression (up to 90% savings)
- [x] **One-click deployment** — Ship to production with a single command (with Clacky CDE)
- [x] **Autonomous AI agent** — Multi-step task execution with undo/redo
- [x] **Multi-provider support** — OpenAI, Anthropic, DeepSeek, and any OpenAI-compatible API
- [ ] **Time Machine** — Visual history to rewind and branch any point in your project *(coming soon)*

## Installation

### Method 1: One-line Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/clacky-ai/open-clacky/main/scripts/install.sh | bash
```

### Method 2: RubyGems

**Requirements:** Ruby >= 3.1.0

```bash
gem install openclacky
```

## Configuration

Before using Clacky, you need to configure your settings:

```bash
$ openclacky

- /config
```

You'll be prompted to enter:
- **API Key**: Your API key from any OpenAI-compatible provider
- **Model**: Model name
- **Base URL**: OpenAI-compatible API endpoint

## Usage

### Scenario 1: Create a new web app

```bash
$ openclacky
> /new my-blog
# OpenClacky scaffolds a full-stack Rails app in seconds
# > Add a posts page with title, content, and author fields
# > Deploy to production
# > exit
```

### Scenario 2: Build a feature in an existing project

```bash
$ cd ~/my-project && openclacky
# > Add user authentication with email and password
# > Write tests for the auth flow
# > exit
```

### Scenario 3: Ask questions about your codebase

```bash
$ openclacky
# > How does the payment module work?
# > Where is the user session managed?
# > exit
```

## Install from Source

```bash
git clone https://github.com/clacky-ai/open-clacky.git
cd open-clacky
bundle install
bin/clacky
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/clacky` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/clacky-ai/open-clacky. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/clacky-ai/open-clacky/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the OpenClacky project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/clacky-ai/open-clacky/blob/main/CODE_OF_CONDUCT.md).
