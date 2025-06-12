# Claude GitHub Actions Research Documentation

## Overview

This document captures comprehensive research into how Anthropic's Claude GitHub Actions work, specifically focusing on the grll forks that add OAuth authentication support. The research examines two key repositories:

1. **grll-claude-code-action** - A fork of `anthropics/claude-code-action`
2. **grll-claude-code-base-action** - The base action that handles actual Claude interactions

## Initial Research Question

The primary research question was to understand:
- How these GitHub Actions make calls to Claude
- Whether they use process spawning to Claude Desktop or make actual API calls to Anthropic's API endpoints
- How OAuth authentication works with these actions

## Repository Analysis

### 1. grll-claude-code-action (The Wrapper)

**Location**: `/Users/ben/Documents/git/ben-vargas/grll-claude-code-action`

**Purpose**: This repository acts as a GitHub integration layer that:
- Monitors GitHub events (comments, issues, PRs) for trigger phrases
- Prepares context from GitHub data
- Creates prompt files for Claude
- Delegates actual Claude execution to a base action

**Key Finding**: This repository does NOT make direct API calls to Claude/Anthropic. It's purely an orchestration layer.

#### Architecture Flow
```
GitHub Event → Trigger Detection → Context Preparation → Prompt Creation → Delegate to Base Action
```

#### Key Components
- **Trigger System**: Responds to `/claude` comments or issue assignments
- **Context Gathering**: Uses `github-data-fetcher.ts` to retrieve PR/issue data
- **Prompt Generation**: Uses `create-prompt.ts` to format context for Claude
- **GitHub Authentication**: OIDC-based token exchange for secure GitHub interactions
- **MCP Server Setup**: Configures Model Context Protocol servers for extended functionality

#### OAuth Support (Added by Fork)
The fork adds OAuth authentication parameters:
- `use_oauth`: Boolean flag to enable OAuth
- `claude_access_token`: OAuth access token from Claude Max subscription
- `claude_refresh_token`: OAuth refresh token for renewal
- `claude_expires_at`: Token expiration timestamp

These credentials come from Claude Max subscriptions and can be found in:
- **Linux**: `~/.claude/.credentials.json`
- **macOS**: Keychain Access (search for "claude")

### 2. grll-claude-code-base-action (The Executor)

**Location**: `/Users/ben/Documents/git/ben-vargas/grll-claude-code-base-action`

**Purpose**: This action handles the actual execution of Claude, but still doesn't make direct API calls.

**Key Finding**: This action installs and invokes Claude Code CLI, which is the actual component making API calls.

#### Implementation Details
- Installs Claude Code CLI: `npm install -g @anthropic-ai/claude-code@1.0.11`
- Uses complex multi-process piping to handle large prompts
- Spawns Claude CLI with various configuration options

## Detailed Findings

### How Claude API Calls Actually Work

The complete architecture involves three layers:

```
GitHub Event
    ↓
grll-claude-code-action (prepares context)
    ↓
grll-claude-code-base-action (installs Claude Code CLI)
    ↓
Claude Code CLI (makes actual API calls)
    ↓
Anthropic API / AWS Bedrock / Google Vertex
```

**Key Insight**: Neither repository contains direct API client implementations. The actual API calls are made by Claude Code CLI, which is Anthropic's official command-line tool.

### Authentication Methods Supported

1. **Direct Anthropic API**: Uses `anthropic_api_key`
2. **AWS Bedrock**: Enabled with `use_bedrock: true`
3. **Google Vertex AI**: Enabled with `use_vertex: true`
4. **OAuth (Claude Max)**: Enabled with `use_oauth: true` (fork innovation)

### No Claude Desktop Process Spawning

The actions run entirely in GitHub Actions environment and do not spawn Claude Desktop processes. All interactions are through web APIs via Claude Code CLI.

## Follow-up Question 1: GitHub App Token Exchange

### Endpoint: `https://api.anthropic.com/api/github/github-app-token-exchange`

**What it is**: An Anthropic-hosted authentication service that bridges GitHub's OIDC authentication with the Claude GitHub App.

**Location in code**: `src/github/token.ts` in the `exchangeForAppToken` function

**How it works**:
1. GitHub Action obtains an OIDC token using `core.getIDToken("claude-code-github-action")`
2. This OIDC token is sent to Anthropic's endpoint
3. Anthropic validates the token and returns a GitHub App installation token
4. This token has permissions granted to the Claude GitHub App for that repository

**Purpose**:
- Eliminates need for manual GitHub token management
- Provides secure, temporary tokens scoped to the repository
- Simplifies setup - users only need to install the Claude GitHub App
- Tokens are automatically revoked when workflow ends

**Security Benefits**:
- No long-lived tokens stored as secrets
- Token scoped to specific repository
- Permissions controlled by GitHub App installation
- Automatic token lifecycle management

## Follow-up Question 2: Claude Code CLI Execution Environment

### Where It Runs

Claude Code CLI runs on **GitHub-hosted runners**, not on user's local machine or Anthropic's infrastructure.

### GitHub Runners Specifications
- **Operating Systems**: Ubuntu (latest), Windows, macOS
- **Hardware** (ubuntu-latest):
  - 2-core CPU
  - 7 GB RAM
  - 14 GB SSD space
- **Environment**: Fresh VM for each workflow run, destroyed after completion

### Installation and Execution Flow

1. **Repository Checkout**: `actions/checkout@v4`
2. **Runtime Setup**: Install Bun v1.2.11 via `oven-sh/setup-bun`
3. **Dependencies**: `bun install` in action directory
4. **Context Preparation**: Run `prepare.ts` to:
   - Setup GitHub authentication
   - Check trigger conditions
   - Create tracking comment
   - Setup branches
   - Generate prompt file
   - Configure MCP servers
5. **Claude Execution**: Invoke `grll/claude-code-base-action` which:
   - Installs Claude Code CLI
   - Configures authentication
   - Executes with prepared prompt
   - Captures output

### File System Access
```
/home/runner/work/your-repo/your-repo/  ← Repository files
/home/runner/temp/                      ← Temporary files (prompts)
/home/runner/.claude/                   ← Claude configuration
```

### Network Communication
- Runner → Anthropic API (Claude responses)
- Runner → GitHub API (creating comments, branches)
- Runner → MCP servers (additional tools if configured)

## CLI Invocation Method Comparison

### grll-claude-code-base-action Implementation

**Method**: Complex multi-process piping with `spawn`

```javascript
// Creates named pipe (FIFO) for large prompts
const pipePath = `/tmp/claude-prompt-${process.pid}.fifo`;
execSync(`mkfifo ${pipePath}`);

// Three processes:
1. spawn('cat', [promptFile, '>', pipePath])  // Write to pipe
2. spawn('claude', [...args])                 // Main Claude
3. spawn('cat', [pipePath])                   // Pipe to stdin
```

**CLI Arguments**:
```javascript
const BASE_ARGS = ["-p", "--verbose", "--output-format", "stream-json"];
// Plus conditional: --allowedTools, --disallowedTools, --max-turns, etc.
```

**Why Complex Piping**: Likely due to:
- Large prompt sizes (entire PRs/issues)
- GitHub Actions environment constraints
- Shell compatibility across different OS
- Legacy implementation reasons

### ai-sdk-provider-claude-code Implementation

**Method**: Simple, direct spawn approach

```javascript
const child = spawn(claudePath, args, {
  env: { ...process.env, ...envVars },
  stdio: ['pipe', 'pipe', 'pipe'],
});

// Direct stdin write
child.stdin.write(prompt);
child.stdin.end();
```

**Key Features**:
- Process pooling with concurrent execution management
- Session resumption support (`--resume`)
- Both streaming and non-streaming modes
- Custom error types and handling
- TypeScript with full type safety

### Implementation Comparison Table

| Feature | GitHub Action | AI SDK Provider |
|---------|--------------|----------------|
| Process spawn | Complex multi-process | Simple direct spawn |
| Prompt handling | Named pipes (FIFO) | Direct stdin write |
| Concurrency | Single execution | Process pool with queue |
| Session resumption | ❌ | ✅ |
| Streaming modes | Always streaming | Both modes |
| Error handling | Basic | Custom error classes |
| Default timeout | 10 minutes | 2 minutes |
| Environment | GitHub runner only | Any Node.js environment |
| Type safety | JavaScript | TypeScript |

## Key Insights

1. **No Direct API Implementation**: Neither repository contains actual Anthropic API client code. All API interactions are delegated to Claude Code CLI.

2. **OAuth Innovation**: The grll forks add OAuth support for Claude Max subscribers, making the tool accessible to individual developers without enterprise API access.

3. **Security Architecture**: Uses GitHub's OIDC for secure authentication and Anthropic's token exchange service for GitHub App permissions.

4. **Execution Environment**: Everything runs on ephemeral GitHub-hosted infrastructure, ensuring code privacy and security.

5. **Modular Design**: Clear separation of concerns:
   - GitHub integration layer (grll-claude-code-action)
   - Execution orchestration (grll-claude-code-base-action)
   - API interaction (Claude Code CLI)

## Configuration Example

```yaml
- uses: grll/claude-code-action@main
  with:
    # OAuth authentication (Claude Max)
    use_oauth: true
    claude_access_token: ${{ secrets.CLAUDE_ACCESS_TOKEN }}
    claude_refresh_token: ${{ secrets.CLAUDE_REFRESH_TOKEN }}
    claude_expires_at: ${{ secrets.CLAUDE_EXPIRES_AT }}
    
    # Alternative: Direct API
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    
    # Alternative: Cloud providers
    use_bedrock: true  # AWS
    use_vertex: true   # Google Cloud
```

## Summary

The grll forks of Anthropic's Claude GitHub Actions provide OAuth authentication support for Claude Max subscribers, enabling individual developers to use Claude in their GitHub workflows without requiring enterprise API access. The implementation uses a layered architecture where GitHub integration, execution orchestration, and API calls are cleanly separated, with the actual Claude interactions handled by Anthropic's official Claude Code CLI tool running on GitHub's infrastructure.