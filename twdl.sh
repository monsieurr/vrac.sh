#!/bin/bash

# Script to download Twitch VODs using yt-dlp
# Accepts full URLs (https://www.twitch.tv/videos/...) or just VOD IDs

# --- Configuration ---
# Add any default yt-dlp options here if needed
# Example: YTDLP_OPTIONS="--format bestvideo+bestaudio/best --merge-output-format mp4"
YTDLP_OPTIONS=""
# --- End Configuration ---

# Check if yt-dlp is installed
if ! command -v yt-dlp &> /dev/null; then
    echo "Error: yt-dlp could not be found."
    echo "Please install it first (e.g., pip install -U yt-dlp or check https://github.com/yt-dlp/yt-dlp#installation)"
    exit 1
fi

# Check if at least one argument (URL or ID) is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <Twitch_VOD_URL_or_ID> [Twitch_VOD_URL_or_ID...]"
    echo "Example:"
    echo "  $0 https://www.twitch.tv/videos/2427574349"
    echo "  $0 2427574349"
    echo "  $0 https://www.twitch.tv/videos/2427574349 1234567890 https://www.twitch.tv/videos/987654321"
    exit 1
fi

echo "Starting Twitch VOD download process..."

# Loop through all arguments provided
for arg in "$@"; do
    video_ref="$arg"
    full_url=""

    # Check if the argument looks like a URL or just an ID
    # Simple check: if it contains http:// or https:// assume URL, otherwise assume ID
    if [[ "$video_ref" == *"http://"* || "$video_ref" == *"https://"* ]]; then
        # Input is likely a full URL
        # Basic validation: check if it contains twitch.tv/videos/
        if [[ "$video_ref" == *"twitch.tv/videos/"* ]]; then
             full_url="$video_ref"
             echo "Processing URL: $full_url"
        else
             echo "Warning: '$video_ref' looks like a URL but not a standard Twitch VOD URL. Skipping."
             continue # Skip to the next argument
        fi
    elif [[ "$video_ref" =~ ^[0-9]+$ ]]; then
        # Input is likely just an ID (consists only of digits)
        full_url="https://www.twitch.tv/videos/$video_ref"
        echo "Processing ID $video_ref as URL: $full_url"
    else
        # Input doesn't look like a URL or a numeric ID
        echo "Warning: Unrecognized input '$video_ref'. Skipping. Please provide a valid URL or numeric VOD ID."
        continue # Skip to the next argument
    fi

    # Construct and run the yt-dlp command
    echo "---"
    echo "Attempting download for: $full_url"
    # The eval is used here to correctly handle potential spaces within YTDLP_OPTIONS if defined with quotes
    # If YTDLP_OPTIONS is empty, it effectively just runs: yt-dlp "$full_url"
    eval yt-dlp $YTDLP_OPTIONS '"$full_url"'

    # Check the exit status of yt-dlp
    if [ $? -ne 0 ]; then
        echo "Error downloading: $full_url"
    else
        echo "Finished processing: $full_url"
    fi
    echo "---"
    echo # Add a blank line for better separation between downloads

done

echo "All specified VOD download attempts are complete."
