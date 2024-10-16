# script to check if new pottery classes are available for registration at the Phipps art center

# configurations
$updatesFile = "C:\THEPHIPPSBOT\ClassUpdates.txt"
$discordWebHook = "C:\THEPHIPPSBOT\DiscordWH.txt"
$siteUrl = "https://thephipps.org/classes/art"
$badHyphens = "\?\?\?"

# create file to store updates
if (!(Test-Path $updatesFile)) { New-Item -ItemType File -Path $updatesFile -Force }

# check for discord webhook
if (!(Test-Path $discordWebHook)) { Write-Host "No webhook configured in [$($discordWebHook)]"; exit }

# gather updates to compare
$updatesList = Get-Content -Path $updatesFile

function CheckSiteForUpdates {
    param($updatesList)

    $classes = @("Beginner", "Advanced", "Open-Studio")
    $classDates = @()
    $classFees =@()
    $regDates =@()
    $discordNotification = @()
    
    try {
        # get website content
        $siteContent = (Invoke-WebRequest -uri $siteUrl)
        
        # match dates from the three desired classes
        $classDates += $siteContent -match 'Beginner Pottery on the Wheel[\s\S]*?<p>(.*?)<br' | ForEach-Object { $Matches[1] }
        $classDates += $siteContent -match "Intermediate\/Advanced Pottery on the Wheel[\s\S]*?<p>(.*?)<br" | ForEach-Object { $Matches[1] }
        $classDates += $siteContent -match "Pottery Open Studio[\s\S]*?<p>(.*?)<br" | ForEach-Object { $Matches[1] }

        # match registration dates 
        $regDates += $siteContent -match 'Beginner Pottery on the Wheel[\s\S]*?(.egistration opens \w* 1\d*)' | ForEach-Object { $Matches[1] }
        $regDates += $siteContent -match "Intermediate\/Advanced Pottery on the Wheel[\s\S]*?(.egistration opens \w* 1\d*)" | ForEach-Object { $Matches[1] }
        $regDates += $siteContent -match "Pottery Open Studio[\s\S]*?(.egistration opens \w* 1\d*)" | ForEach-Object { $Matches[1] }

        # match class fees
        $classFees += $siteContent -match 'Beginner Pottery on the Wheel[\s\S]*?(Fee: \$\d*)' | ForEach-Object { $Matches[1] }
        $classFees += $siteContent -match "Intermediate\/Advanced Pottery on the Wheel[\s\S]*?(Fee: \$\d*)" | ForEach-Object { $Matches[1] }
        $classFees += $siteContent -match "Pottery Open Studio[\s\S]*?(Fee: \$\d*)" | ForEach-Object { $Matches[1] } 

        if ($classDates -match $badHyphens) { $classDates = $classDates -replace $badHyphens, '-' }
        
        # loop through class dates, checking for new ones
        for ($i = 0; $i -lt $classes.Count; $i++) {
            if (!($updatesList -match $classDates[$i])) { 
                Write-Host "New $($classes[$i]) class date: $($classDates[$i])"
                
                # append update to log file
                "$($classes[$i]) date: $($classDates[$i])" | Out-File -Append -LiteralPath $updatesFile

                # format notifcation text
                $notificationText = "$($classDates[$i])"
                if($regDates.count -gt 0) {$notificationText = $notificationText + "`n$($regDates[$i])"}
                if($classFees.count -gt 0) {$notificationText = $notificationText + "`n$($classFees[$i])"}

                # add update to discord notification
                $discordNotification += @{
                    name  = "$($classes[$i]) Class Update"
                    value = $notificationText
                }
            }
        }

        # send notification to discord
        if ($discordNotification) {
            $notificationBody = @{
                username   = "Phipps Notification Bot"
                avatar_url = "https://i.imgur.com/Tv1N1KS.png"
                embeds     = @(
                    @{
                        title  = "Phipps Center for the Arts Class Updates"
                        url    = $siteUrl
                        color  = 8913109
                        fields = $discordNotification
                    }
                )
            } | ConvertTo-Json -Depth 100
            Invoke-RestMethod -uri (Get-Content $discordWebHook) -Body $notificationBody -Method Post -ContentType "application/json"
        }
        else { Write-Host "No class updates found" }
    }
    catch {
        # Output any errors
        Write-Host -foregroundcolor Red "An error occurred: $_"
    }
}

# start program
CheckSiteForUpdates $updatesList


