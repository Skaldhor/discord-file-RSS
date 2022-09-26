[CmdletBinding()] # for standard parameters like -Verbose or -ErrorAction
param(
    [Parameter(Mandatory=$true, HelpMessage="Amount of messages you want to query per Discord channel, maximum 100")] [int]$MessageLimit,
    [Parameter(Mandatory=$true, HelpMessage="Maximum amount of total RSS items you want to save (it's recommended to set the limit below 2000, because the xml file will get extremely big and the RSS reader takes too long to load the entries)")] [int]$TotalItemLimit,
    [Parameter(Mandatory=$true, HelpMessage="Full path to where the RSS xml file gets saved.")] [string]$RssFilePath,
    [Parameter(Mandatory=$true, HelpMessage="The name for your RSS channel.")] [string]$RssChannel,
    [Parameter(Mandatory=$true, HelpMessage="List of Discord channelIDs to query for messages.")] [array]$ChannelIds,
    [Parameter(Mandatory=$true, HelpMessage="Your personal Discord auth token.")] [string]$AuthToken,
    [Parameter(Mandatory=$false, HelpMessage="List of file types you want to filter for, for example 'pdf' or 'jpg'.")] [array]$FilterFileTypes
)

# --- script ---
# create function to get messages per channel
function Get-DiscordFiles{
    # declare parameters
    param(
        [Parameter(Mandatory=$true)] [string]$ChannelId,
        [Parameter(Mandatory=$true)] [string]$AuthToken,
        [Parameter(Mandatory=$false)] [array]$FilterFileTypes,
        [Parameter(Mandatory=$false)] [int]$MessageLimit
    )

    # fix invalid message limit
    if($PSBoundParameters.ContainsKey("FilterFileTypes") -eq $false){
        $MessageLimit = 100
    }elseif(($MessageLimit -gt 100) -or ($MessageLimit -lt 1)){
        $MessageLimit = 100
        Write-Host "Invalid message limit (must be between 1 and 100). Set limit to 100."
    }

    # set auth header and make json web request
    $Headers = @{
        Authorization = $AuthToken
    }
    $Url = "https://discord.com/api/v9/channels/$($ChannelId)/messages?limit=$($MessageLimit)"

    # get channel name from id
    $ChannelRequest = (Invoke-WebRequest -Uri "https://discord.com/api/v9/channels/$($ChannelId)" -Headers $Headers -Method "Get").Content | ConvertFrom-Json
    $ChannelName = $ChannelRequest.Name
        
    # get server name from from id
    $ServerRequest = (Invoke-WebRequest -Uri "https://discord.com/api/v9/guilds/$($ChannelRequest.guild_id)" -Headers $Headers -Method "Get").Content | ConvertFrom-Json
    $ServerName = $ServerRequest.Name

    # get messages from channel
    $Request = (Invoke-WebRequest -Uri $Url -Headers $Headers -Method "Get").Content | ConvertFrom-Json

    # process each request and get requested urls
    $List = foreach($Post in $Request){
        $Embeds = $Post.embeds.image.url | Sort-Object -Unique
        $Attachments = $Post.attachments.url | Sort-Object -Unique
        $FileUrls = $Embeds + $Attachments | Sort-Object -Unique
        if($PSBoundParameters.ContainsKey("FilterFileTypes") -eq $true){
            $FileUrls = $FileUrls | Where-Object{($_.Split("."))[-1] -in $FilterFileTypes}
        }
        if($FileUrls.Count -gt 0){
            foreach($FileUrl in $FileUrls){
                [ordered]@{PostId = $Post.Id; Date = $Post.Timestamp; Server = $ServerName; Channel = $ChannelName; Author = $Post.Author.Username; FileUrl = $FileUrl; Message = $Post.Content}
            }
        }
    }
    $Table = $List | ForEach-Object{New-Object Object | Add-Member -NotePropertyMembers $_ -PassThru}
    $Table
}

# query all requested channels and combine output
$Output = foreach($ChannelId in $ChannelIds){
    Get-DiscordFiles -ChannelId $ChannelId -AuthToken $AuthToken #-FilterFileTypes $FilterFileTypes
}
$Output = $Output | Sort-Object -Property "Date" -Descending -Top $TotalItemLimit

# create RSS items list
Write-Verbose "Creating RSS XML file..."
$RssItems = New-Object Collections.Generic.List[String]
foreach($Item in $Output){
    # fix special characters for RSS/HTML
    $ChannelName = $Item.Channel.Replace("<","").Replace(">","").Replace("&","").Replace(";","")
    $ServerName = $Item.Server.Replace("<","").Replace(">","").Replace("&","").Replace(";","")
    $AuthorName = $Item.Author.Replace("<","").Replace(">","").Replace("&","").Replace(";","")
    $Message = $Item.Message.Replace("<","").Replace(">","").Replace("&","").Replace(";","")

$RssItems.Add("       <item>
                    <title>New Discord file</title>
                    <link>$($Item.FileUrl)</link>
                    <guid>$($Item.FileUrl)</guid>
                    <pubDate>$($Item.Date)</pubDate>
                    <description>&lt;img src=&quot;$($Item.FileUrl)&quot;&gt;&lt;br&gt;Server: $($ServerName) - Channel: $($ChannelName) - Author: $($AuthorName)&lt;br&gt;Message: $($Message)</description>
                </item>
        ")
}

# create RSS opening tags
$RssOpeningTags = "<?xml version=""1.0"" encoding=""utf-8""?><rss xmlns:atom=""http://www.w3.org/2005/Atom"" version=""2.0"">
    <channel>
        <title>$RssChannel</title>
        <link></link>
        <description>$RssChannel</description>

        "

# create RSS opening tags
$RssClosingTags = "
        </channel>
</rss>"

# create finished RSS file
$RssFeed = $RssOpeningTags + $RssItems + $RssClosingTags
Set-Content -Path $RssFilePath -Value $RssFeed
Write-Verbose "Done."
