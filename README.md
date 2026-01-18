# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Amp](https://ampcode.com) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)) repeatedly until all tasks are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and task tracking (either `prd.json` or GitHub Issues).

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Features

- **Two task sources**: Local `prd.json` file or GitHub Issues
- **GitHub Integration**: Works with GitHub Issues, Projects, and CI
- **Concurrent workers**: Multiple Ralph instances can work on the same repository safely
- **Watch mode**: Continuously monitor for new issues
- **CI verification**: Waits for CI to pass before closing issues
- **Issue refinement**: Automatically converts rough ideas into proper user stories

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Amp CLI](https://ampcode.com)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project
- For GitHub mode: [GitHub CLI](https://cli.github.com/) installed and authenticated (`brew install gh && gh auth login`)

## Quick Start

### Option A: GitHub Issues Mode (Recommended)

```bash
# Clone Ralph
git clone https://github.com/Dowser/ralph-claude-git.git
cd ralph-claude-git

# Initialize your target project for Ralph
cd /path/to/your/project
/path/to/ralph-claude-git/ralph.sh --init

# Commit and push the issue templates
git add .github/ISSUE_TEMPLATE/
git commit -m "feat: add Ralph issue templates"
git push

# Create issues using the GitHub UI, then run Ralph
/path/to/ralph-claude-git/ralph.sh --source github
```

### Option B: Local PRD Mode

```bash
# Copy Ralph files to your project
mkdir -p scripts/ralph
cp /path/to/ralph/ralph.sh scripts/ralph/
cp /path/to/ralph/prompt-claude.md scripts/ralph/
chmod +x scripts/ralph/ralph.sh

# Create prd.json with your user stories (see prd.json.example)
# Then run Ralph
./scripts/ralph/ralph.sh
```

## Usage

```
Ralph - Autonomous AI Agent for Software Development

USAGE:
  ./ralph.sh [OPTIONS] [max_iterations]

OPTIONS:
  -h, --help              Show this help message and exit
  -t, --tool TOOL         AI tool to use: 'claude' (default) or 'amp'
  -s, --source SOURCE     Source for user stories: 'prd' (default) or 'github'
  -w, --watch             Watch mode: continuously monitor for new issues
  -i, --interval SECONDS  Polling interval for watch mode (default: 60)
  --init                  Initialize repository for Ralph (GitHub mode only)

ARGUMENTS:
  max_iterations          Maximum iterations per batch (default: 10)

EXAMPLES:
  # Initialize a repository for Ralph
  ./ralph.sh --init

  # Run with GitHub issues as source
  ./ralph.sh --source github

  # Run 20 iterations with GitHub source
  ./ralph.sh --source github 20

  # Watch mode: continuously monitor for new issues
  ./ralph.sh --source github --watch --interval 120
```

## GitHub Issues Mode

GitHub mode allows Ralph to work with issues from your GitHub repository instead of a local `prd.json` file.

### Setting Up a Repository

Run the init command in your project directory:

```bash
/path/to/ralph/ralph.sh --init
```

This will:
1. Create required labels (`ralph-story`, `ralph-analyze`, `ralph-in-progress`)
2. Install the user story issue template
3. Detect GitHub Project configuration
4. Show current status and issue counts

After init, commit and push the issue templates:
```bash
git add .github/ISSUE_TEMPLATE/
git commit -m "feat: add Ralph issue templates"
git push
```

### Creating Issues

Create issues using the "User Story" template in GitHub. Each issue should include:

- **Priority** (1-5, where 1 is highest)
- **As a...** (user role)
- **I want...** (feature/capability)
- **So that...** (benefit)
- **Acceptance Criteria** (specific, verifiable requirements)

### Labels

Ralph uses three labels to manage issues:

| Label | Purpose |
|-------|---------|
| `ralph-story` | Ready-to-implement user stories |
| `ralph-analyze` | Rough issues needing refinement into proper user stories |
| `ralph-in-progress` | Currently being worked on (concurrency lock) |

### Issue Refinement (ralph-analyze)

For rough ideas or bug reports that need analysis before implementation:

1. Create an issue with the `ralph-analyze` label
2. Ralph will analyze the codebase and rewrite the issue as a proper user story
3. The issue is then relabeled as `ralph-story` for implementation in the next iteration

### Watch Mode

Run Ralph continuously to pick up new issues as they're created:

```bash
./ralph.sh --source github --watch --interval 120
```

Ralph will:
- Process all available issues
- Wait for the specified interval (default: 60 seconds)
- Check for new issues and repeat
- Use Ctrl+C to stop

### Concurrent Workers

Multiple Ralph instances can safely work on the same repository. Ralph uses a claim-and-verify mechanism:

1. Each worker has a unique ID (hostname + PID + timestamp)
2. When picking an issue, Ralph adds the `ralph-in-progress` label and posts a claim comment
3. After a short delay, Ralph verifies it was the first to claim
4. If another worker claimed first, Ralph backs off and tries a different issue

### CI Verification

Ralph waits for CI to pass before closing an issue:

1. After pushing, Ralph runs `gh run watch` to wait for CI
2. If CI fails, Ralph views the logs, fixes the issues, and pushes again
3. Only after CI passes does Ralph close the issue

If your repository has no CI workflows, Ralph will skip this check.

### GitHub Project Integration

If your repository has a GitHub Project board, Ralph will:
- Move issues to "In progress" when starting work
- Move issues to "Done" when completed

The project must have a "Status" field with "In progress" and "Done" options.

## Local PRD Mode

### Creating a PRD

Use the PRD skill to generate requirements:

```
Load the prd skill and create a PRD for [your feature description]
```

Then convert to Ralph format:

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

### Running Ralph

```bash
# Using Claude Code (default)
./ralph.sh [max_iterations]

# Using Amp
./ralph.sh --tool amp [max_iterations]
```

Ralph will:
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

## Workflow (GitHub Mode)

For each iteration, Ralph:

1. **Pulls latest code** - ensures working with the most recent version
2. **Checks for issues** - prioritizes `ralph-analyze` over `ralph-story`
3. **Claims the issue** - adds label and verifies exclusive claim
4. **Moves to "In progress"** - updates GitHub Project board
5. **Implements the story** - writes code, runs tests
6. **Commits and pushes** - with message `feat: #[number] - [title]`
7. **Waits for CI** - monitors until CI passes (or fixes failures)
8. **Closes the issue** - with summary of changes
9. **Updates progress.txt** - logs learnings for future iterations

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | Main script with all modes (GitHub, PRD, watch, init) |
| `prompt-github.md` | Instructions for GitHub Issues mode |
| `prompt-claude.md` | Instructions for local PRD mode (Claude Code) |
| `prompt-amp.md` | Instructions for local PRD mode (Amp) |
| `prd.json` | User stories for local PRD mode |
| `progress.txt` | Append-only learnings for future iterations |
| `.github/ISSUE_TEMPLATE/` | GitHub Issue templates for user stories |

## Error Handling

Ralph includes robust error handling:

- **Retry logic**: Transient errors (network issues, "No messages returned") trigger automatic retries with exponential backoff
- **Work completion detection**: If work was completed (CI passed, issue closed), errors don't trigger unnecessary retries
- **Claim conflicts**: If another worker claims an issue first, Ralph automatically tries the next issue

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- Task tracking (`prd.json` or GitHub Issues)

### Small Tasks

Each task should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md Updates

After each iteration, Ralph updates relevant `AGENTS.md` files with learnings. AI coding tools automatically read these files, so future iterations benefit from discovered patterns.

Examples of what to add:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

## Debugging

```bash
# Check GitHub issues status
gh issue list --label "ralph-story" --state open
gh issue list --label "ralph-in-progress" --state open

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10

# View CI status
gh run list --limit 5
```

## Requirements for GitHub Mode

For full functionality, ensure:

1. **GitHub CLI authenticated with project scope**:
   ```bash
   gh auth login
   gh auth refresh -s project
   ```

2. **CI workflows configured** (optional but recommended):
   - Ralph will wait for CI to pass before closing issues
   - If no workflows exist, this check is skipped

3. **GitHub Project** (optional):
   - Create a project with the same name as your repository
   - Add a "Status" field with "In progress" and "Done" options

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub CLI documentation](https://cli.github.com/manual/)
