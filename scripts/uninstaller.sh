#!/bin/bash

# Claude Code OAuth Uninstaller Script
# Author: Guillaume Raille <guillaume.raille@gmail.com>

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${CYAN}ℹ ${WHITE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ ${WHITE}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ ${WHITE}$1${NC}"
}

log_error() {
    echo -e "${RED}✗ ${WHITE}$1${NC}"
}

log_step() {
    echo -e "${MAGENTA}${BOLD}▶ $1${NC}"
}

# Helper functions for reading input when piped from curl
read_from_tty() {
    local prompt="$1"
    local input
    if [ -t 0 ]; then
        # Running interactively
        read -p "$prompt" input
    else
        # Running from pipe, use /dev/tty
        printf "%s" "$prompt" >/dev/tty
        read input </dev/tty
    fi
    echo "$input"
}

# Summary tracking
declare -A REMOVAL_SUMMARY
REMOVAL_SUMMARY["workflows_removed"]=false
REMOVAL_SUMMARY["workflows_status"]=""
REMOVAL_SUMMARY["secrets_removed"]=()
REMOVAL_SUMMARY["secrets_failed"]=()
REMOVAL_SUMMARY["pat_removed"]=false
REMOVAL_SUMMARY["pat_status"]=""

# ASCII Art Header
show_header() {
    clear
    echo -e "${RED}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║                                                                          ║
║                  🗑️  @claude OAuth Uninstaller 🗑️                        ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

 ██╗   ██╗███╗   ██╗██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     
 ██║   ██║████╗  ██║██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     
 ██║   ██║██╔██╗ ██║██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     
 ██║   ██║██║╚██╗██║██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     
 ╚██████╔╝██║ ╚████║██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
  ╚═════╝ ╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝

 by @grll

EOF
    echo -e "${NC}"
}

# Parse command line arguments
REPO_ARG=""
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO_ARG="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--repo owner/repo-name] [--force]"
            exit 1
            ;;
    esac
done

# Show header
show_header

# Warning message
echo -e "${RED}${BOLD}⚠️  WARNING: This will remove Claude Code OAuth components ⚠️${NC}"
echo
echo -e "${BOLD}This script will attempt to remove:${NC}"
echo "  • GitHub workflow files (claude_code_login.yml, claude_code.yml)"
echo "  • GitHub secrets (CLAUDE_ACCESS_TOKEN, CLAUDE_REFRESH_TOKEN, CLAUDE_EXPIRES_AT)"
echo "  • GitHub secret SECRETS_ADMIN_PAT (if confirmed)"
echo
echo -e "${YELLOW}Note: This will NOT remove the Anthropic GitHub App installation.${NC}"
echo -e "${YELLOW}To remove the app, visit: https://github.com/settings/installations${NC}"
echo

if [ "$FORCE" != true ]; then
    echo -e "${BOLD}Do you want to continue? (y/N):${NC} "
    CONFIRM=$(read_from_tty "")
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi
fi

# Step 1: Check gh CLI installation
log_step "STEP 1: Checking GitHub CLI Installation"
if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) is not installed or not in PATH"
    echo
    log_info "Please install GitHub CLI first to continue:"
    echo "  • Visit: https://cli.github.com/"
    exit 1
fi
log_success "GitHub CLI is installed"

# Check jq installation
if ! command -v jq &> /dev/null; then
    log_error "jq is not installed or not in PATH"
    echo
    log_info "Please install jq first:"
    echo "  • Visit: https://jqlang.github.io/jq/"
    exit 1
fi
log_success "jq is installed"

# Step 2: Get GitHub username
log_step "STEP 2: Getting GitHub Username"
GITHUB_USERNAME=$(gh api user | jq -r '.login' 2>/dev/null)
if [ $? -ne 0 ] || [ "$GITHUB_USERNAME" = "null" ] || [ -z "$GITHUB_USERNAME" ]; then
    log_error "Failed to get GitHub username. Please ensure you're logged in to GitHub CLI"
    echo
    log_info "Run: gh auth login"
    exit 1
fi
log_success "Authenticated as: $GITHUB_USERNAME"

# Step 3: Repository detection/selection
log_step "STEP 3: Repository Detection"
if [ -n "$REPO_ARG" ]; then
    REPO_NAME="$REPO_ARG"
    log_info "Using repository from --repo flag: $REPO_NAME"
else
    # Try to get current repo
    set +e
    CURRENT_REPO=$(gh repo view --json name -q ".name" 2>/dev/null)
    GH_REPO_EXIT_CODE=$?
    set -e
    
    if [ $GH_REPO_EXIT_CODE -ne 0 ]; then
        log_warning "Could not detect current repository"
        echo
        echo -e "${BOLD}Please enter repository name (format: owner/repo-name):${NC}"
        echo -e "${CYAN}Example: $GITHUB_USERNAME/claude-code-login${NC}"
        REPO_NAME=$(read_from_tty "Repository: ")
    elif [ -n "$CURRENT_REPO" ]; then
        set +e
        REPO_OWNER=$(gh repo view --json owner -q ".owner.login" 2>/dev/null)
        set -e
        REPO_NAME="${REPO_OWNER}/${CURRENT_REPO}"
        log_success "Found current repository: $REPO_NAME"
    else
        log_warning "No current repository found"
        echo
        echo -e "${BOLD}Please enter repository name (format: owner/repo-name):${NC}"
        echo -e "${CYAN}Example: $GITHUB_USERNAME/claude-code-login${NC}"
        REPO_NAME=$(read_from_tty "Repository: ")
    fi
fi

# Verify repository exists
log_info "Verifying repository access: $REPO_NAME"
if ! gh repo view "$REPO_NAME" &>/dev/null; then
    log_error "Cannot access repository: $REPO_NAME"
    echo
    log_info "Please ensure:"
    echo "  • The repository exists"
    echo "  • You have access to the repository"
    exit 1
fi
log_success "Repository verified: $REPO_NAME"

# Step 4: Check for existing workflows
log_step "STEP 4: Checking for Claude Code Workflows"
WORKFLOWS_EXIST=false
WORKFLOW_FILES=()

# Check if workflows exist
if [ -f ".github/workflows/claude_code_login.yml" ]; then
    WORKFLOWS_EXIST=true
    WORKFLOW_FILES+=(".github/workflows/claude_code_login.yml")
    log_info "Found: claude_code_login.yml"
fi

if [ -f ".github/workflows/claude_code.yml" ]; then
    WORKFLOWS_EXIST=true
    WORKFLOW_FILES+=(".github/workflows/claude_code.yml")
    log_info "Found: claude_code.yml"
fi

if [ "$WORKFLOWS_EXIST" = false ]; then
    log_warning "No Claude Code workflow files found in current directory"
    REMOVAL_SUMMARY["workflows_status"]="No workflow files found to remove"
else
    # Step 5: Git repository setup for workflow removal
    log_step "STEP 5: Removing Workflow Files"
    
    # Save current branch and any uncommitted changes
    ORIGINAL_BRANCH=$(git branch --show-current)
    if [ -z "$ORIGINAL_BRANCH" ]; then
        ORIGINAL_BRANCH=$(git rev-parse HEAD 2>/dev/null || echo "main")
        IS_DETACHED=true
    else
        IS_DETACHED=false
    fi
    log_info "Current branch/commit: $ORIGINAL_BRANCH"
    
    # Stash any existing changes
    log_info "Stashing existing changes..."
    set +e
    STASH_RESULT=$(git stash push -u -m "Pre-Claude-OAuth-uninstall stash" 2>&1)
    STASH_EXIT_CODE=$?
    set -e
    
    # Check stash result
    set +e
    echo "$STASH_RESULT" | grep -q "No local changes to save"
    NO_CHANGES=$?
    set -e
    
    if [ $NO_CHANGES -eq 0 ]; then
        STASH_CREATED=false
        log_info "No existing changes to stash"
    elif [ $STASH_EXIT_CODE -eq 0 ]; then
        STASH_CREATED=true
        log_success "Existing changes stashed"
    else
        STASH_CREATED=false
        log_warning "Failed to stash changes: $STASH_RESULT"
    fi
    
    # Check if main branch exists
    if git show-ref --verify --quiet refs/heads/main; then
        MAIN_BRANCH="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        MAIN_BRANCH="master"
    else
        log_error "No main/master branch found"
        REMOVAL_SUMMARY["workflows_status"]="Failed: No main/master branch"
        WORKFLOWS_EXIST=false
    fi
    
    if [ "$WORKFLOWS_EXIST" = true ]; then
        # Switch to main branch
        if [ "$ORIGINAL_BRANCH" != "$MAIN_BRANCH" ]; then
            log_info "Switching to $MAIN_BRANCH branch..."
            git checkout "$MAIN_BRANCH"
        fi
        
        # Remove workflow files
        log_info "Removing workflow files..."
        for workflow in "${WORKFLOW_FILES[@]}"; do
            rm -f "$workflow"
            log_success "Removed: $workflow"
        done
        
        # Check if .github/workflows is empty and remove if so
        if [ -d ".github/workflows" ] && [ -z "$(ls -A .github/workflows)" ]; then
            rmdir .github/workflows
            log_info "Removed empty workflows directory"
        fi
        
        # Check if .github is empty and remove if so
        if [ -d ".github" ] && [ -z "$(ls -A .github)" ]; then
            rmdir .github
            log_info "Removed empty .github directory"
        fi
        
        # Ask for user consent before committing
        echo
        echo -e "${BOLD}${YELLOW}⚠️  Permission Required${NC}"
        echo -e "${BOLD}The uninstaller needs to commit and push the removal to the $MAIN_BRANCH branch.${NC}"
        echo
        echo -e "${BOLD}Commit and push workflow removal? (y/N):${NC} "
        CONSENT=$(read_from_tty "")
        
        if [[ "$CONSENT" =~ ^[Yy]$ ]]; then
            # Add removed files to git
            for workflow in "${WORKFLOW_FILES[@]}"; do
                git add "$workflow"
            done
            
            # Also add directories if they were removed
            if [ ! -d ".github/workflows" ]; then
                git add -u .github/workflows || true
            fi
            if [ ! -d ".github" ]; then
                git add -u .github || true
            fi
            
            # Commit the changes
            log_info "Committing workflow removal..."
            git commit -m "Remove Claude Code OAuth workflows

- Removed claude_code_login.yml
- Removed claude_code.yml

🗑️ Removed with Claude OAuth Uninstaller

Co-authored-by: grll <noreply@github.com>"
            
            log_success "Workflow removal committed"
            REMOVAL_SUMMARY["workflows_removed"]=true
            REMOVAL_SUMMARY["workflows_status"]="Successfully removed and committed"
            
            # Push to remote
            log_info "Pushing to remote repository..."
            if git push origin "$MAIN_BRANCH"; then
                log_success "Changes pushed to remote repository"
            else
                log_warning "Failed to push. You may need to push manually:"
                echo "  git push origin $MAIN_BRANCH"
                REMOVAL_SUMMARY["workflows_status"]="Removed locally but failed to push"
            fi
        else
            log_warning "Workflow files removed locally but not committed"
            REMOVAL_SUMMARY["workflows_status"]="Removed locally but not committed"
            
            # Restore the files since user didn't consent
            git checkout -- "${WORKFLOW_FILES[@]}"
            log_info "Restored workflow files since commit was declined"
            REMOVAL_SUMMARY["workflows_removed"]=false
            REMOVAL_SUMMARY["workflows_status"]="Removal cancelled by user"
        fi
        
        # Return to original branch
        if [ "$ORIGINAL_BRANCH" != "$MAIN_BRANCH" ]; then
            log_info "Returning to original branch/commit: $ORIGINAL_BRANCH"
            if [ "$IS_DETACHED" = true ]; then
                git checkout "$ORIGINAL_BRANCH" 2>/dev/null || log_warning "Could not return to original commit"
            else
                git checkout "$ORIGINAL_BRANCH"
            fi
        fi
        
        # Pop stashed changes if we created a stash
        if [ "$STASH_CREATED" = true ]; then
            log_info "Restoring stashed changes..."
            if git stash pop; then
                log_success "Stashed changes restored"
            else
                log_warning "Failed to restore stashed changes. Check 'git stash list'"
            fi
        fi
    fi
fi

# Step 6: Remove GitHub Secrets
log_step "STEP 6: Removing GitHub Secrets"

# Function to check if a secret exists
secret_exists() {
    local secret_name="$1"
    set +e
    gh secret list --repo "$REPO_NAME" | grep -q "^$secret_name"
    local result=$?
    set -e
    return $result
}

# Function to remove a secret
remove_secret() {
    local secret_name="$1"
    if secret_exists "$secret_name"; then
        log_info "Removing secret: $secret_name"
        if gh secret delete "$secret_name" --repo "$REPO_NAME" 2>/dev/null; then
            log_success "Removed: $secret_name"
            REMOVAL_SUMMARY["secrets_removed"]+=("$secret_name")
            return 0
        else
            log_error "Failed to remove: $secret_name"
            REMOVAL_SUMMARY["secrets_failed"]+=("$secret_name")
            return 1
        fi
    else
        log_info "Secret not found: $secret_name"
        return 0
    fi
}

# Remove Claude-related secrets first
CLAUDE_SECRETS=("CLAUDE_ACCESS_TOKEN" "CLAUDE_REFRESH_TOKEN" "CLAUDE_EXPIRES_AT")
for secret in "${CLAUDE_SECRETS[@]}"; do
    remove_secret "$secret"
done

# Ask about SECRETS_ADMIN_PAT removal
if secret_exists "SECRETS_ADMIN_PAT"; then
    echo
    echo -e "${YELLOW}${BOLD}⚠️  SECRETS_ADMIN_PAT Detected${NC}"
    echo -e "${BOLD}This PAT might be used by other workflows in your repository.${NC}"
    echo -e "${BOLD}Remove SECRETS_ADMIN_PAT? (y/N):${NC} "
    REMOVE_PAT=$(read_from_tty "")
    
    if [[ "$REMOVE_PAT" =~ ^[Yy]$ ]]; then
        if remove_secret "SECRETS_ADMIN_PAT"; then
            REMOVAL_SUMMARY["pat_removed"]=true
            REMOVAL_SUMMARY["pat_status"]="Successfully removed"
        else
            REMOVAL_SUMMARY["pat_status"]="Failed to remove"
        fi
    else
        log_info "Keeping SECRETS_ADMIN_PAT"
        REMOVAL_SUMMARY["pat_status"]="Kept by user choice"
    fi
else
    log_info "SECRETS_ADMIN_PAT not found"
    REMOVAL_SUMMARY["pat_status"]="Not found"
fi

# Step 7: Summary
log_step "UNINSTALLATION SUMMARY"
echo
echo -e "${BOLD}Workflow Files:${NC}"
if [ "${REMOVAL_SUMMARY["workflows_removed"]}" = true ]; then
    echo -e "  ${GREEN}✓${NC} Status: ${REMOVAL_SUMMARY["workflows_status"]}"
else
    echo -e "  ${YELLOW}○${NC} Status: ${REMOVAL_SUMMARY["workflows_status"]}"
fi

echo
echo -e "${BOLD}GitHub Secrets:${NC}"
if [ ${#REMOVAL_SUMMARY["secrets_removed"][@]} -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} Removed:"
    for secret in "${REMOVAL_SUMMARY["secrets_removed"][@]}"; do
        echo "    • $secret"
    done
fi

if [ ${#REMOVAL_SUMMARY["secrets_failed"][@]} -gt 0 ]; then
    echo -e "  ${RED}✗${NC} Failed to remove:"
    for secret in "${REMOVAL_SUMMARY["secrets_failed"][@]}"; do
        echo "    • $secret"
    done
fi

echo -e "  ${YELLOW}○${NC} SECRETS_ADMIN_PAT: ${REMOVAL_SUMMARY["pat_status"]}"

echo
echo -e "${BOLD}Additional Notes:${NC}"
echo "  • The Anthropic GitHub App was NOT removed"
echo "  • To remove it, visit: https://github.com/settings/installations"
echo "  • Your repository and code remain intact"

echo
log_success "Uninstallation process complete"

# Final message
echo
if [ "${REMOVAL_SUMMARY["workflows_removed"]}" = true ] && [ ${#REMOVAL_SUMMARY["secrets_removed"][@]} -gt 0 ]; then
    echo -e "${GREEN}Claude Code OAuth has been successfully removed from $REPO_NAME${NC}"
else
    echo -e "${YELLOW}Claude Code OAuth was partially removed from $REPO_NAME${NC}"
    echo -e "${YELLOW}Some manual cleanup may be required${NC}"
fi