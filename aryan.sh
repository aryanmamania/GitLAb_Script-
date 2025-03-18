#!/bin/bash

# Exit on any error
set -e

# Git credentials
GIT_USERNAME="${GIT_USERNAME:-root}"
GIT_PASSWORD="${GIT_PASSWORD:-zyoiDZXaJNJQvx6Pfeuu}"

# Prompt for service name
echo -n "Enter the Service Name: "
read SERVICE_NAME

if [ -z "$SERVICE_NAME" ]; then
  echo "Service name is required. Exiting."
  exit 1
fi

echo "You entered: $SERVICE_NAME"

# Variables
CLONE_PATH="/home/aaa/aryan/"
BRANCH="UAT_Branch"
REPO_URL="http://${GIT_USERNAME}:${GIT_PASSWORD}@10.181.48.188:81/root/${SERVICE_NAME}.git"
PROD_REG_REPO="registry.esbprod.finopaymentbank.in/bankesbprod"
PROD_CRED="${PROD_CRED:-esbadmin:Fino@2024}"

# Remove any previous cloned repo
echo "Cleaning up any existing clone..."
rm -rf "${CLONE_PATH}${SERVICE_NAME}"

# Clone the repository
echo "Cloning repository for ${SERVICE_NAME} into ${CLONE_PATH}${SERVICE_NAME}..."
git clone -b "$BRANCH" "$REPO_URL" "${CLONE_PATH}${SERVICE_NAME}"
cd "${CLONE_PATH}${SERVICE_NAME}"

# Add required lines to application.properties
echo "Adding OpenTelemetry tracing configuration to application.properties..."
echo -e "\nquarkus.otel.traces.sampler=traceidratio" >> src/main/resources/application.properties
echo "quarkus.otel.traces.sampler.arg=0.001" >> src/main/resources/application.properties

# Merge branches
echo "Merging UAT_Branch into Master..."
git config --global user.email "root@example.com"
git config --global user.name "root"

# Handle uncommitted changes
git stash push -m "Stashing local changes before switching branches" || true
git checkout master
git stash pop || true

# Add and commit changes
git add .
git commit -m "Auto-commit: Saving changes before merging branches" || true

# Attempt to merge branches
if git merge --allow-unrelated-histories --no-ff UAT_Branch -m "Merging Locally Due to conflicts" -X theirs; then
  echo "Branches Merged Successfully."
else
  echo "Merge conflict detected. Resolving conflicts by favoring changes from UAT_Branch..."
  git checkout --theirs src/main/resources/application.properties
  git add src/main/resources/application.properties
  git commit -m "Resolved merge conflict by favoring UAT_Branch changes"
fi

# Push changes to the repository
echo "Pushing changes to the repository..."
git push "$REPO_URL"

# Get the latest commit hash
GIT_COMMIT_VERSION=$(git rev-parse --short HEAD)

# Generate timestamp
DATE=$(date +'%d%m%Y%H%M')

# Convert service name to lowercase
LOWERCASE_NAME=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]')

# Define the Docker image tag with the production registry
IMAGE_TAG="${PROD_REG_REPO}/${LOWERCASE_NAME}:${GIT_COMMIT_VERSION}_${DATE}"
echo "Docker image tag: ${IMAGE_TAG}"

# Build the Maven project
echo "Building the project with Maven..."
mvn clean compile package -DskipTests

# Build the Docker image
echo "Building the Docker image for ${SERVICE_NAME} with tag ${IMAGE_TAG}..."
buildah build -t "${IMAGE_TAG}" -f src/main/docker/Dockerfile.jvm .

# Remove the cloned repo to save space
echo "Removing cloned repository..."
rm -rf "${CLONE_PATH}${SERVICE_NAME}"

# Push the Docker image to the production registry
echo "Pushing the Docker image to the production registry..."
buildah push --tls-verify=false --creds="${PROD_CRED}" "${IMAGE_TAG}"

# Print image details
echo "The following Docker image has been built and pushed:"
echo "${IMAGE_TAG}"

echo "Script executed successfully."
