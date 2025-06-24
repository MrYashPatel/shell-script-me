#!/bin/bash

echo "📂 Enter full or relative path to your Dockerfile:"
read -r DOCKERFILE_PATH
DOCKERFILE_PATH=$(echo "$DOCKERFILE_PATH" | xargs)

if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "❌ Error: Dockerfile not found at '$DOCKERFILE_PATH'"
  exit 1
fi

echo "🔍 Analyzing Dockerfile at: $DOCKERFILE_PATH"

is_local=false
is_remote=false
repo_name=""

# Step 1: Detect local or remote code usage
while IFS= read -r line; do
  clean_line=$(echo "$line" | tr '[:upper:]' '[:lower:]' | sed 's/^[ \t]*//')
  [[ "$clean_line" =~ ^(copy|add)[[:space:]]+\.[[:space:]] ]] && is_local=true
  echo "$clean_line" | grep -Eq 'git clone|curl|wget|http[s]?://' && is_remote=true
done < "$DOCKERFILE_PATH"

# Step 2: Detect repo name
if [ "$is_remote" = true ]; then
  echo "📡 Dockerfile pulls from REMOTE source."
  remote_url=$(grep -Ei 'git clone|http[s]?://.*github.com' "$DOCKERFILE_PATH" | grep -oE 'http[s]?://[^ ]+')
  [ -n "$remote_url" ] && repo_name=$(basename "$remote_url" .git)
elif [ "$is_local" = true ]; then
  echo "💾 Dockerfile uses LOCAL code."
  repo_name=$(basename "$(dirname "$DOCKERFILE_PATH")")
else
  echo "🤔 Could not determine source type. Using folder name."
  repo_name=$(basename "$(dirname "$DOCKERFILE_PATH")")
fi

# Step 3: Check label-based image source
label_repo_url=$(grep -i 'image.source' "$DOCKERFILE_PATH" | grep -oP '(?<=source=")[^"]+')
[ -n "$label_repo_url" ] && repo_name=$(basename "$label_repo_url" .git)

# Step 4: Check Docker login
echo ""
echo "🔐 Checking Docker login..."

get_user_from_credstore() {
  local helper
  CONFIG="$HOME/.docker/config.json"
  helper=$(jq -r '.credsStore' "$CONFIG" 2>/dev/null)
  if [ -n "$helper" ] && command -v "docker-credential-$helper" >/dev/null; then
    docker-credential-$helper list 2>/dev/null | jq -r --arg reg "https://index.docker.io/v1/" '.[$reg]' | cut -d: -f1
  fi
}

CONFIG="$HOME/.docker/config.json"
REGISTRY="https://index.docker.io/v1/"
DOCKER_CURRENT_USER=""

if [ -f "$CONFIG" ]; then
  AUTH=$(jq -r ".auths[\"$REGISTRY\"].auth" "$CONFIG" 2>/dev/null)
  if [ -n "$AUTH" ] && [ "$AUTH" != "null" ]; then
    DOCKER_CURRENT_USER=$(echo "$AUTH" | base64 --decode | cut -d: -f1)
  else
    DOCKER_CURRENT_USER=$(get_user_from_credstore)
  fi
fi

if [ -z "$DOCKER_CURRENT_USER" ]; then
  echo "❌ Docker is NOT logged in. Please run: docker login"
  exit 1
fi

echo "✅ Logged in as: $DOCKER_CURRENT_USER"
echo "📦 Repo name: $repo_name"

# Step 5: Ask user for tag
echo ""
read -rp "🏷️ Enter tag for the image (default: latest): " TAG_NAME
TAG_NAME=${TAG_NAME:-latest}

# Step 6: Build Docker image
IMAGE_NAME="$DOCKER_CURRENT_USER/$repo_name:$TAG_NAME"
BUILD_CONTEXT=$(dirname "$DOCKERFILE_PATH")

echo ""
echo "🛠️ Building image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" "$BUILD_CONTEXT"

if [ $? -ne 0 ]; then
  echo "❌ Docker build failed!"
  exit 1
fi

# Step 7: Push versioned tag
echo "📤 Pushing image to Docker Hub..."
docker push "$IMAGE_NAME"

if [ $? -eq 0 ]; then
  echo "✅ Successfully pushed: $IMAGE_NAME"

  # Step 8: Also push as 'latest'
  LATEST_IMAGE="$DOCKER_CURRENT_USER/$repo_name:latest"
  echo "🔄 Tagging image as: $LATEST_IMAGE"
  docker tag "$IMAGE_NAME" "$LATEST_IMAGE"
  echo "📤 Pushing 'latest' tag..."
  docker push "$LATEST_IMAGE"

  if [ $? -eq 0 ]; then
    echo "✅ 'latest' tag pushed: $LATEST_IMAGE"
  else
    echo "⚠️ Failed to push 'latest' tag"
  fi

else
  echo "❌ Failed to push image: $IMAGE_NAME"
fi