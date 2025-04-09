#!/usr/bin/env bash

# --- Configuration ---
OUTPUT_BASE_DIR="."
ARCHIVE_FILENAME="ytmp3_processed_archive.txt"

# --- Script Setup ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ARCHIVE_FILE="${SCRIPT_DIR}/${ARCHIVE_FILENAME}"

# --- Initial Archive Creation ---
if [ ! -f "$ARCHIVE_FILE" ]; then
    echo "Creating archive file at: $ARCHIVE_FILE"
    touch "$ARCHIVE_FILE"
fi

# --- Script Logic ---
if [ $# -eq 0 ]; then
    echo "Usage: ytmp3 <URL_or_ID_1> [URL_or_ID_2] ..."
    # ... (rest of usage message)
    exit 1
fi

processed_count=0
skipped_count=0
error_count=0

for video_identifier in "$@"; do
    echo "--------------------------------------------------"
    echo "Checking identifier: $video_identifier"

    if grep -Fxq -- "$video_identifier" "$ARCHIVE_FILE"; then
        echo "Skipping: '$video_identifier' is already in the archive ($ARCHIVE_FILENAME)."
        skipped_count=$((skipped_count + 1))
    else
        echo "Processing: $video_identifier"

        # Define the chapter output template including the directory
        output_template_chapter="chapter:${OUTPUT_BASE_DIR}/%(title)s/%(section_title)s - %(title)s.%(ext)s"

        # Run yt-dlp - Command on a single line to avoid shell parsing issues with backslashes
        # Use ONLY the chapter template for -o when splitting
        yt-dlp -i -f "bestvideo*+bestaudio/best" --extract-audio --audio-format mp3 --audio-quality 0 --split-chapters --embed-thumbnail -o "${output_template_chapter}" "$video_identifier"

        status=$?
        if [ $status -eq 0 ]; then
            echo "Successfully processed: $video_identifier"
            echo "$video_identifier" >> "$ARCHIVE_FILE"
            if [ $? -eq 0 ]; then
                 echo "Added '$video_identifier' to archive."
                 processed_count=$((processed_count + 1))
            else
                echo "Error: Failed to update archive file '$ARCHIVE_FILE' after processing."
                error_count=$((error_count + 1))
            fi
        else
            echo "An error occurred (Exit Code: $status) while processing: $video_identifier"
            error_count=$((error_count + 1))
        fi
    fi
    echo ""
done

echo "=================================================="
echo "Processing Summary:"
echo "  Successfully processed: $processed_count"
echo "  Skipped (already in archive): $skipped_count"
echo "  Errors: $error_count"
echo "Archive file: $ARCHIVE_FILE"
echo "=================================================="


exit 0
