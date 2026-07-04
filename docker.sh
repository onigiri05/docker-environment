#!/bin/bash

# ==============================================================================
# Default Variables
# ==============================================================================
COMMAND=$1
shift # Remove the first argument (command), keep the rest for the while loop

IMAGE_NAME="hw-env"
CONT_NAME="hw-cont"
USER_NAME="$(id -un)"
HOSTNAME="hw-env-host"
MOUNTS=() # Use an array to handle multiple mount parameters safely

# ==============================================================================
# Argument Parsing
# ==============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --mount)
            # Convert input mount path to Docker's -v format
            MOUNTS+=("-v" "$2")
            shift 2
            ;;
        --image-name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --cont-name)
            CONT_NAME="$2"
            shift 2
            ;;
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown parameter: $1"
            echo "Usage: ./docker.sh {run|clean|rebuild|build} [options]"
            exit 1
            ;;
    esac
done

# ==============================================================================
# Core Functions
# ==============================================================================

# 1. Build Image
build_image() {
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        echo "Hint: Image '$IMAGE_NAME' already exists."
        echo "      To rebuild, execute: docker rmi $IMAGE_NAME (or use ./docker.sh rebuild)"
    else
        echo "Building Image '$IMAGE_NAME'..."
        # Assuming Dockerfile is in the current directory
        docker build --build-arg USERNAME="$USER_NAME" -t "$IMAGE_NAME" .
        echo "Image built successfully."
    fi
}

# 2. Run and Enter Container
run_container() {
    # Ensure the image exists; trigger build if it does not
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        echo "Warning: Image '$IMAGE_NAME' does not exist. Starting build process..."
        build_image
    fi

    # Get current container state (running, exited, created, or empty if not existed)
    local state=$(docker inspect -f '{{.State.Status}}' "$CONT_NAME" 2>/dev/null)

    echo "Detected container state: ${state:-not existed}"

    if [ "$state" == "running" ]; then
        echo "Container '$CONT_NAME' is running. Entering..."
        docker exec -it "$CONT_NAME" bash

    elif [ "$state" == "exited" ] || [ "$state" == "created" ]; then
        echo "Container '$CONT_NAME' is stopped. Restarting and entering..."
        docker start "$CONT_NAME"
        docker exec -it "$CONT_NAME" bash

    else
        echo "Container '$CONT_NAME' does not exist. Creating and starting..."
        
        # Use -d (detach) to keep it running in the background, 
        # and -it to keep tty open so bash doesn't exit immediately.
        docker run -it -d \
            --name "$CONT_NAME" \
            --hostname "$HOSTNAME" \
            -e HOST_USER="$USER_NAME" \
            "${MOUNTS[@]}" \
            "$IMAGE_NAME" \
            bash
            
        echo "Creation complete. Entering container..."
        docker exec -it "$CONT_NAME" bash
    fi
}

# 3. Clean Environment
clean_env() {
    echo "Cleaning up environment..."
    
    if docker container inspect "$CONT_NAME" >/dev/null 2>&1; then
        docker rm -f "$CONT_NAME"
        echo "Force removed container: '$CONT_NAME'"
    fi
    
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        docker rmi -f "$IMAGE_NAME"
        echo "Force removed image: '$IMAGE_NAME'"
    fi
    
    echo "Cleanup complete."
}

# ==============================================================================
# Main Logic Router
# ==============================================================================
case "$COMMAND" in
    build)
        build_image
        ;;
    run)
        run_container
        ;;
    clean)
        clean_env
        ;;
    rebuild)
        clean_env
        build_image
        ;;
    *)
        echo "======================================================"
        echo " Docker Environment Manager Script"
        echo "======================================================"
        echo "Usage: ./docker.sh <command> [options]"
        echo ""
        echo "Commands:"
        echo "  run      Start and enter the container (auto-detects state)"
        echo "  build    Build the image only"
        echo "  clean    Remove the container and image"
        echo "  rebuild  Clean the existing environment and rebuild the image"
        echo ""
        echo "Options:"
        echo "  --mount <host:cont>    Mount local directory to container (Can be used multiple times)"
        echo "  --image-name <name>    Specify image name (Default: hw-env)"
        echo "  --cont-name <name>     Specify container name (Default: hw-cont)"
        echo "  --hostname <name>      Specify container hostname (Default: hw-env-host)"
        echo "======================================================"
        exit 1
        ;;
esac