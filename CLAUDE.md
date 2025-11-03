# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Core Development
- **Setup**: `flutter pub get` - Install dependencies
- **Run**: `flutter run -d macos|linux|windows|chrome|web-server` - Run on specific platform
- **Build**: `flutter build <platform>` - Build for release (e.g., `flutter build web`)
- **Clean**: `flutter clean && flutter pub get` - Clean and reinstall dependencies
- **Format**: `dart format .` - Format code (required by pre-commit hook)

### Localization
- **Generate**: `flutter gen-l10n` or `make lan` - Generate localizations

### Testing
- **Test**: `flutter test` - Run tests
- **Test with coverage**: `flutter test --coverage`

### Code Quality
- **Analyze**: `flutter analyze` - Static analysis
- **Lint**: Enforced via pre-commit hook (automatically formats with `dart format .`)

### Build Commands (via Makefile)
- `make clean` - Clean build artifacts
- `make setup-git-hooks` - Setup required pre-commit hooks
- `make lan` - Generate localizations
- `make dep` - Validate dependencies
- `make upgrade` - Upgrade dependencies

## Architecture Overview

### Core Structure
ChatMCP is a cross-platform AI chat client built with Flutter that supports multiple LLM providers and MCP (Model Context Protocol) servers. The app follows a provider-based state management pattern with a clear separation of concerns.

### Key Architectural Components

#### 1. Data Layer (`lib/dao/`, `lib/repository/`)
- **DAOs**: Data Access Objects for SQLite operations (`lib/dao/init_db.dart`, `lib/dao/chat.dart`, `lib/dao/chat_message.dart`)
- **Repositories**: Abstraction layer with local and remote implementations (`lib/repository/local_chat_repository.dart`, `lib/repository/remote_chat_repository.dart`)
- **Database**: SQLite with libsql_dart support for remote sync capabilities

#### 2. State Management (`lib/provider/`)
- **Provider Pattern**: Uses Flutter Provider for state management
- **Key Providers**:
  - `ChatProvider`: Chat state and operations
  - `McpServerProvider`: MCP server configurations and connections
  - `SettingsProvider`: App settings and preferences
  - `ChatModelProvider`: LLM model selection and configuration

#### 3. MCP Integration (`lib/mcp/`)
- **Multi-transport Support**: stdio, SSE, and in-memory MCP clients
- **Client Types**:
  - `StdioClient`: Process-based MCP communication
  - `SSEClient`: Server-sent events transport
  - `InMemoryClient`: Built-in MCP tools (math, artifacts, etc.)
- **Server Management**: Dynamic MCP server discovery and configuration

#### 4. UI Layer (`lib/page/`, `lib/widgets/`)
- **Responsive Design**: Adaptive UI for desktop, mobile, and web
- **Component Library**: Custom widgets for markdown rendering, chat display, and settings
- **Layout System**: Modular layout components for different screen sizes

#### 5. LLM Integration (`lib/llm/`)
- **Multiple Providers**: OpenAI, Claude, DeepSeek, Ollama, Copilot, Claude Code
- **Unified Interface**: Consistent client interface across all LLM providers
- **Streaming Support**: Real-time response streaming via SSE

#### 6. Utilities (`lib/utils/`)
- **Platform-specific**: Conditional imports for desktop, mobile, and web
- **File Management**: Cross-platform file operations and content handling
- **Network**: HTTP clients, OAuth, and network utilities

### Data Storage
- **Desktop**: Platform-specific application directories (~/Library/Application Support/ChatMcp on macOS, %APPDATA%/ChatMcp on Windows, ~/.local/share/ChatMcp on Linux)
- **Mobile**: Application documents directory
- **Database**: SQLite with libsql_dart for remote synchronization capabilities
- **Sync**: LAN-based data synchronization between devices

### Key Features
- Multi-platform support (macOS, Windows, Linux, iOS, Android, Web)
- MCP server marketplace and dynamic server loading
- Multiple LLM provider support with unified interface
- Real-time chat with streaming responses
- Markdown rendering with LaTeX, mermaid diagrams, and HTML preview
- Artifact display and code execution
- Dark/light theme support
- Network synchronization for chat history

### Development Notes
- **Pre-commit Hook**: Mandatory code formatting on every commit
- **Line Width**: 150 characters (configured in analysis_options.yaml)
- **Database Migration**: Uses both sqflite and libsql_dart for legacy and new functionality
- **Internationalization**: Full localization support via flutter_localizations
- **Testing**: Includes unit tests with mockito for mocking