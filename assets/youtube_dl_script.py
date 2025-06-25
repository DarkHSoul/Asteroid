import sys
import json
import subprocess
import os

def get_stream_url(video_id):
    """
    Gets the streaming URL for a YouTube video ID using yt-dlp.
    Tries a few common locations for the yt-dlp executable.
    """
    if not video_id:
        print("Error: Video ID is required.", file=sys.stderr)
        return None

    # List of potential yt-dlp executable names or paths
    yt_dlp_cmds = [
        'yt-dlp',
        './yt-dlp',                      # In current directory
        './yt-dlp_linux',                # For linux
        './yt-dlp_macos',                # For macos
        './yt-dlp.exe',                  # For windows
        os.path.expanduser('~/bin/yt-dlp'), # Common user install location
        '/usr/local/bin/yt-dlp',         # Common system-wide install
    ]

    for cmd in yt_dlp_cmds:
        try:
            # Command to get the best audio-only stream URL in JSON format
            command = [
                cmd,
                '-f', 'bestaudio',
                '--get-url',
                f'https://www.youtube.com/watch?v={video_id}'
            ]
            
            # Execute the command
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=True,  # This will raise CalledProcessError if the command fails
                timeout=15   # Add a timeout
            )
            
            # The URL is in stdout
            stream_url = result.stdout.strip()
            if stream_url.startswith('http'):
                return stream_url
            else:
                # If it didn't return a URL, something is wrong with the output
                # but not necessarily an error code.
                continue # Try the next command

        except FileNotFoundError:
            # This means the command (e.g., 'yt-dlp') was not found, try the next one
            continue
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            # This catches errors if yt-dlp runs but fails, or if it hangs
            # print(f"Error running '{cmd}': {e}", file=sys.stderr)
            # print(f"Stderr: {e.stderr}", file=sys.stderr)
            continue # Try the next command
        except Exception as e:
            # Catch any other unexpected errors
            # print(f"An unexpected error occurred with '{cmd}': {e}", file=sys.stderr)
            continue

    # If all commands failed
    # print("Error: yt-dlp command failed or not found in any expected location.", file=sys.stderr)
    return None

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python youtube_dl_script.py <video_id>", file=sys.stderr)
        sys.exit(1)
    
    video_id_arg = sys.argv[1]
    url = get_stream_url(video_id_arg)
    
    if url:
        print(url)
        sys.exit(0)
    else:
        sys.exit(1)
