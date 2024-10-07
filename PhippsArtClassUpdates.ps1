# script to check if new pottery classes are available for registration at the Phipps art center

# configurations
$updatesFile = "C:\THEPHIPPSBOT\ClassUpdates.txt"
$siteUrl = "https://thephipps.org/classes/art"
$discordWebHook = Get-Content "C:\THEPHIPPSBOT\DiscordWH.txt"

# create file to store updates
if (!(Test-Path $updatesFile)) { New-Item -ItemType File -Path $updatesFile -Force }

# gather updates to compare
$updatesList = Get-Content -Path $updatesFile

function CheckSiteForUpdates {
    param($updatesList)

    $classes = @("Beginner", "Advanced", "Open-Studio")
    $classDates = @()
    $discordNotification = @()

    # get website content
    $siteContent = Invoke-WebRequest -UseBasicParsing -uri $siteUrl
    
    # match dates from the three desired classes
    $classDates += $siteContent -match "Beginner Pottery on the Wheel[\s\S]*?([\w]*\s\d*-[\w]*\s\d*)" | ForEach-Object { $Matches[1] }
    $classDates += $siteContent -match "Intermediate\/Advanced Pottery on the Wheel[\s\S]*?([\w]*\s\d*-[\w]*\s\d*)" | ForEach-Object { $Matches[1] }
    $classDates += $siteContent -match "Pottery Open Studio[\s\S]*?([\w]*\s\d*-[\w]*\s\d*)" | ForEach-Object { $Matches[1] }

    # loop through class dates, checking for new ones
    for ($i = 0; $i -lt $classes.Count; $i++) {
        if (!($updatesList -match $classDates[$i])) { 
            Write-Host "New $($classes[$i]) class dates: $($classDates[$i])"
            
            # append update to log file
            "$($classes[$i]) date: $($classDates[$i])" | Out-File -Append -LiteralPath $updatesFile

            # add update to discord notification
            $discordNotification += @{
                name  = "$($classes[$i]) Class Update"
                value = $classDates[$i]
            }
        }
    }

    # send notification to discord
    if ($discordNotification) {
        $notificationBody = @{
            username = "Phipps Notification Bot"
            avatar_url = "https://i.imgur.com/Tv1N1KS.png"
            embeds = @(
                @{
                    title  = "Phipps Center for the Arts Class Updates"
                    url    = $siteUrl
                    color  = 8913109
                    fields = $discordNotification
                }
            )
        } | ConvertTo-Json -Depth 100
        Invoke-RestMethod -uri $discordWebHook -Body $notificationBody -Method Post -ContentType "application/json"
    }
}

# start program
CheckSiteForUpdates $updatesList


