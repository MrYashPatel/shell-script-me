#!/bin/bash

echo "Please enter the full or relative path to your Dockerfile:"
read -r DOCKERFILE_PATH

# Trim spaces
DOCKERFILE_PATH=$(echo "$DOCKERFILE_PATH" | xargs)

# Check if file exists
if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "❌ Error: Dockerfile not found at '$DOCKERFILE_PATH'"
  exit 1
fi

echo "🔍 Analyzing Dockerfile at: $DOCKERFILE_PATH"

# Flags
is_local=false
is_remote=false

# Read Dockerfile line-by-line
while IFS= read -r line; do
  # Normalize to lowercase and remove leading spaces
  clean_line=$(echo "$line" | tr '[:upper:]' '[:lower:]' | sed 's/^[ \t]*//')

  # Check for local code indicators
  if [[ "$clean_line" =~ ^(copy|add)[[:space:]]+\.[[:space:]] ]]; then
    is_local=true
  fi

  # Check for remote code fetching
  if echo "$clean_line" | grep -Eq 'git clone|curl|wget|http[s]?://'; then
    is_remote=true
  fi
done < "$DOCKERFILE_PATH"

# Output result
if [ "$is_remote" = true ]; then
  echo "This Dockerfile is pulling code from a REMOTE source (GitHub, curl, etc)."
elif [ "$is_local" = true ]; then
  echo "This Dockerfile is using LOCAL code (via COPY/ADD)."
else
  echo "Could not determine if code is local or remote. Manual review recommended."
fi