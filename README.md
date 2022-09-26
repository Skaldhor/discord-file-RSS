# discord-file-RSS
This script can create a RSS feed of posted files in specified discord channels.

## Dependencies
- Powershell (developed in v7+)

## Usage
1. Run the script with the following arguments:
`.\discord-file-RSS.ps1 -MessageLimit <integer: 1-100> -TotalItemLimit <integer: amount of total RSS items in final xml> -RssFilePath <string: path to output the xml file> -RssChannel <string: name of the RSS channel in the xml> -ChannelIds <array: list of channel IDs to search for new files> -AuthToken <string: Your personal Auth token> -FilterFileTypes <optional argument; array: List of file types you want to filter for, for example 'pdf' or 'jpg'>`
2. Run the script with a scheduled task/cronjob
