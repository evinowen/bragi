configure_media_directories() {
    echo
    echo "=== Media Directory Configuration ==="
    echo "Please specify the directories for media storage."
    echo "These will be used by media services like SABnzbd, Sonarr, Radarr, etc."
    echo

    local config_mode=""

    while [[ "${config_mode:-}" != "s" && "${config_mode:-}" != "i" ]]; do
        echo "Configuration mode:"
        echo "  [s] Simple - Set base directory for each media type (recommended)"
        echo "  [i] Individual - Set each subdirectory separately"
        echo -n "Choose configuration mode [s/i]: "
        read config_mode </dev/tty
        config_mode=$(echo "${config_mode:-}" | tr '[:upper:]' '[:lower:]')

        if [[ -z "${config_mode:-}" ]]; then
            config_mode="s"
        fi

        if [[ "${config_mode}" != "s" && "${config_mode}" != "i" ]]; then
            echo "  Error: Please enter 's' for Simple or 'i' for Individual."
        fi
    done

    echo

    if [[ "$config_mode" == "s" ]]; then
        echo "Simple Configuration Mode"
        echo "Enter base directories. Subdirectories (download, stage, library) will be created automatically."
        echo

        echo "Television Shows:"
        echo -n "  Base directory [/media/television]: "
        read television_base </dev/tty
        television_base="${television_base:-/media/television}"
        TELEVISION_DOWNLOADS_DIR="$television_base/download"
        TELEVISION_STAGING_DIR="$television_base/stage"
        TELEVISION_LIBRARY_DIR="$television_base/library"

        echo

        echo "Movies:"
        echo -n "  Base directory [/media/movies]: "
        read movies_base </dev/tty
        movies_base="${movies_base:-/media/movies}"
        MOVIE_DOWNLOADS_DIR="$movies_base/download"
        MOVIE_STAGING_DIR="$movies_base/stage"
        MOVIE_LIBRARY_DIR="$movies_base/library"

    else
        echo "Individual Configuration Mode"
        echo "Specify each directory separately."
        echo

        echo "Television Shows:"
        echo -n "  Download directory [/media/television/download]: "
        read TELEVISION_DOWNLOADS_DIR </dev/tty
        TELEVISION_DOWNLOADS_DIR="${TELEVISION_DOWNLOADS_DIR:-/media/television/download}"

        echo -n "  Stage directory [/media/television/stage]: "
        read TELEVISION_STAGING_DIR </dev/tty
        TELEVISION_STAGING_DIR="${TELEVISION_STAGING_DIR:-/media/television/stage}"

        echo -n "  Library directory [/media/television/library]: "
        read TELEVISION_LIBRARY_DIR </dev/tty
        TELEVISION_LIBRARY_DIR="${TELEVISION_LIBRARY_DIR:-/media/television/library}"

        echo

        echo "Movies:"
        echo -n "  Download directory [/media/movies/download]: "
        read MOVIE_DOWNLOADS_DIR </dev/tty
        MOVIE_DOWNLOADS_DIR="${MOVIE_DOWNLOADS_DIR:-/media/movies/download}"

        echo -n "  Stage directory [/media/movies/stage]: "
        read MOVIE_STAGING_DIR </dev/tty
        MOVIE_STAGING_DIR="${MOVIE_STAGING_DIR:-/media/movies/stage}"

        echo -n "  Library directory [/media/movies/library]: "
        read MOVIE_LIBRARY_DIR </dev/tty
        MOVIE_LIBRARY_DIR="${MOVIE_LIBRARY_DIR:-/media/movies/library}"
    fi

    echo
    echo "Directory Configuration Summary:"
    echo "Television Shows:"
    echo "  Download:  $TELEVISION_DOWNLOADS_DIR"
    echo "  Stage:     $TELEVISION_STAGING_DIR"
    echo "  Library:   $TELEVISION_LIBRARY_DIR"
    echo "Movies:"
    echo "  Download:  $MOVIE_DOWNLOADS_DIR"
    echo "  Stage:     $MOVIE_STAGING_DIR"
    echo "  Library:   $MOVIE_LIBRARY_DIR"
}

create_media_directories() {
    echo
    echo "=== Directory Creation ==="

    local -a all_dirs=(
        "$TELEVISION_DOWNLOADS_DIR"
        "$TELEVISION_STAGING_DIR"
        "$TELEVISION_LIBRARY_DIR"
        "$MOVIE_DOWNLOADS_DIR"
        "$MOVIE_STAGING_DIR"
        "$MOVIE_LIBRARY_DIR"
    )

    local -a missing_dirs=()
    local -a unique_dirs=()

    for dir in "${all_dirs[@]}"; do
        local found=false

        for unique_dir in "${unique_dirs[@]}"; do
            if [[ "$dir" == "$unique_dir" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == "false" ]]; then
            unique_dirs+=("$dir")

            if [[ ! -d "$dir" ]]; then
                missing_dirs+=("$dir")
            fi
        fi
    done

    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        echo "✓ All directories already exist."
        return 0
    fi

    echo "The following directories do not exist:"

    for dir in "${missing_dirs[@]}"; do
        echo "  - $dir"
    done

    echo
    local create_dirs=""

    while [[ "${create_dirs:-}" != "y" && "${create_dirs:-}" != "n" && "${create_dirs:-}" != "" ]]; do
        echo -n "Would you like to create these directories? [y/N]: "
        read create_dirs </dev/tty
        create_dirs=$(echo "${create_dirs:-}" | tr '[:upper:]' '[:lower:]')
    done

    if [[ -z "$create_dirs" ]]; then
        create_dirs="n"
    fi

    if [[ "$create_dirs" == "y" ]]; then
        echo "Creating directories..."
        local created_count=0
        local failed_count=0

        for dir in "${missing_dirs[@]}"; do
            if mkdir -p "$dir" 2>/dev/null; then
                echo "✓ Created: $dir"
                created_count=$((created_count + 1))
            else
                echo "✗ Failed to create: $dir"
                failed_count=$((failed_count + 1))
            fi
        done

        echo
        echo "Directory Creation Summary:"
        echo "  Created: $created_count"
        echo "  Failed: $failed_count"

        if [[ $failed_count -gt 0 ]]; then
            echo
            echo "⚠️  Some directories could not be created. Services may fail if these"
            echo "   directories are not created manually before starting services."
        fi
    else
        echo "Skipping directory creation."
        echo
        echo "⚠️  Note: Services may fail to start if the configured directories"
        echo "   do not exist. Please create them manually before starting services."
    fi
}
