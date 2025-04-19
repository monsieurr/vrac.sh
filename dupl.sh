#!/bin/bash

# --- Configuration ---
# Use md5 (faster, common on macOS) or shasum (more collision resistant)
HASH_COMMAND="md5 -q"
# HASH_COMMAND="shasum -a 256" # Alternative using SHA-256

# --- Script Info ---
SCRIPT_NAME=$(basename "$0")
VERSION="1.1"

# --- Default Values ---
filetypes=()
directories=()
store_duplicates=false
store_file="" # Will be generated if -s is used

# --- Functions ---

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options] [directory ...]

Find duplicate files recursively based on content hash.

Arguments:
  directory ...       One or more directories to search recursively.
                      Defaults to the current directory (.) if none specified.

Options:
  -f, --filetypes ext1 [ext2 ...]   Limit search to specific file extensions (e.g., jpg png mov).
                                    Do not include the leading dot (.).
  -s, --store                       Store the paths of all duplicate files (all except one
                                    from each set) to a timestamped text file in the
                                    current directory (duplicates_YYYYMMDD_HHMMSS.txt).
  -h, --help                        Display this help message and exit.
  -v, --version                     Display script version and exit.

Examples:
  $SCRIPT_NAME                   # Search in current directory for all file types
  $SCRIPT_NAME ~/Pictures ~/Docs # Search in specific directories
  $SCRIPT_NAME -f jpg png        # Search current directory for *.jpg and *.png files
  $SCRIPT_NAME -s -f mp3 /Volumes/Music # Search for *.mp3 files on a specific volume and store duplicates list

Notes:
  - Compares files based on MD5 hash (default) after grouping by size.
  - Handles filenames with spaces or special characters.
  - Reports summary statistics upon completion.
EOF
    exit 0
}

version_info() {
    echo "$SCRIPT_NAME version $VERSION"
    exit 0
}

# Formats seconds into a human-readable duration
display_time() {
    local T=$1 D H M S
    D=$((T / 60 / 60 / 24))
    H=$((T / 60 / 60 % 24))
    M=$((T / 60 % 60))
    S=$((T % 60))
    ((D > 0)) && printf "%d days " $D
    ((H > 0)) && printf "%d hours " $H
    ((M > 0)) && printf "%d minutes " $M
    printf "%d seconds" $S
}

# Formats bytes into human-readable size (IEC standard: KiB, MiB, GiB)
format_size() {
    local size=$1
    if command -v numfmt >/dev/null; then
        # Use numfmt if available (GNU coreutils)
        numfmt --to=iec-i --suffix=B --format="%.2f" "$size"
    else
        # Basic fallback for macOS without coreutils
        local unit="B"
        local value=$size
        if (( value > 1024 )); then value=$((value / 1024)); unit="KiB"; fi
        if (( value > 1024 )); then value=$((value / 1024)); unit="MiB"; fi
        if (( value > 1024 )); then value=$((value / 1024)); unit="GiB"; fi
        if (( value > 1024 )); then value=$((value / 1024)); unit="TiB"; fi
        printf "%d %s" "$value" "$unit" # Fallback doesn't do decimals well
    fi
}

# Error handling function
error_exit() {
    echo "ERROR: $1" >&2
    # Cleanup is handled by trap
    exit 1
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--filetypes)
            shift
            if [[ $# -eq 0 || $1 == -* ]]; then
                error_exit "Option $1 requires at least one file extension."
            fi
            while [[ $# -gt 0 && ! $1 == -* ]]; do
                # Sanitize: remove leading/trailing dots
                local ext=${1#.} # Remove leading dot
                ext=${ext%.}   # Remove trailing dot (less common)
                [[ -n "$ext" ]] && filetypes+=("$ext") # Add if not empty
                shift
            done
            ;;
        -s|--store)
            store_duplicates=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -v|--version)
            version_info
            ;;
        -*)
            error_exit "Unknown option: $1. Use -h or --help for usage."
            ;;
        *)
            # Check if directory exists and is readable
            if [[ -d "$1" && -r "$1" ]]; then
                directories+=("$1")
            else
                echo "Warning: Skipping invalid or unreadable directory: $1" >&2
            fi
            shift
            ;;
    esac
done

# Set default directories if none provided or all were invalid
[[ ${#directories[@]} -eq 0 ]] && directories=(".")

# --- Preparation ---

# Build find command arguments
find_args=("${directories[@]}" -type f)

if [[ ${#filetypes[@]} -gt 0 ]]; then
    find_pattern=() # Initialize explicitly
    # Build pattern like: \( -name "*.ext1" -o -name "*.ext2" \)
    find_pattern+=(-name "*.${filetypes[0]}")
    for ext in "${filetypes[@]:1}"; do
        find_pattern+=(-o -name "*.$ext")
    done
    # Group the -name patterns with parentheses
    find_args+=(\( "${find_pattern[@]}" \))
fi

# Add null delimiter for safe filename handling
find_args+=(-print0)

# Create temporary directory for storing hash lists
temp_dir=$(mktemp -d -t duplicate_finder_XXXXXX)
if [[ ! -d "$temp_dir" ]]; then
    error_exit "Failed to create temporary directory."
fi
# Setup trap for cleanup on exit (normal or error)
trap 'rm -rf "$temp_dir"' EXIT SIGINT SIGTERM

echo "Starting duplicate file search..."
echo "Searching in: ${directories[*]}"
if [[ ${#filetypes[@]} -gt 0 ]]; then
    echo "Filtering by filetypes: ${filetypes[*]}"
fi
echo "Temporary directory: $temp_dir"

# --- Main Processing ---

start_time=$(date +%s)
processed_files_count=0
processed_size_total=0
declare -A size_map # Associative array to group files by size first

# Phase 1: Find files and group by size
echo "Phase 1: Finding files and grouping by size..."
while IFS= read -r -d '' file; do
    ((processed_files_count++))
    # Get size using stat (robust for macOS)
    size=$(stat -f %z "$file" 2>/dev/null)
    if [[ $? -ne 0 || -z "$size" ]]; then
        echo "Warning: Could not get size for '$file'. Skipping." >&2
        continue
    fi

    processed_size_total=$((processed_size_total + size))

    # Optimization: Only hash files that have potential duplicates (same size)
    # Append filename (null-separated) to the entry for this size in the map
    # Using null separator within the map value for safety
    size_map["$size"]+="$file"$'\0'

    # Provide some progress feedback
    if (( processed_files_count % 500 == 0 )); then
      printf "Processed %d files...\r" $processed_files_count
    fi

done < <(find "${find_args[@]}" 2>/dev/null) # Redirect find errors to stderr
find_status=$?
printf "\nPhase 1 complete. Processed %d files.\n" $processed_files_count

if [[ $find_status -ne 0 ]]; then
     echo "Warning: 'find' command encountered errors during execution." >&2
fi

# Phase 2: Calculate hashes only for files with matching sizes
echo "Phase 2: Calculating hashes for files with potential size matches..."
declare -A hash_map # Associative array: hash -> list of files (null separated)
potential_duplicate_size_groups=0

for size in "${!size_map[@]}"; do
    # Read null-separated files back into an array
    IFS=$'\0' read -r -d '' -a files_with_same_size <<< "${size_map[$size]}"

    # Only process if more than one file has this size
    if [[ ${#files_with_same_size[@]} -gt 1 ]]; then
        ((potential_duplicate_size_groups++))
        for file in "${files_with_same_size[@]}"; do
             # Check again if file still exists and is readable before hashing
             if [[ ! -f "$file" || ! -r "$file" ]]; then
                 echo "Warning: File '$file' disappeared or became unreadable before hashing. Skipping." >&2
                 continue
             fi

            # Calculate hash
            hash=$($HASH_COMMAND "$file" 2>/dev/null)
            if [[ $? -ne 0 || -z "$hash" ]]; then
                echo "Warning: Could not compute hash for '$file'. Skipping." >&2
                continue
            fi
            # Store file path associated with this hash (null-separated)
            hash_map["$hash"]+="$file"$'\0'
        done
    fi
     # Progress for phase 2
    if (( potential_duplicate_size_groups % 100 == 0 && potential_duplicate_size_groups > 0 )); then
      printf "Processed %d size groups for hashing...\r" $potential_duplicate_size_groups
    fi
done
printf "\nPhase 2 complete. Hashed files from %d size groups.\n" $potential_duplicate_size_groups


# --- Analysis and Reporting ---
echo "Phase 3: Analyzing hashes and identifying duplicates..."
duplicates_count=0      # Total number of files identified as duplicates (N-1 per set)
duplicates_size=0       # Total size of these duplicate files
declare -a duplicate_files_to_store # Array to hold paths for the -s option

# Process each hash that has files associated with it
for hash in "${!hash_map[@]}"; do
    # Read null-separated files back into an array
    IFS=$'\0' read -r -d '' -a files_with_same_hash <<< "${hash_map[$hash]}"
    count=${#files_with_same_hash[@]}

    # If more than one file has the same hash, they are duplicates
    if (( count > 1 )); then
        # Get the size from the first file (they should all be the same size
        # because we pre-filtered by size before hashing, but check just in case)
        # We retrieve size again, avoiding potential issues if file changed
        # between phase 1 and phase 2 (unlikely but possible)
        first_file="${files_with_same_hash[0]}"
        if [[ ! -f "$first_file" ]]; then
             echo "Warning: Original file '$first_file' for hash $hash seems missing. Skipping this set." >&2
             continue
        fi
        size=$(stat -f %z "$first_file" 2>/dev/null)
         if [[ $? -ne 0 || -z "$size" ]]; then
            echo "Warning: Could not get size for '$first_file' (hash $hash). Skipping this set." >&2
            continue
        fi

        local num_dupes_in_set=$((count - 1))
        duplicates_count=$((duplicates_count + num_dupes_in_set))
        duplicates_size=$((duplicates_size + size * num_dupes_in_set))

        # Add all files *except the first one* to the list for storage if requested
        for (( i=1; i<count; i++ )); do
             duplicate_files_to_store+=("${files_with_same_hash[$i]}")
        done

        # Optional: Print duplicate sets found during analysis (can be verbose)
        # echo "Duplicate set (hash: $hash):"
        # printf "  %s\n" "${files_with_same_hash[@]}"
    fi
done
echo "Phase 3 complete."


end_time=$(date +%s)
duration=$((end_time - start_time))

# --- Final Report ---
printf "\n=== Duplicate File Report ===\n"
printf "Start time:           %s\n" "$(date -r $start_time)"
printf "End time:             %s\n" "$(date -r $end_time)"
printf "Total execution time: %s\n" "$(display_time $duration)"
printf "\n"
printf "Directories scanned:  %s\n" "${directories[*]}"
if [[ ${#filetypes[@]} -gt 0 ]]; then
    printf "Filetypes filtered:   %s\n" "${filetypes[*]}"
fi
printf "\n"
printf "Total files checked:  %d\n" "$processed_files_count"
printf "Total size checked:   %s\n" "$(format_size $processed_size_total)"
printf "\n"
printf "Duplicate files found:%d\n" "$duplicates_count"
printf "Total size of dups:   %s (Potential space savings)\n" "$(format_size $duplicates_size)"
printf "=============================\n"

# --- Store Duplicates (if requested) ---
if [[ "$store_duplicates" == true ]]; then
    if [[ ${#duplicate_files_to_store[@]} -gt 0 ]]; then
        timestamp=$(date +%Y%m%d_%H%M%S)
        store_file="duplicates_${timestamp}.txt"
        echo "Storing paths of $duplicates_count duplicate files to: $store_file"
        # Use printf for safe output of filenames
        printf "%s\n" "${duplicate_files_to_store[@]}" > "$store_file"
        if [[ $? -ne 0 ]]; then
             echo "Warning: Failed to write duplicates list to '$store_file'." >&2
        fi
    else
        echo "No duplicate files found to store."
    fi
fi

exit 0
