# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.1] - 2026-01-29

### Added
- User tips for better guidance and feedback
- Batch TODO operations for improved task management
- Markdown output support for better formatted responses
- Text style customization options

### Improved
- Tool execution with slow progress indicators for long-running operations
- Progress UI refinements for better visual feedback
- Session restore now shows recent messages for context
- TODO area UI enhancements with auto-hide when all tasks completed
- Work status bar styling improvements
- Text wrapping when moving input to output area
- Safe shell output improvements for better readability
- Task info display optimization (only show essential information)
- TODO list cleanup and organization

### Fixed
- Double paste bug causing duplicate input
- Double error message display issue
- TODO clear functionality
- RSpec test hanging issues

### Removed
- Tool emoji from output for cleaner display

## [0.6.0] - 2026-01-28

### Added
- **New UI System (UI2)**: Complete component-based UI rewrite with modular architecture (InputArea, OutputArea, TodoArea, ToolComponent, ScreenBuffer, LayoutManager)
- **Slash Commands**: `/help`, `/clear`, `/exit` for quick actions
- **Prompt Caching**: Significantly improved performance and reduced API costs
- **Theme System**: Support for multiple UI themes (base, hacker, minimal)
- **Session Management**: Auto-keep last 10 sessions with datetime naming

### Improved
- Advanced inline input with Unicode support, multi-line handling, smooth scrolling, and rapid paste detection
- Better terminal resize handling and flicker-free rendering
- Work/idle status indicators with token cost display
- Enhanced tool execution feedback and multiple tool rejection handling
- Tool improvements: glob limits, grep performance, safe shell security, UTF-8 encoding fixes

### Fixed
- Input flickering, output scrolling, Ctrl+C behavior, image copying, base64 warnings, prompt cache issues

### Removed
- Legacy UI components (Banner, EnhancedPrompt, Formatter, StatusBar)
- Max cost/iteration limits for better flexibility

## [0.5.6] - 2026-01-18

### Added
- **Image Support**: Added support for image handling with cost tracking and display
- **Enhanced Input Controls**: Added Emacs-like Ctrl+A/E navigation for input fields
- **Session Management**: Added `/clear` command to clear session history
- **Edit Mode Switching**: New feature to switch between different edit modes
- **File Operations**: Support for reading from home directory (`~/`) and current directory (`.`)
- **Image Management**: Ctrl+D hotkey to delete images functionality

### Improved
- **Cost Tracking**: Display detailed cost information at every turn for better transparency
- **Performance**: Test suite speed optimizations and performance improvements
- **Token Efficiency**: Reduced token usage in grep operations for cost savings

### Fixed
- Fixed system Cmd+V copy functionality for multi-line text
- Fixed input flickering issues during text editing
- Removed unnecessary blank lines from image handling

## [0.5.4] - 2026-01-16

### Added
- **Automatic Paste Detection**: Rapid input detection automatically identifies paste operations
- **Word Wrap Display**: Long input lines automatically wrap with scroll indicators (up to 15 visible lines)
- **Full-width Terminal Display**: Enhanced prompt box uses full terminal width for better visibility

### Improved
- **Smart Ctrl+C Handling**: First press clears content, second press (within 2s) exits
- **UTF-8 Encoding**: Better handling of multi-byte characters in clipboard operations
- **Cursor Positioning**: Improved cursor tracking in wrapped lines
- **Multi-line Paste**: Better display for pasted content with placeholder support

## [0.5.0] - 2026-01-11

### Added
- **Agent Mode**: Autonomous AI agent with tool execution capabilities
- **Built-in Tools**: 
  - `safe_shell` - Safe shell command execution with security checks
  - `file_reader` - Read file contents
  - `write` - Create/overwrite files with diff preview
  - `edit` - Precise file editing with string replacement
  - `glob` - Find files using glob patterns
  - `grep` - Search file contents with regex
  - `web_search` - Search the web for information
  - `web_fetch` - Fetch and parse web pages
  - `todo_manager` - Task planning and tracking
  - `run_project` - Project dev server management
- **Session Management**: Save, resume, and list conversation sessions
- **Permission Modes**: 
  - `auto_approve` - Automatically execute all tools
  - `confirm_safes` - Auto-execute safe operations, confirm risky ones
  - `confirm_edits` - Confirm file edits only
  - `confirm_all` - Confirm every tool execution
  - `plan_only` - Plan without executing
- **Cost Control**: Track and limit API usage costs
- **Message Compression**: Automatic conversation history compression
- **Project Rules**: Support for `.clackyrules`, `.cursorrules`, and `CLAUDE.md`
- **Interactive Confirmations**: Preview diffs and shell commands before execution
- **Hook System**: Extensible event hooks for customization

### Changed
- Refactored architecture to support autonomous agent capabilities
- Enhanced CLI with agent command and session management
- Improved error handling and retry logic for network failures
- Better progress indicators during API calls and compression

### Fixed
- API compatibility issues with different providers
- Session restoration with error recovery
- Tool execution feedback loop
- Safe shell command validation
- Edit tool string matching and preview

## [0.1.0] - 2025-12-27

### Added
- Initial release of Clacky
- Interactive chat mode for conversations with Claude
- Single message mode for quick queries
- Configuration management for API keys
- Support for Claude 3.5 Sonnet model
- Colorful terminal output with TTY components
- Secure API key storage in `~/.clacky/config.yml`
- Multi-turn conversation support with context preservation
- Command-line interface powered by Thor
- Comprehensive test suite with RSpec

### Features
- `clacky chat [MESSAGE]` - Start interactive chat or send single message
- `clacky config set` - Configure API key
- `clacky config show` - Display current configuration
- `clacky version` - Show version information
- Model selection via `--model` option

[Unreleased]: https://github.com/yafeilee/clacky/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/yafeilee/clacky/compare/v0.1.0...v0.5.0
[0.1.0]: https://github.com/yafeilee/clacky/releases/tag/v0.1.0
