[CmdletBinding()] # for standard parameters like -Verbose or -ErrorAction
param(
    [Parameter(Mandatory=$true, HelpMessage="Amount of messages you want to query per Discord channel, maximum 100")] [int]$MessageLimit,
    [Parameter(Mandatory=$true, HelpMessage="Maximum amount of total RSS items you want to save (it's recommended to set the limit below 2000, because the xml file will get extremely big and the RSS reader takes too long to load the entries)")] [int]$TotalItemLimit,
    [Parameter(Mandatory=$true, HelpMessage="Full path to where the RSS xml file gets saved.")] [string]$RssFilePath,
    [Parameter(Mandatory=$true, HelpMessage="The name for your RSS channel.")] [string]$RssChannel,
    [Parameter(Mandatory=$true, HelpMessage="List of Discord channelIDs to query for messages.")] [array]$ChannelIds,
    [Parameter(Mandatory=$true, HelpMessage="Your personal Discord auth token.")] [string]$AuthToken,
    [Parameter(Mandatory=$false, HelpMessage="List of file types you want to filter for, for example 'pdf' or 'jpg'.")] [array]$FilterFileTypes,
    [Parameter(Mandatory=$false, HelpMessage="Discord API base URL to use, must not end with a slash '/'.")] [string]$ApiUrl = "https://discord.com/api/v10"
)

# --- script ---
# create function to get messages per channel
function Get-DiscordFiles{
    # declare parameters
    param(
        [Parameter(Mandatory=$true)] [string]$ChannelId,
        [Parameter(Mandatory=$true)] [string]$AuthToken,
        [Parameter(Mandatory=$false)] [string[]]$FilterFileTypes,
        [Parameter(Mandatory=$false)] [int]$MessageLimit,
        [Parameter(Mandatory=$false)] [string]$ApiUrl = "https://discord.com/api/v10"
    )

    # fix invalid message limit
    if($PSBoundParameters.ContainsKey("MessageLimit") -eq $false){
        $MessageLimit = 100
    }elseif(($MessageLimit -gt 100) -or ($MessageLimit -lt 1)){
        $MessageLimit = 100
        Write-Host "Invalid message limit (must be between 1 and 100). Set limit to 100."
    }

    # create auth header for web requests
    $Headers = @{
        Authorization = $AuthToken
    }

    # get channel name from id
    $ChannelRequest = Invoke-RestMethod -Uri "$($ApiUrl)/channels/$($ChannelId)" -Headers $Headers -Method "Get"

    # get server name from channel
    $ServerRequest = Invoke-RestMethod -Uri "$($ApiUrl)/guilds/$($ChannelRequest.guild_id)" -Headers $Headers -Method "Get"

    # get messages from channel
    $MessageRequest = Invoke-RestMethod -Uri "$($ApiUrl)/channels/$($ChannelId)/messages?limit=$($MessageLimit)" -Headers $Headers -Method "Get"

    # process each request and get requested urls
    $List = @()
    foreach($Post in $MessageRequest){
        $Embeds = $Post.embeds.image.url | Sort-Object -Unique
        $Attachments = $Post.attachments.url | Sort-Object -Unique
        [string[]]$FileUrls = $Embeds + $Attachments | Sort-Object -Unique
        if($PSBoundParameters.ContainsKey("FilterFileTypes") -eq $true){
            [string[]]$FileUrls = $FileUrls | Where-Object{($_.Split("."))[-1] -in $FilterFileTypes}
        }
        foreach($FileUrl in $FileUrls){
            $List += [PSCustomObject]@{
                PostId = $Post.Id
                Date = $Post.Timestamp
                Server = $ServerRequest.Name
                Channel = $ChannelRequest.Name
                Author = $Post.Author.Username
                FileUrl = $FileUrl
                Message = $Post.Content
            }
        }
    }
    $List
}

# query all requested channels and combine output
$Output = foreach($ChannelId in $ChannelIds){
    if($PSBoundParameters.ContainsKey("FilterFileTypes") -eq $true){
        Get-DiscordFiles -ChannelId $ChannelId -AuthToken $AuthToken -FilterFileTypes $FilterFileTypes
    }else{
        Get-DiscordFiles -ChannelId $ChannelId -AuthToken $AuthToken
    }
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
                    <link>$([System.Web.HttpUtility]::HtmlEncode($Item.FileUrl))</link>
                    <guid>$([System.Web.HttpUtility]::HtmlEncode($Item.FileUrl))</guid>
                    <pubDate>$($Item.Date)</pubDate>
                    <description>&lt;img src=&quot;$([System.Web.HttpUtility]::HtmlEncode($Item.FileUrl))&quot;&gt;&lt;br&gt;Server: $($ServerName) - Channel: $($ChannelName) - Author: $($AuthorName)&lt;br&gt;Message: $($Message)</description>
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
