#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop

set -e

# Help function
show_help() {
  cat << 'EOF'
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
                          Creates labels, issue templates, and shows status

ARGUMENTS:
  max_iterations          Maximum iterations per batch (default: 10)
                          In watch mode, this is iterations per polling cycle

SOURCES:
  prd      Read user stories from local prd.json file
  github   Read user stories from GitHub Issues (requires 'gh' CLI)

GITHUB MODE:
  In GitHub mode, Ralph works with issues labeled:
  - 'ralph-story'       Ready-to-implement user stories
  - 'ralph-analyze'     Issues needing refinement into user stories
  - 'ralph-in-progress' Currently being worked on (concurrency lock)

  Ralph will:
  1. First process any 'ralph-analyze' issues (refine into user stories)
  2. Then implement 'ralph-story' issues by priority
  3. Update GitHub Project board status if configured
  4. Close issues when complete

WATCH MODE:
  With --watch, Ralph runs continuously:
  - Processes all available issues
  - When done (or if no issues), waits for --interval seconds
  - Polls for new issues and repeats
  - Use Ctrl+C to stop

  Perfect for running Ralph as a background service that picks up
  new issues as they are created.

INIT MODE:
  With --init, Ralph sets up a repository for GitHub mode:
  - Creates required labels (ralph-story, ralph-analyze, ralph-in-progress)
  - Installs the user story issue template
  - Detects GitHub Project configuration
  - Shows current status and issue counts

EXAMPLES:
  # Initialize a repository for Ralph
  cd /path/to/project && /path/to/ralph/ralph.sh --init

  # Run with defaults (claude, prd source, 10 iterations)
  ./ralph.sh

  # Run with GitHub issues as source
  ./ralph.sh --source github

  # Run 20 iterations with GitHub source
  ./ralph.sh --source github 20

  # Watch mode: continuously monitor for new issues (check every 2 minutes)
  ./ralph.sh --source github --watch --interval 120

REQUIREMENTS:
  - For --source github: GitHub CLI (gh) must be installed and authenticated
    Install: brew install gh
    Auth:    gh auth login
    Scopes:  gh auth refresh -s project  (for project board updates)

For more information, see: https://github.com/denen99/ralph
EOF
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Init function for GitHub mode
run_init() {
  echo ""
  echo "==============================================================="
  echo "  Ralph Repository Initialization"
  echo "==============================================================="
  echo ""

  # Check prerequisites
  echo "Checking prerequisites..."
  echo ""

  # Check gh CLI
  if ! command -v gh &> /dev/null; then
    echo -e "${RED}[x] GitHub CLI (gh) not installed${NC}"
    echo "    Install with: brew install gh"
    exit 1
  else
    echo -e "${GREEN}[✓] GitHub CLI installed${NC}"
  fi

  # Check gh auth
  if ! gh auth status &> /dev/null; then
    echo -e "${RED}[x] GitHub CLI not authenticated${NC}"
    echo "    Run: gh auth login"
    exit 1
  else
    echo -e "${GREEN}[✓] GitHub CLI authenticated${NC}"
  fi

  # Check if we're in a git repo
  if ! git rev-parse --git-dir &> /dev/null; then
    echo -e "${RED}[x] Not in a git repository${NC}"
    exit 1
  else
    echo -e "${GREEN}[✓] Git repository detected${NC}"
  fi

  # Get repo info
  REPO_OWNER=$(gh repo view --json owner -q '.owner.login' 2>/dev/null)
  REPO_NAME=$(gh repo view --json name -q '.name' 2>/dev/null)
  REPO_URL=$(gh repo view --json url -q '.url' 2>/dev/null)

  if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
    echo -e "${RED}[x] Could not determine repository info${NC}"
    echo "    Make sure you're in a directory with a GitHub remote"
    exit 1
  fi

  echo -e "${GREEN}[✓] Repository: ${REPO_OWNER}/${REPO_NAME}${NC}"
  echo ""

  # Create labels
  echo "Setting up labels..."
  echo ""

  # ralph-story label
  if gh label create "ralph-story" --description "User story for Ralph autonomous agent" --color "5319E7" 2>/dev/null; then
    echo -e "${GREEN}[✓] Created label: ralph-story${NC}"
  else
    echo -e "${YELLOW}[~] Label exists: ralph-story${NC}"
  fi

  # ralph-in-progress label
  if gh label create "ralph-in-progress" --description "Issue is currently being worked on by Ralph" --color "FBCA04" 2>/dev/null; then
    echo -e "${GREEN}[✓] Created label: ralph-in-progress${NC}"
  else
    echo -e "${YELLOW}[~] Label exists: ralph-in-progress${NC}"
  fi

  # ralph-analyze label
  if gh label create "ralph-analyze" --description "Issue needs analysis and conversion to user story format" --color "D93F0B" 2>/dev/null; then
    echo -e "${GREEN}[✓] Created label: ralph-analyze${NC}"
  else
    echo -e "${YELLOW}[~] Label exists: ralph-analyze${NC}"
  fi

  echo ""

  # Create issue template
  echo "Setting up issue template..."
  echo ""

  TEMPLATE_DIR=".github/ISSUE_TEMPLATE"
  TEMPLATE_FILE="$TEMPLATE_DIR/user-story.yml"
  CONFIG_FILE="$TEMPLATE_DIR/config.yml"

  mkdir -p "$TEMPLATE_DIR"

  # Create user-story.yml
  cat > "$TEMPLATE_FILE" << 'TEMPLATE_EOF'
name: User Story
description: Create a user story for Ralph to implement
title: "[Story]: "
labels: ["ralph-story"]
body:
  - type: markdown
    attributes:
      value: |
        ## User Story for Ralph
        Fill out this form to create a user story that Ralph can pick up and implement autonomously.

        **Keep stories small!** Each story should be completable in one iteration (one context window).

  - type: dropdown
    id: priority
    attributes:
      label: Priority
      description: Lower number = higher priority. Ralph works on priority 1 first.
      options:
        - "1 - Critical"
        - "2 - High"
        - "3 - Medium"
        - "4 - Low"
        - "5 - Nice to have"
    validations:
      required: true

  - type: input
    id: user-role
    attributes:
      label: As a...
      description: Who is the user or role?
      placeholder: "user, developer, admin, etc."
    validations:
      required: true

  - type: input
    id: user-want
    attributes:
      label: I want...
      description: What feature or capability?
      placeholder: "to filter tasks by status"
    validations:
      required: true

  - type: input
    id: user-benefit
    attributes:
      label: So that...
      description: What benefit or value does this provide?
      placeholder: "I can focus on what needs attention"
    validations:
      required: true

  - type: textarea
    id: acceptance-criteria
    attributes:
      label: Acceptance Criteria
      description: |
        List each criterion on a new line. These will become checkboxes.
        Be specific and verifiable - avoid vague criteria like "works correctly".
        Note: "Build and validation passes without errors" is automatically added by Ralph.
      placeholder: |
        Filter dropdown shows options: All, Active, Completed
        Selecting a filter updates the list immediately
        Filter persists in URL params
    validations:
      required: true

  - type: textarea
    id: context
    attributes:
      label: Additional Context (Optional)
      description: Any technical notes, links to related issues, or helpful context for implementation.
      placeholder: "Reuse the existing FilterDropdown component from src/components/ui"
    validations:
      required: false

  - type: checkboxes
    id: ui-story
    attributes:
      label: Story Type
      description: Check if this story involves UI changes
      options:
        - label: This story changes the UI (requires browser verification)
          required: false
TEMPLATE_EOF

  echo -e "${GREEN}[✓] Created issue template: $TEMPLATE_FILE${NC}"

  # Create config.yml
  cat > "$CONFIG_FILE" << CONFIG_EOF
blank_issues_enabled: true
contact_links:
  - name: Rough Idea / Bug Report (for Ralph to analyze)
    url: ${REPO_URL}/issues/new?labels=ralph-analyze
    about: Create a rough issue that Ralph will analyze and convert to a proper user story
CONFIG_EOF

  echo -e "${GREEN}[✓] Created template config: $CONFIG_FILE${NC}"
  echo ""

  # Check for GitHub Project
  echo "Checking for GitHub Project..."
  echo ""

  # Get all projects and find one matching repo name
  PROJECTS_JSON=$(gh project list --owner "$REPO_OWNER" --format json 2>/dev/null || echo '{"projects":[]}')
  PROJECT_NUM=$(echo "$PROJECTS_JSON" | jq -r --arg name "$REPO_NAME" '.projects[] | select(.title | ascii_downcase == ($name | ascii_downcase)) | .number' 2>/dev/null | head -1)

  if [ -n "$PROJECT_NUM" ] && [ "$PROJECT_NUM" != "null" ]; then
    PROJECT_TITLE=$(echo "$PROJECTS_JSON" | jq -r --arg num "$PROJECT_NUM" '.projects[] | select(.number == ($num | tonumber)) | .title' 2>/dev/null)
    PROJECT_URL=$(echo "$PROJECTS_JSON" | jq -r --arg num "$PROJECT_NUM" '.projects[] | select(.number == ($num | tonumber)) | .url' 2>/dev/null)
    echo -e "${GREEN}[✓] GitHub Project found: $PROJECT_TITLE (#$PROJECT_NUM)${NC}"
    echo "    URL: $PROJECT_URL"

    # Check for Status field
    FIELDS_JSON=$(gh project field-list "$PROJECT_NUM" --owner "$REPO_OWNER" --format json 2>/dev/null || echo '{"fields":[]}')
    STATUS_FIELD=$(echo "$FIELDS_JSON" | jq -r '.fields[] | select(.name == "Status") | .name' 2>/dev/null)
    if [ -n "$STATUS_FIELD" ]; then
      echo -e "${GREEN}[✓] Status field configured${NC}"
      echo "    Ralph will update issue status (In progress → Done)"
    else
      echo -e "${YELLOW}[~] No Status field found - Ralph will skip project status updates${NC}"
    fi
  else
    echo -e "${YELLOW}[~] No matching GitHub Project found${NC}"
    echo "    Ralph will work without project board integration"
    echo "    To enable: Create a project named '$REPO_NAME' at:"
    echo "    https://github.com/$REPO_OWNER?tab=projects"
  fi

  echo ""

  # Show current issue status
  echo "Current issue status..."
  echo ""

  STORY_COUNT=$(gh issue list --label "ralph-story" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  ANALYZE_COUNT=$(gh issue list --label "ralph-analyze" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  IN_PROGRESS_COUNT=$(gh issue list --label "ralph-in-progress" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

  echo "  ralph-story:       $STORY_COUNT open issues (ready to implement)"
  echo "  ralph-analyze:     $ANALYZE_COUNT open issues (need refinement)"
  echo "  ralph-in-progress: $IN_PROGRESS_COUNT open issues (currently being worked on)"

  echo ""
  echo "==============================================================="
  echo "  Initialization Complete!"
  echo "==============================================================="
  echo ""
  echo "Next steps:"
  echo ""
  echo "  1. Commit and push the issue template:"
  echo "     git add .github/ISSUE_TEMPLATE/"
  echo "     git commit -m 'feat: add Ralph issue templates'"
  echo "     git push"
  echo ""
  echo "  2. Create issues using the template at:"
  echo "     ${REPO_URL}/issues/new/choose"
  echo ""
  echo "  3. Run Ralph:"
  echo "     ./ralph.sh --source github"
  echo ""
  echo "  Or run in watch mode:"
  echo "     ./ralph.sh --source github --watch"
  echo ""
}

# Parse arguments
TOOL="claude"  # Default to claude
SOURCE="prd"   # Default to prd.json
MAX_ITERATIONS=10
WATCH_MODE=false
POLL_INTERVAL=60
INIT_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      exit 0
      ;;
    --init)
      INIT_MODE=true
      SOURCE="github"  # Init implies github mode
      shift
      ;;
    -t|--tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    -s|--source)
      SOURCE="$2"
      shift 2
      ;;
    --source=*)
      SOURCE="${1#*=}"
      shift
      ;;
    -w|--watch)
      WATCH_MODE=true
      shift
      ;;
    -i|--interval)
      POLL_INTERVAL="$2"
      shift 2
      ;;
    --interval=*)
      POLL_INTERVAL="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      else
        echo "Error: Unknown option '$1'"
        echo "Run './ralph.sh --help' for usage information."
        exit 1
      fi
      shift
      ;;
  esac
done

# Handle init mode first
if [[ "$INIT_MODE" == true ]]; then
  run_init
  exit 0
fi

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

# Validate source choice
if [[ "$SOURCE" != "prd" && "$SOURCE" != "github" ]]; then
  echo "Error: Invalid source '$SOURCE'. Must be 'prd' or 'github'."
  exit 1
fi

# Validate poll interval
if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid interval '$POLL_INTERVAL'. Must be a number (seconds)."
  exit 1
fi

# Watch mode only makes sense with github source
if [[ "$WATCH_MODE" == true && "$SOURCE" != "github" ]]; then
  echo "Error: Watch mode (--watch) only works with --source github"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Select prompt file based on source
if [[ "$SOURCE" == "github" ]]; then
  PROMPT_FILE="$SCRIPT_DIR/prompt-github.md"

  # Check if gh CLI is available
  if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is required for --source github"
    echo "Install it with: brew install gh"
    exit 1
  fi

  # Check if gh is authenticated
  if ! gh auth status &> /dev/null; then
    echo "Error: GitHub CLI is not authenticated"
    echo "Run: gh auth login"
    exit 1
  fi
else
  PROMPT_FILE="$SCRIPT_DIR/prompt-claude.md"

  # Archive previous run if branch changed (only for prd mode)
  if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
    CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
    LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

    if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
      # Archive the previous run
      DATE=$(date +%Y-%m-%d)
      # Strip "ralph/" prefix from branch name for folder
      FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
      ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

      echo "Archiving previous run: $LAST_BRANCH"
      mkdir -p "$ARCHIVE_FOLDER"
      [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
      [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
      echo "   Archived to: $ARCHIVE_FOLDER"

      # Reset progress file for new run
      echo "# Ralph Progress Log" > "$PROGRESS_FILE"
      echo "Started: $(date)" >> "$PROGRESS_FILE"
      echo "---" >> "$PROGRESS_FILE"
    fi
  fi

  # Track current branch (only for prd mode)
  if [ -f "$PRD_FILE" ]; then
    CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
    if [ -n "$CURRENT_BRANCH" ]; then
      echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
    fi
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Generate unique worker ID for this Ralph instance
WORKER_ID="ralph-$(hostname -s 2>/dev/null || echo "local")-$$-$(date +%s)"

# Function to check if there are available issues (github mode only)
check_for_issues() {
  # Check for ralph-analyze issues first
  ANALYZE_COUNT=$(gh issue list --label "ralph-analyze" --state open --json number 2>/dev/null | jq '[.[] | select(.labels // [] | map(.name // "") | index("ralph-in-progress") | not)] | length' 2>/dev/null || echo "0")
  if [[ "$ANALYZE_COUNT" -gt 0 ]]; then
    return 0
  fi

  # Then check for ralph-story issues
  STORY_COUNT=$(gh issue list --label "ralph-story" --state open --json number,labels 2>/dev/null | jq '[.[] | select(.labels | map(.name) | index("ralph-in-progress") | not)] | length' 2>/dev/null || echo "0")
  if [[ "$STORY_COUNT" -gt 0 ]]; then
    return 0
  fi

  return 1
}

# Function to claim an issue with verification (prevents race conditions)
# Returns 0 if claim successful, 1 if failed (another worker claimed it)
claim_issue() {
  local ISSUE_NUM=$1
  local CLAIM_MARKER="<!-- ralph-claim:$WORKER_ID -->"

  echo "   Attempting to claim issue #$ISSUE_NUM..."

  # Step 1: Add the ralph-in-progress label
  if ! gh issue edit "$ISSUE_NUM" --add-label "ralph-in-progress" 2>/dev/null; then
    echo -e "   ${RED}Failed to add label to issue #$ISSUE_NUM${NC}"
    return 1
  fi

  # Step 2: Add a claim comment with our unique worker ID
  gh issue comment "$ISSUE_NUM" --body "🤖 **Claimed by Ralph worker**
$CLAIM_MARKER
Worker ID: \`$WORKER_ID\`
Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" 2>/dev/null || true

  # Step 3: Wait with random jitter (3-7 seconds) to allow other workers to also claim
  local JITTER=$((RANDOM % 5 + 3))
  echo "   Waiting ${JITTER}s to verify exclusive claim..."
  sleep $JITTER

  # Step 4: Fetch all comments and find claim comments from the last 60 seconds
  local COMMENTS=$(gh issue view "$ISSUE_NUM" --json comments --jq '.comments[-10:]' 2>/dev/null)

  # Find all ralph-claim comments
  local CLAIM_COMMENTS=$(echo "$COMMENTS" | jq -r '[.[] | select(.body | contains("ralph-claim:"))] | sort_by(.createdAt)' 2>/dev/null)
  local CLAIM_COUNT=$(echo "$CLAIM_COMMENTS" | jq 'length' 2>/dev/null || echo "0")

  if [[ "$CLAIM_COUNT" -eq 0 ]]; then
    # No claim comments found (shouldn't happen, but handle it)
    echo -e "   ${YELLOW}Warning: Could not verify claim, proceeding anyway${NC}"
    return 0
  fi

  # Check if the FIRST (oldest) claim comment is ours
  local FIRST_CLAIM=$(echo "$CLAIM_COMMENTS" | jq -r '.[0].body' 2>/dev/null)

  if echo "$FIRST_CLAIM" | grep -q "$WORKER_ID"; then
    echo -e "   ${GREEN}Successfully claimed issue #$ISSUE_NUM${NC}"
    return 0
  else
    # Another worker claimed first - back off
    echo -e "   ${YELLOW}Another worker claimed issue #$ISSUE_NUM first, backing off...${NC}"

    # Remove our label (the other worker's label stays)
    # Note: We can't selectively remove, so we add a release comment instead
    gh issue comment "$ISSUE_NUM" --body "🤖 **Released by Ralph worker**
$CLAIM_MARKER
Worker \`$WORKER_ID\` backing off - another worker claimed first." 2>/dev/null || true

    return 1
  fi
}

# Function to release a claimed issue (in case of errors)
release_issue() {
  local ISSUE_NUM=$1
  local CLAIM_MARKER="<!-- ralph-claim:$WORKER_ID -->"

  gh issue edit "$ISSUE_NUM" --remove-label "ralph-in-progress" 2>/dev/null || true
  gh issue comment "$ISSUE_NUM" --body "🤖 **Released by Ralph worker**
$CLAIM_MARKER
Worker \`$WORKER_ID\` released this issue due to an error." 2>/dev/null || true
}

# Function to run one batch of iterations
run_batch() {
  local batch_num=$1

  for i in $(seq 1 $MAX_ITERATIONS); do
    echo ""
    echo "==============================================================="
    if [[ "$WATCH_MODE" == true ]]; then
      echo "  Ralph Batch $batch_num, Iteration $i of $MAX_ITERATIONS ($TOOL, $SOURCE)"
    else
      echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL, $SOURCE)"
    fi
    echo "==============================================================="

    # For GitHub mode, find an issue and claim it with verification
    CLAIMED_ISSUE=""
    CLAIMED_ISSUE_TYPE=""

    if [[ "$SOURCE" == "github" ]]; then
      echo ""
      echo "Checking for available issues..."

      # Try to claim an issue (may need multiple attempts if racing with other workers)
      MAX_CLAIM_ATTEMPTS=5
      CLAIM_ATTEMPT=0

      while [[ -z "$CLAIMED_ISSUE" && $CLAIM_ATTEMPT -lt $MAX_CLAIM_ATTEMPTS ]]; do
        CLAIM_ATTEMPT=$((CLAIM_ATTEMPT + 1))

        # Check for ralph-analyze issues first (they take priority)
        ANALYZE_ISSUES=$(gh issue list --label "ralph-analyze" --state open --json number,title,labels 2>/dev/null | jq -r '[.[] | select(.labels | map(.name) | index("ralph-in-progress") | not)]' 2>/dev/null)
        ANALYZE_COUNT=$(echo "$ANALYZE_ISSUES" | jq 'length' 2>/dev/null || echo "0")

        if [[ "$ANALYZE_COUNT" -gt 0 ]]; then
          # Try each analyze issue until we successfully claim one
          for idx in $(seq 0 $((ANALYZE_COUNT - 1))); do
            PICKED_NUM=$(echo "$ANALYZE_ISSUES" | jq -r ".[$idx].number")
            PICKED_TITLE=$(echo "$ANALYZE_ISSUES" | jq -r ".[$idx].title")

            echo ""
            echo -e "${YELLOW}>> Attempting issue #$PICKED_NUM for ANALYSIS${NC}"
            echo "   Title: $PICKED_TITLE"
            echo "   Reason: ralph-analyze issues are processed first (needs refinement)"

            if claim_issue "$PICKED_NUM"; then
              CLAIMED_ISSUE="$PICKED_NUM"
              CLAIMED_ISSUE_TYPE="analyze"
              break
            fi
          done
        fi

        # If no analyze issues claimed, try story issues
        if [[ -z "$CLAIMED_ISSUE" ]]; then
          STORY_ISSUES=$(gh issue list --label "ralph-story" --state open --json number,title,body,labels 2>/dev/null | jq -r '[.[] | select(.labels | map(.name) | index("ralph-in-progress") | not)]' 2>/dev/null)
          STORY_COUNT=$(echo "$STORY_ISSUES" | jq 'length' 2>/dev/null || echo "0")

          if [[ "$STORY_COUNT" -eq 0 && "$ANALYZE_COUNT" -eq 0 ]]; then
            echo ""
            echo "No available issues found. All done!"
            return 0
          fi

          if [[ "$STORY_COUNT" -gt 0 ]]; then
            # Parse priorities and sort all issues
            ISSUES_WITH_PRIORITY=$(echo "$STORY_ISSUES" | jq -r '
              [.[] | {
                number: .number,
                title: .title,
                priority: (
                  if (.body | test("1 - Critical"; "i")) then 1
                  elif (.body | test("2 - High"; "i")) then 2
                  elif (.body | test("3 - Medium"; "i")) then 3
                  elif (.body | test("4 - Low"; "i")) then 4
                  elif (.body | test("5 - Nice"; "i")) then 5
                  else 99
                  end
                )
              }] | sort_by(.priority)
            ' 2>/dev/null)

            SORTED_COUNT=$(echo "$ISSUES_WITH_PRIORITY" | jq 'length' 2>/dev/null || echo "0")

            # Try each issue in priority order until we successfully claim one
            for idx in $(seq 0 $((SORTED_COUNT - 1))); do
              PICKED_NUM=$(echo "$ISSUES_WITH_PRIORITY" | jq -r ".[$idx].number")
              PICKED_TITLE=$(echo "$ISSUES_WITH_PRIORITY" | jq -r ".[$idx].title")
              PICKED_PRIORITY=$(echo "$ISSUES_WITH_PRIORITY" | jq -r ".[$idx].priority")

              # Map priority number to name
              case $PICKED_PRIORITY in
                1) PRIORITY_NAME="Critical" ;;
                2) PRIORITY_NAME="High" ;;
                3) PRIORITY_NAME="Medium" ;;
                4) PRIORITY_NAME="Low" ;;
                5) PRIORITY_NAME="Nice to have" ;;
                *) PRIORITY_NAME="Unknown" ;;
              esac

              echo ""
              echo -e "${GREEN}>> Attempting issue #$PICKED_NUM for IMPLEMENTATION${NC}"
              echo "   Title: $PICKED_TITLE"
              echo "   Priority: $PICKED_PRIORITY - $PRIORITY_NAME"

              if claim_issue "$PICKED_NUM"; then
                CLAIMED_ISSUE="$PICKED_NUM"
                CLAIMED_ISSUE_TYPE="story"
                break
              fi
            done
          fi
        fi

        # If still no claim after trying all issues, wait and retry
        if [[ -z "$CLAIMED_ISSUE" && $CLAIM_ATTEMPT -lt $MAX_CLAIM_ATTEMPTS ]]; then
          echo ""
          echo -e "${YELLOW}Could not claim any issue. Waiting 10s before retry ($CLAIM_ATTEMPT/$MAX_CLAIM_ATTEMPTS)...${NC}"
          sleep 10
        fi
      done

      # Check if we got an issue
      if [[ -z "$CLAIMED_ISSUE" ]]; then
        echo ""
        echo -e "${RED}Could not claim any issue after $MAX_CLAIM_ATTEMPTS attempts.${NC}"
        echo "All issues may be claimed by other workers. Waiting for next iteration..."
        sleep 30
        continue
      fi

      echo ""
      echo -e "${GREEN}===============================================================${NC}"
      echo -e "${GREEN}  CLAIMED: Issue #$CLAIMED_ISSUE (Worker: $WORKER_ID)${NC}"
      echo -e "${GREEN}===============================================================${NC}"
      echo ""
    fi

    # Run the selected tool with the appropriate prompt
    # Retry logic for transient errors
    RETRY_COUNT=0
    MAX_RETRIES=5

    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
      # Use a temp file to avoid buffering issues with tee
      TEMP_OUTPUT=$(mktemp)
      TEMP_PROMPT=$(mktemp)

      # Copy prompt to temp file, prepending claimed issue info for GitHub mode
      if [[ "$SOURCE" == "github" && -n "$CLAIMED_ISSUE" ]]; then
        cat > "$TEMP_PROMPT" << CLAIM_EOF
## Pre-Claimed Issue

**IMPORTANT:** Issue #$CLAIMED_ISSUE has already been claimed by this Ralph worker.

- Worker ID: \`$WORKER_ID\`
- Issue Type: $CLAIMED_ISSUE_TYPE
- The \`ralph-in-progress\` label has already been added
- A claim comment has already been posted

**Skip the "Claiming an Issue" step** - go directly to implementation/analysis.

---

CLAIM_EOF
        cat "$PROMPT_FILE" >> "$TEMP_PROMPT"
      else
        cp "$PROMPT_FILE" "$TEMP_PROMPT"
      fi

      # Small delay to ensure any previous processes have cleaned up
      sleep 1

      if [[ "$TOOL" == "amp" ]]; then
        cat "$TEMP_PROMPT" | amp --dangerously-allow-all 2>&1 | tee "$TEMP_OUTPUT" || true
      else
        # Claude Code: use --dangerously-skip-permissions for autonomous operation
        # --no-session-persistence avoids session conflicts between iterations
        # Use a fresh subshell to ensure clean state
        (cat "$TEMP_PROMPT" | claude --dangerously-skip-permissions --no-session-persistence --print 2>&1) | tee "$TEMP_OUTPUT" || true
      fi

      OUTPUT=$(cat "$TEMP_OUTPUT")
      rm -f "$TEMP_OUTPUT" "$TEMP_PROMPT"

      # Check for empty output (no content at all)
      if [[ -z "$OUTPUT" ]]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
          WAIT_TIME=$((RETRY_COUNT * 10))
          echo ""
          echo -e "${YELLOW}[!] Claude returned empty output. Waiting ${WAIT_TIME}s before retry ($RETRY_COUNT/$MAX_RETRIES)...${NC}"
          sleep $WAIT_TIME
          continue
        else
          echo ""
          echo -e "${RED}[x] Claude returned empty output after $MAX_RETRIES attempts.${NC}"
          if [[ "$SOURCE" == "github" ]] && ! check_for_issues; then
            echo "No available issues found. All done!"
            return 0
          fi
          echo "Skipping this iteration..."
          break
        fi
      fi

      # FIRST: Check if work was completed successfully (before checking for errors)
      # Look for indicators that the issue was FULLY completed (CI passed AND issue closed)
      # Just pushing is NOT enough - CI must pass and issue must be closed
      WORK_COMPLETED=false

      # Check for CI pass indicators
      CI_PASSED=false
      if echo "$OUTPUT" | grep -qiE "CI status:.*Passed|CI status:.*✅|CI.*passed|workflow.*completed.*success|run.*completed.*success"; then
        CI_PASSED=true
      fi

      # Check for issue closed indicators
      ISSUE_CLOSED=false
      if echo "$OUTPUT" | grep -qiE "issue.*closed|closed.*issue|gh issue close|Closing issue"; then
        ISSUE_CLOSED=true
      fi

      # Work is only complete if BOTH CI passed AND issue was closed
      if [[ "$CI_PASSED" == true && "$ISSUE_CLOSED" == true ]]; then
        WORK_COMPLETED=true
        echo ""
        echo -e "${GREEN}[✓] Work completed successfully (CI passed, issue closed).${NC}"
      elif [[ "$CI_PASSED" == true ]]; then
        echo ""
        echo -e "${YELLOW}[~] CI passed but issue not yet closed.${NC}"
      elif echo "$OUTPUT" | grep -qiE "waiting for CI|gh run watch|CI run.*complete"; then
        echo ""
        echo -e "${BLUE}[...] CI verification in progress.${NC}"
      fi

      # Check for "No messages returned" error (transient Claude Code issue)
      if echo "$OUTPUT" | grep -q "Error: No messages returned"; then
        if [[ "$WORK_COMPLETED" == true ]]; then
          echo -e "${YELLOW}[~] 'No messages' error occurred but work was already completed. Continuing...${NC}"
          break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
          WAIT_TIME=$((RETRY_COUNT * 15))
          echo ""
          echo -e "${YELLOW}[!] Claude returned 'No messages' error. This is a known transient issue.${NC}"
          echo "    Waiting ${WAIT_TIME}s before retry ($RETRY_COUNT/$MAX_RETRIES)..."
          sleep $WAIT_TIME
          continue
        else
          echo ""
          echo -e "${RED}[x] 'No messages returned' error persisted after $MAX_RETRIES attempts.${NC}"
          echo "    This is a Claude Code transient error, not a Ralph issue."
          if [[ "$SOURCE" == "github" ]] && ! check_for_issues; then
            echo "No available issues found. All done!"
            return 0
          fi
          echo "Continuing to next iteration..."
          break
        fi
      fi

      # Check for connection/timeout errors (only real errors, not mentions in text)
      # Look for actual error patterns, not just any mention of these words
      if echo "$OUTPUT" | grep -qiE "ECONNRESET|ETIMEDOUT|ENOTFOUND|socket hang up|connection refused|network error|request timed out"; then
        if [[ "$WORK_COMPLETED" == true ]]; then
          echo -e "${YELLOW}[~] Network error occurred but work was already completed. Continuing...${NC}"
          break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
          WAIT_TIME=$((RETRY_COUNT * 20))
          echo ""
          echo -e "${YELLOW}[!] Network/connection error detected. Waiting ${WAIT_TIME}s before retry ($RETRY_COUNT/$MAX_RETRIES)...${NC}"
          sleep $WAIT_TIME
          continue
        else
          echo ""
          echo -e "${RED}[x] Network errors persisted after $MAX_RETRIES attempts. Skipping iteration...${NC}"
          break
        fi
      fi

      # Check for other Claude errors
      if echo "$OUTPUT" | grep -q "^Error:"; then
        if [[ "$WORK_COMPLETED" == true ]]; then
          echo -e "${YELLOW}[~] Error occurred but work was already completed. Continuing...${NC}"
          break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        ERROR_MSG=$(echo "$OUTPUT" | grep "^Error:" | head -1)
        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
          WAIT_TIME=$((RETRY_COUNT * 10))
          echo ""
          echo -e "${YELLOW}[!] Claude error: $ERROR_MSG${NC}"
          echo "    Waiting ${WAIT_TIME}s before retry ($RETRY_COUNT/$MAX_RETRIES)..."
          sleep $WAIT_TIME
          continue
        else
          echo ""
          echo -e "${RED}[x] Claude error persisted after $MAX_RETRIES attempts: $ERROR_MSG${NC}"
          echo "Skipping iteration..."
          break
        fi
      fi

      # Success - exit retry loop
      break
    done

    # Check for completion signal
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
      echo ""
      echo "Ralph completed all tasks!"
      return 0  # Signal completion
    fi

    echo "Iteration $i complete. Continuing..."
    sleep 2
  done

  return 1  # Max iterations reached without completion
}

# Main execution
if [[ "$WATCH_MODE" == true ]]; then
  echo "Starting Ralph in WATCH MODE"
  echo "  Tool: $TOOL"
  echo "  Source: $SOURCE"
  echo "  Max iterations per batch: $MAX_ITERATIONS"
  echo "  Poll interval: ${POLL_INTERVAL}s"
  echo ""
  echo "Press Ctrl+C to stop"
  echo ""

  BATCH_NUM=0

  # Handle Ctrl+C gracefully
  trap 'echo ""; echo "Ralph stopped by user."; exit 0' INT

  while true; do
    # Check if there are issues to work on
    if check_for_issues; then
      BATCH_NUM=$((BATCH_NUM + 1))
      echo ""
      echo "==============================================================="
      echo "  Issues found! Starting batch $BATCH_NUM"
      echo "==============================================================="

      run_batch $BATCH_NUM
      BATCH_RESULT=$?

      if [[ $BATCH_RESULT -eq 0 ]]; then
        echo ""
        echo "Batch $BATCH_NUM complete. Waiting ${POLL_INTERVAL}s before checking for new issues..."
      else
        echo ""
        echo "Batch $BATCH_NUM reached max iterations. Waiting ${POLL_INTERVAL}s before continuing..."
      fi
    else
      echo "[$(date '+%H:%M:%S')] No issues found. Waiting ${POLL_INTERVAL}s before checking again..."
    fi

    sleep "$POLL_INTERVAL"
  done
else
  # Normal mode (non-watch)
  echo "Starting Ralph - Tool: $TOOL - Source: $SOURCE - Max iterations: $MAX_ITERATIONS"

  run_batch 1
  BATCH_RESULT=$?

  if [[ $BATCH_RESULT -eq 0 ]]; then
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  else
    echo ""
    echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
    echo "Check $PROGRESS_FILE for status."
    exit 1
  fi
fi
