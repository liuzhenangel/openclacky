# How to Use OpenClacky

## Installation

```bash
gem install openclacky
```

**Requirements:** Ruby >= 3.1

## Quick Start

### 1. Start Clacky

```bash
clacky
```

### 2. Configure API Key (First Time)

In the chat interface, type:

```
/config
```

Then follow the prompts to set your API key:
- **OpenAI**: Get key from https://platform.openai.com/api-keys
- **Anthropic**: Get key from https://console.anthropic.com/

### 3. Start Chatting

Just type your questions or requests in the chat:

```
Help me write a Ruby script to parse CSV files
```

```
Create a web scraper for extracting article titles
```

## Key Features

### 🎯 Autonomous Agent Mode
Clacky can automatically execute complex tasks using built-in tools:
- **File Operations**: Read, write, edit, search files
- **Web Access**: Browse and search the web
- **Code Execution**: Run shell commands and test code
- **Project Management**: Git operations, testing, deployment

### 🔌 Skill System
Use powerful skills with simple shorthand commands:

```
/commit          # Smart git commit helper
/gem-release     # Automated gem publishing
```

Create your own skills in `.clacky/skills/` directory!

### 💬 Smart Memory Management
- **Automatic compression** for long conversations
- **Context preservation** while reducing token costs
- **Intelligent summarization** of conversation history

### ⚙️ Easy Configuration
- Interactive setup wizard
- Support for multiple API providers
- Cost tracking and usage limits
- Smart defaults for common use cases

## Common Commands in Chat

```
/config          # Configure API settings
/help            # Show available commands
/skills          # List available skills
```

## Why Choose OpenClacky?

✅ **Simple Setup** - Just `gem install` and start chatting  
✅ **Powerful Agent** - Executes complex tasks autonomously  
✅ **Extensible** - Create custom skills for your workflows  
✅ **Cost-Effective** - Smart memory compression saves tokens  
✅ **Multi-Provider** - Works with OpenAI and Anthropic  
✅ **Well-Tested** - 367+ passing tests ensure reliability  

## Learn More

- GitHub: https://github.com/clacky-ai/openclacky
- Report Issues: https://github.com/clacky-ai/openclacky/issues
- Version: 0.7.0
