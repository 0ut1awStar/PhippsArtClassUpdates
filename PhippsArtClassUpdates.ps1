# Class Data Monitor - Fetches webpage and sends Discord notifications
# Designed for automated cron job execution
# https://thephipps.org/classes/p/pottery#register

param(
    [string]$Url = "https://app.jackrabbitclass.com/jr3.0/Openings/OpeningsJS?OrgID=546477&sort=class&hidecols=description,gender,session,openings&Cat1=Art|Pottery&Cat2=Pottery",
    [string]$DiscordWebhook = <discordWebHook>,
    [string]$OutputCsv = "$PSScriptRoot\classes.csv",
    [string]$HistoryFile = "$PSScriptRoot\class_history.json",
    [string]$LogFile = "$PSScriptRoot\class_monitor.log",
    [switch]$SendFullTable
)

# === Utility Functions ===
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage
    Write-Host $logMessage
}

# Helper: unescape \uXXXX sequences then HTML-decode entities like &amp;
function Decode-UnicodeHtml {
    param([string]$s)
    if (-not $s) { return $s }
    try {
        $unescaped = [System.Text.RegularExpressions.Regex]::Unescape($s)
        return [System.Net.WebUtility]::HtmlDecode($unescaped)
    } catch {
        return $s
    }
}

function Fetch-WebPageContent {
    param([string]$Url)
    
    try {
        Write-Log "Fetching content from: $Url"
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30
        Write-Log "Successfully fetched webpage (Status: $($response.StatusCode))"
        return $response.Content
    }
    catch {
        Write-Log "Error fetching webpage: $_" -Level "ERROR"
        return $null
    }
}

function Extract-ClassData {
    param([string]$HtmlContent)
    
    $classes = @()
    $rowPattern = '<tr>.*?</tr>'
    $rows = [regex]::Matches($HtmlContent, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Write-Log "Found $($rows.Count) table rows to process"
    
    foreach ($row in $rows) {
        $rowHtml = $row.Value
        if ($rowHtml -notmatch 'data-title="Class".*?scope="row"') { continue }
        
        $titleMatch = [regex]::Match($rowHtml, 'data-title="Class"[^>]*>\s*([^<]+)\s*</th>')
        if (-not $titleMatch.Success) { continue }
        $classTitle = $titleMatch.Groups[1].Value.Trim()
        
        $daysMatch = [regex]::Match($rowHtml, 'data-title="Days"[^>]*>\s*([^<]+)\s*</td>')
        $timesMatch = [regex]::Match($rowHtml, 'data-title="Times"[^>]*>\s*([^<]+)\s*</td>')
        $agesMatch = [regex]::Match($rowHtml, 'data-title="Ages"[^>]*>\s*([^<]+)\s*</td>')
        $startMatch = [regex]::Match($rowHtml, 'data-title="Class Starts"[^>]*>\s*([^<]+)\s*</td>')
        $endMatch = [regex]::Match($rowHtml, 'data-title="Class Ends"[^>]*>\s*([^<]+)\s*</td>')
        $tuitionMatch = [regex]::Match($rowHtml, 'data-title="Tuition"[^>]*>\s*([^<]+)\s*</td>')
        $registerMatch = [regex]::Match($rowHtml, 'href="([^"]+)"[^>]*>(Register|Waitlist)</a>')
        
        $classes += [PSCustomObject]@{
            Class            = Decode-UnicodeHtml $classTitle
            Days             = if ($daysMatch.Success) { Decode-UnicodeHtml $daysMatch.Groups[1].Value.Trim() } else { "" }
            Times            = if ($timesMatch.Success) { Decode-UnicodeHtml $timesMatch.Groups[1].Value.Trim() } else { "" }
            Ages             = if ($agesMatch.Success) { Decode-UnicodeHtml $agesMatch.Groups[1].Value.Trim() } else { "" }
            ClassStarts      = if ($startMatch.Success) { Decode-UnicodeHtml $startMatch.Groups[1].Value.Trim() } else { "" }
            ClassEnds        = if ($endMatch.Success) { Decode-UnicodeHtml $endMatch.Groups[1].Value.Trim() } else { "" }
            Tuition          = if ($tuitionMatch.Success) { Decode-UnicodeHtml $tuitionMatch.Groups[1].Value.Trim() } else { "" }
            Status           = if ($registerMatch.Success) { Decode-UnicodeHtml $registerMatch.Groups[2].Value } else { "" }
            RegistrationLink = if ($registerMatch.Success) { Decode-UnicodeHtml $registerMatch.Groups[1].Value } else { "" }
        }
    }
    
    Write-Log "Extracted $($classes.Count) classes from webpage"
    return $classes
}

function Compare-ClassTitles {
    param(
        [array]$OldClasses,
        [array]$NewClasses
    )
    
    $changes = @{
        Added    = @()
        Removed  = @()
        Modified = @()
    }
    
    $oldTitles = $OldClasses | ForEach-Object { $_.Class }
    $newTitles = $NewClasses | ForEach-Object { $_.Class }
    
    foreach ($oldClass in $OldClasses) {
        if ($oldClass.Class -notin $newTitles) { $changes.Removed += $oldClass }
    }
    foreach ($newClass in $NewClasses) {
        if ($newClass.Class -notin $oldTitles) { $changes.Added += $newClass }
    }
    foreach ($newClass in $NewClasses) {
        $oldClass = $OldClasses | Where-Object { $_.Class -eq $newClass.Class } | Select-Object -First 1
        if ($oldClass) {
            $differences = @()
            if ($oldClass.Days -ne $newClass.Days) { $differences += "Days: '$($oldClass.Days)' -> '$($newClass.Days)'" }
            if ($oldClass.Times -ne $newClass.Times) { $differences += "Times: '$($oldClass.Times)' -> '$($newClass.Times)'" }
            if ($oldClass.Tuition -ne $newClass.Tuition) { $differences += "Tuition: `$$($oldClass.Tuition) -> `$$($newClass.Tuition)" }
            if ($oldClass.Status -ne $newClass.Status) { $differences += "Status: '$($oldClass.Status)' -> '$($newClass.Status)'" }
            if ($oldClass.ClassStarts -ne $newClass.ClassStarts) { $differences += "Start: '$($oldClass.ClassStarts)' -> '$($newClass.ClassStarts)'" }
            
            if ($differences.Count -gt 0) {
                $changes.Modified += [PSCustomObject]@{
                    Class    = $newClass
                    OldClass = $oldClass
                    Changes  = $differences
                }
            }
        }
    }
    return $changes
}

# === Discord Functions ===
function Send-DiscordNotification {
    param([string]$WebhookUrl,[array]$Embeds)
    if (-not $WebhookUrl -or $WebhookUrl -like "*YOUR_WEBHOOK*") { return }
    $payload = @{
        username   = "Class Monitor Bot"
        avatar_url = "https://cdn-icons-png.flaticon.com/512/2534/2534404.png"
        embeds     = $Embeds
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType "application/json" | Out-Null
    Write-Log "Discord notification sent successfully"
}

function Format-ClassEmbed {
    param([object]$Class,[int]$Color = 5814783)
    $fields = @(
        @{ name = "Days"; value = $Class.Days; inline = $true }
        @{ name = "Times"; value = $Class.Times; inline = $true }
        @{ name = "Ages"; value = $Class.Ages; inline = $true }
        @{ name = "Starts"; value = $Class.ClassStarts; inline = $true }
        @{ name = "Ends"; value = $Class.ClassEnds; inline = $true }
        @{ name = "Tuition"; value = "`$$($Class.Tuition)"; inline = $true }
    )
    if ($Class.Status) {
        # Status is either 'Register' or 'Waitlist' (or similar)
        $statusText = if ($Class.Status -match "(?i)register") { "Available" } elseif ($Class.Status -match "(?i)waitlist") { "Waitlist" } else { $Class.Status }
        $fields += @{ name = "Status"; value = $statusText; inline = $true }
    }
    $embed = @{
        title     = $Class.Class
        color     = $Color
        fields    = $fields
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    if ($Class.RegistrationLink) { $embed.url = $Class.RegistrationLink }
    return $embed
}

function Send-ClassTableToDiscord {
    param([array]$Classes,[string]$WebhookUrl)
    Write-Log "Sending full class table to Discord ($($Classes.Count) classes)"
    $embeds = @(
        @{
            title       = "Current Class Schedule"
            description = "Total classes available: **$($Classes.Count)**"
            color       = 3447003
            timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    )
    $displayCount = [Math]::Min(9, $Classes.Count)
    for ($i = 0; $i -lt $displayCount; $i++) {
        $embeds += Format-ClassEmbed -Class $Classes[$i] -Color 5814783
    }
    Send-DiscordNotification -WebhookUrl $WebhookUrl -Embeds $embeds
}

function Send-ChangesToDiscord {
    param([hashtable]$Changes,[string]$WebhookUrl)
    $embeds = @()
    $totalChanges = $Changes.Added.Count + $Changes.Removed.Count + $Changes.Modified.Count
    $embeds += @{
        title       = "Class Schedule Changes Detected"
        description = "**$totalChanges** changes found"
        color       = 16776960
        timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        fields      = @(
            @{ name = "Added"; value = $Changes.Added.Count; inline = $true }
            @{ name = "Removed"; value = $Changes.Removed.Count; inline = $true }
            @{ name = "Modified"; value = $Changes.Modified.Count; inline = $true }
        )
    }
    foreach ($class in $Changes.Added) {
    $embed = Format-ClassEmbed -Class $class -Color 3066993
    $embed.title = "NEW: " + $embed.title
        $embeds += $embed
    }
    foreach ($class in $Changes.Removed) {
    $embed = Format-ClassEmbed -Class $class -Color 15158332
    $embed.title = "REMOVED: " + $embed.title
        $embeds += $embed
    }
    foreach ($mod in $Changes.Modified) {
    $embed = Format-ClassEmbed -Class $mod.Class -Color 16776960
    $embed.title = "UPDATED: " + $embed.title
        $embed.fields += @{ name = "Changes"; value = ($mod.Changes -join "`n"); inline = $false }
        $embeds += $embed
    }
    Send-DiscordNotification -WebhookUrl $WebhookUrl -Embeds $embeds
}  # ✅ properly closed

# === Main Script ===
Write-Log "=== Class Data Monitor Started ==="

$htmlContent = Fetch-WebPageContent -Url $Url
if (-not $htmlContent) { Write-Log "Failed to fetch webpage content."; exit 1 }

$currentClasses = Extract-ClassData -HtmlContent $htmlContent
if ($currentClasses.Count -eq 0) { Write-Log "No classes found."; exit 1 }

$currentClasses | Export-Csv -Path $OutputCsv -NoTypeInformation -Force
Write-Log "Data exported to: $OutputCsv"

if (Test-Path $HistoryFile) {
    $previousClasses = Get-Content $HistoryFile -Raw | ConvertFrom-Json
    $changes = Compare-ClassTitles -OldClasses $previousClasses -NewClasses $currentClasses
    if ($changes.Added.Count -or $changes.Removed.Count -or $changes.Modified.Count) {
        Write-Log "*** CHANGES DETECTED ***"
        Send-ChangesToDiscord -Changes $changes -WebhookUrl $DiscordWebhook
    } else {
        Write-Log "No changes detected."
    }
} else {
    Write-Log "No history file found. Creating initial baseline."
    Send-ClassTableToDiscord -Classes $currentClasses -WebhookUrl $DiscordWebhook
}

if ($SendFullTable) {
    Write-Log "Sending full class table (manual flag)"
    Send-ClassTableToDiscord -Classes $currentClasses -WebhookUrl $DiscordWebhook
}

$currentClasses | ConvertTo-Json -Depth 10 | Out-File $HistoryFile -Force
Write-Log "History updated: $HistoryFile"
Write-Log "=== Class Data Monitor Completed ==="
