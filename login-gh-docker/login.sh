#!/bin/bash

set -euo pipefail

# Enable command tracing if VERBOSE is true
VERBOSE=true
if [ "$VERBOSE" = true ]; then
  echo "🔊 Verbose mode enabled"
  set -x
fi

echo "🔧 Starting authentication and token expiry check script..."

# ----------------------------
# Load .env variables
# ----------------------------
echo "📦 Loading environment variables..."
set -a
source .env
set +a

# Masked output
echo "✅ Loaded:"
echo "   - DOCKER_USERNAME: $DOCKER_USERNAME"
echo "   - GITHUB_TOKEN: ${GITHUB_TOKEN:0:4}********"
echo "   - GITHUB_TOKEN_EXPIRY: $GITHUB_TOKEN_EXPIRY"
echo "   - DOCKER_TOKEN: ${DOCKER_TOKEN:0:4}********"
echo "   - DOCKER_TOKEN_EXPIRY: $DOCKER_TOKEN_EXPIRY"

# ----------------------------
# Date utility
# ----------------------------
date_to_epoch() {
  date -j -f "%Y-%m-%d" "$1" "+%s" 2>/dev/null || date -d "$1" "+%s"
}

TODAY_EPOCH=$(date +%s)
TODAY_HUMAN=$(date -d "@$TODAY_EPOCH" 2>/dev/null || date -r "$TODAY_EPOCH")
echo "📆 Today's date: $TODAY_HUMAN"

# ----------------------------
# GitHub Expiry Check
# ----------------------------
GITHUB_EXPIRY_LOWER=$(echo "$GITHUB_TOKEN_EXPIRY" | tr '[:upper:]' '[:lower:]')
if [ "$GITHUB_EXPIRY_LOWER" = "ne" ]; then
  echo "🔓 GitHub token never expires"
else
  GITHUB_EXPIRY_EPOCH=$(date_to_epoch "$GITHUB_TOKEN_EXPIRY")
  GITHUB_DAYS_LEFT=$(( (GITHUB_EXPIRY_EPOCH - TODAY_EPOCH) / 86400 ))
  echo "🔍 GitHub token expires in $GITHUB_DAYS_LEFT day(s)"

  if [ "$GITHUB_DAYS_LEFT" -le 7 ]; then
    echo "⚠️  GitHub token is expiring soon!"
    read -p "🔁 Generate a new GitHub token and press Enter to continue..."
  fi
fi

# ----------------------------
# Docker Expiry Check
# ----------------------------
DOCKER_EXPIRY_LOWER=$(echo "$DOCKER_TOKEN_EXPIRY" | tr '[:upper:]' '[:lower:]')
if [ "$DOCKER_EXPIRY_LOWER" = "ne" ]; then
  echo "🔓 Docker token never expires"
else
  DOCKER_EXPIRY_EPOCH=$(date_to_epoch "$DOCKER_TOKEN_EXPIRY")
  DOCKER_DAYS_LEFT=$(( (DOCKER_EXPIRY_EPOCH - TODAY_EPOCH) / 86400 ))
  echo "🔍 Docker token expires in $DOCKER_DAYS_LEFT day(s)"

  if [ "$DOCKER_DAYS_LEFT" -le 7 ]; then
    echo "⚠️  Docker token is expiring soon!"
    read -p "🔁 Generate a new Docker token and press Enter to continue..."
  fi
fi

# ----------------------------
# GitHub Global Username Check
# ----------------------------
GIT_USER_NAME=$(git config --global user.name || true)

if [ -n "$GIT_USER_NAME" ]; then
  echo "✅ GitHub global user.name is: $GIT_USER_NAME"
else
  echo "⚠️  No GitHub global user.name set. Use: git config --global user.name \"Your Name\""
fi

# ----------------------------
# GitHub Login Check
# ----------------------------
if command -v gh >/dev/null 2>&1; then
  if gh auth status --show-token &>/dev/null; then
    GH_USER=$(gh auth status --show-token 2>/dev/null | grep -i "Logged in to github.com" | awk '{print $6}')
    echo "✅ Already logged in to GitHub as $GIT_USER_NAME"
  else
    echo "🔐 Logging in to GitHub CLI..."
    echo "$GITHUB_TOKEN" | gh auth login --with-token
    echo "✅ GitHub login complete"
  fi
else
  echo "⚠️  GitHub CLI (gh) not found. Skipping GitHub login."
fi

# ----------------------------
# Docker Login Check
# ----------------------------
#!/bin/bash

# Check if Docker config file exists
CONFIG="$HOME/.docker/config.json"
REGISTRY="https://index.docker.io/v1/"
DOCKER_CURRENT_USER=""

# Helper: extract username from credential store
get_user_from_credstore() {
  local helper
  helper=$(jq -r '.credsStore' "$CONFIG" 2>/dev/null)
  if [ -n "$helper" ] && command -v "docker-credential-$helper" >/dev/null; then
    docker-credential-$helper list 2>/dev/null | jq -r --arg reg "$REGISTRY" '.[$reg]'
  fi
}

# Extract current user
if [ -f "$CONFIG" ]; then
  # Case 1: auth inline (no credsStore)
  AUTH=$(jq -r ".auths[\"$REGISTRY\"].auth" "$CONFIG" 2>/dev/null)
  if [ -n "$AUTH" ] && [ "$AUTH" != "null" ]; then
    DOCKER_CURRENT_USER=$(echo "$AUTH" | base64 --decode | cut -d: -f1)
  else
    # Case 2: using credsStore (e.g., desktop)
    DOCKER_CURRENT_USER=$(get_user_from_credstore)
  fi
fi

# Compare and log in if needed
if [ "$DOCKER_CURRENT_USER" = "$DOCKER_USERNAME" ]; then
  echo "✅ Already logged in to Docker Hub as $DOCKER_CURRENT_USER"
else
  echo "🔐 Logging in to Docker Hub as $DOCKER_USERNAME..."
  echo "$DOCKER_TOKEN" | docker login --username "$DOCKER_USERNAME" --password-stdin
  echo "✅ Docker login complete"
fi

# ----------------------------
# Done
# ----------------------------
echo "🎉 All authentication steps completed successfully!"