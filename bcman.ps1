#region Welcome splash

Write-Host
Write-Host "                     ___                   __            __         "
Write-Host "      |\ |\         / _ )_______  ___ ____/ /______ ____/ /____ ____"
Write-Host "   |\ || || |\     / _  / __/ _ \/ _ ``/ _  / __/ _ ``(_-< __/ -_) __/"
Write-Host "   || || || ||    /____/__/ \___/\_,_/\_,_/\__/\_,_/___|__/\__/_/   "
Write-Host "   \| || || \|    /  |/  /__ ____  ___ ____ ____ ____             "
Write-Host "      \| \|      / /|_/ / _ ``/ _ \/ _ ``/ _ ``/ -_) __/             "
Write-Host "                /_/  /_/\_,_/_//_/\_,_/\_, /\__/_/                "
Write-Host "                                      /___/                       "
Write-Host -NoNewline " To quit at any time, press "
Write-Host -ForegroundColor:Yellow "Ctrl+C"
Write-Host

#endregion
#region Setup Broadcaster connection
function Get-BroadcasterUrl
{
    param($instr)
    if ($instr) { $instr = " $instr" }
    $input = Read-Host "> Enter the URL or hostname of the Broadcaster$instr"
    $input = $input.Trim().Split("https://")
    $input = $input[1] ?? $input[0]
    if ( $input.StartsWith("@")) {
        $input = $input.SubString(1)
    }
    elseif (!$input.StartsWith("broadcaster.")) {
        $input = "broadcaster.$input.heads-api.com"
    }
    if (!$input.StartsWith("https://")) {
        $input = "https://$input"
    }
    if (!$input.EndsWith("/api")) {
        $input += "/api"
    }
    $r = $null
    if (![System.Uri]::TryCreate($input, 'Absolute', [ref]$r)) {
        Write-Host "Invalid URI format. Try again."
        return Get-BroadcasterUrl
    }
    try {
        $options = irm $input -Method "OPTIONS" -TimeoutSec 5
        if (($options.Status -eq "success") -and ($options.Data[0].Resource -eq "RESTable.AvailableResource")) {
            return $input
        }
    }
    catch { }
    Write-Host "Found no Broadcaster API responding at $input. Ensure that the URL was input correctly and that the Broadcaster is running"
    return Get-BroadcasterUrl $instr
}

function Get-ApiKeyCredentials
{
    $apiKey = Read-Host "> Enter the API key to use" -AsSecureString
    return New-Object System.Management.Automation.PSCredential ("any", $apiKey)
}

function Pad
{
    param($item)
    $newItem = [ordered]@{ }
    $item.PSObject.Properties | % {
        $name = $_.name
        $val = ($_.value -eq $null) ? "" : $_.value.ToString()
        $newItem."$name" = $val + "  "
    }
    return [pscustomobject]$newItem
}

$bc = Get-BroadcasterUrl
$credentials = Get-ApiKeyCredentials

$getSettingsRaw = @{
    Method = "GET"
    Credential = $credentials
    Headers = @{ Accept = "application/json;raw=true" }
}
$getSettings = @{
    Method = "GET"
    Credential = $credentials
    Headers = @{ Accept = "application/json" }
}
$patchSettings = @{
    Method = "PATCH"
    Credential = $credentials
    Headers = @{ "Content-Type" = "application/json"; Accept = "application/json" }
}
$postSettings = @{
    Method = "POST"
    Credential = $credentials
    Headers = @{ "Content-Type" = "application/json"; Accept = "application/json" }
}
$postSettingsRaw = @{
    Method = "POST"
    Credential = $credentials
    Headers = @{ "Content-Type" = "application/json"; Accept = "application/json;raw=true" }
}
$deleteSettings = @{
    Method = "DELETE"
    Credential = $credentials
}

#endregion 
#region Lib
function Get-Batch
{
    param($bodyObj)
    $body = $null
    if ($bodyObj -is [string]) { $body = $bodyObj }
    else { $body = $bodyObj | ConvertTo-Json }
    try {
        return irm "$bc/Aggregator" @postSettingsRaw -Body $body
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-Host "Invalid API key. Ensure that the key has been given a proper access scope"
            exit
        }
        throw
    }
}

function Yes
{
    param($message)
    $val = Read-Host "$message (yes/no/cancel)"
    $val = $val.Trim()
    if ($val -eq "cancel") { return $null }
    if ($val -eq "yes") { return $true }
    if ($val -eq "no") { return $false }
    if ($val -eq "y") { return $true }
    if ($val -eq "n") { return $false }
    Write-Host "Invalid value, expected yes, no or cancel"
    return Yes $message
}
function Num
{
    param($message, $default)
    $val = Read-Host $message
    $val = $val.Trim();
    if ($val -eq '') { return $default }
    if ($val -as [int]) { return $val }
    Write-Host "Invalid value, expected a number"
    return Num $message
}
function InvalidFileName
{
    param([string]$name)
    return $name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ne -1
}
function Label
{
    param($existing)
    $label = ""
    if ($existing) {
        $label = Read-Host "> Enter the unique name of the manual client, e.g. Fynda Testmiljö"
    } else {
        $label = Read-Host "> Enter a unique name for the manual client, e.g. Fynda Testmiljö"
    }
    $label = $label.Trim()
    if ($label -eq '') {
        Write-Host "Invalid value, expected a name"
        return Label $existing
    }
    if (InvalidFileName $label) {
        Write-Host "Invalid value, $label contains characters that are invalid in a file name"
        return Label $existing
    }
    return $label
}
function Write-DashboardHeader
{
    param($name)
    Write-Host "### $name`: press " -NoNewline
    Write-Host "Space" -ForegroundColor Yellow -NoNewline
    Write-Host " to refresh, " -NoNewline
    Write-Host "Ctrl+C" -ForegroundColor Yellow -NoNewline
    Write-Host " to quit"
}
function Quit-Dashboard
{
    $originalMode = [System.Console]::TreatControlCAsInput
    [System.Console]::TreatControlCAsInput = $true
    try {
        while ($true) {
            $keyInfo = [System.Console]::ReadKey($true)
            $keyChar = $keyInfo.KeyChar
            $ctrlC = $keyInfo.Key -eq [System.ConsoleKey]::C -and $keyInfo.Modifiers -eq [System.ConsoleModifiers]::Control
            if ($ctrlC) { Write-Host "Received Ctrl+C, quitting..."; return $true }
            if ($keyChar -eq " ") { Write-Host "Refreshing..."; return $false }
        }
    }
    finally { [System.Console]::TreatControlCAsInput = $originalMode }
}
function Collation
{
    param($message)
    $val = Read-Host "$message (sv-SE, en-GB or nb-NO)"
    $val = $val.Trim().ToLower();
    if ($val -eq "sv-se") { return "sv-SE" }
    if ($val -eq "en-gb") { return "en-GB" }
    if ($val -eq "nb-no") { return "nb-NO" }
    Write-Host "Invalid collation, expected sv-SE, en-GB or nb-NO"
    return Collation $message
}
function Enter-Terminal
{
    param($terminal)
    Write-Host "Now entering a Broadcaster terminal. Send 'exit' to return to the Broadcaster Manager" -ForegroundColor Yellow
    $ws = New-Object Net.WebSockets.ClientWebSocket
    $ws.Options.Credentials = $credentials
    $ct = New-Object Threading.CancellationToken($false)
    $baseUrl = $bc.Split("://")[1]
    $connectTask = $ws.ConnectAsync("wss://$baseUrl/$terminal", $ct)
    do { Sleep(1) }
    until ($connectTask.IsCompleted)
    if ($ws.State -ne [Net.WebSockets.WebSocketState]::Open) {
        Write-Host "Connection failed!"
        return
    }
    $receiveJob = {
        param($ws, [scriptblock]$outputRedirect)
        $buffer = [Net.WebSockets.WebSocket]::CreateClientBuffer(1024, 1024)
        $ct = [Threading.CancellationToken]::new($false)
        $receiveTask = $null
        while ($ws.State -eq [Net.WebSockets.WebSocketState]::Open) {
            $result = ""
            do {
                $receiveTask = $ws.ReceiveAsync($buffer, $ct)
                while ((-not$receiveTask.IsCompleted) -and ($ws.State -eq [Net.WebSockets.WebSocketState]::Open)) {
                    [Threading.Thread]::Sleep(10)
                }
                $result += [Text.Encoding]::UTF8.GetString($buffer, 0, $receiveTask.Result.Count)
            } until (($ws.State -ne [Net.WebSockets.WebSocketState]::Open) -or ($receiveTask.Result.EndOfMessage))
            & $outputRedirect.Invoke($result)
        }
    }
    $receiver = [PowerShell]::Create()
    $outputRedirect = [scriptblock]{ param($res); $res | Out-Host }
    $receiver.AddScript($receiveJob).AddParameter("ws", $ws).AddParameter("outputRedirect", $outputRedirect).BeginInvoke() | Out-Null
    try {
        do {
            $input = Read-Host
            if ($input -ieq "exit") {
                return
            }
            $ct = New-Object Threading.CancellationToken($false)
            [ArraySegment[byte]]$message = [Text.Encoding]::UTF8.GetBytes($input)
            $ws.SendAsync($message, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult() | Out-Null
        } until ($ws.State -ne [Net.WebSockets.WebSocketState]::Open)
    }
    finally {
        $closetask = $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::Empty, "", $ct)
        do { Sleep(1) }
        until ($closetask.IsCompleted)
        $ws.Dispose()
        $receiver.Stop()
        $receiver.Dispose()
        Write-Host "Returning to Broadcaster Manager" -ForegroundColor Yellow
    }
}

function Get-Terminal
{
    $input = Read-Host "> Enter the name of the terminal, or 'list' to list all terminals"
    if ($input -ieq "list") {
        irm "$bc/AvailableResource/Kind=TerminalResource/select=Name" @getSettingsRaw | Out-Host
        return Get-Terminal
    }
    $input = $input.Trim()
    if ($input -eq "") {
        Write-Host "Invalid terminal name"
        return Get-WorkstationId
    }
    return $input
}

function Get-SoftwareProduct
{
    $input = Read-Host "> Enter software product name: WpfClient, PosServer, Receiver or 'cancel' to cancel"
    switch ( $input.Trim().ToLower()) {
        "receiver" { return "Receiver" }
        "wpfclient" { return "WpfClient" }
        "posserver" { return "PosServer" }
        "elephant" {
            Write-Host "Sorry, I can't really work with elephants ¯\_(ツ)_/¯ ... only squirrels, beavers and the occasional hedgehog"
            return Get-SoftwareProduct
        }
        "squirrel" {
            Write-Host "Squirrel, you say... let me look"
            Sleep 3
            Write-Host "... still looking ..."
            Sleep 4
            Write-Host "What did you want me to look for again?"
            return Get-SoftwareProduct
        }
        "beaver" {
            $global:beaver = $true
            Write-Host "OK, a beaver has been attached to the Broadcaster Manager. Use it with care!"
            return Get-SoftwareProduct
        }
        "hedgehog" {
            Write-Host "Fresh out of hedgehogs today. Try again later."
            return Get-SoftwareProduct
        }
        "cancel" { return $null }
        default {
            Write-Host "Unrecognized software product name $input"
            return Get-SoftwareProduct
        }
    }
}

function Create-WorkstationGroup
{
    $name = Read-Host "> Enter a name for the new workstation group"
    $existingGroups = irm "$bc/WorkstationGroups" @getSettingsRaw | Select-Object -first 1
    $groupExists = [bool]($existingGroups.PSobject.Properties.name -match $name)
    if ($groupExists) {
        Write-Host "A group with name $name already exists"
        return Create-WorkstationGroup
    }
    return $name
}

function Get-WorkstationGroup
{
    $input = Read-Host "> Enter the name of a workstation group, 'list' for available groups, 'new' to create one or 'cancel' to cancel"
    switch ( $input.Trim()) {
        "list" {
            Write-Host
            $groups = irm "$bc/WorkstationGroups" @getSettingsRaw | Select-Object -first 1
            $groups | Get-Member -MemberType NoteProperty | ForEach-Object {
                $_.Name | Out-Host
            }
            Write-Host
            return Get-WorkstationGroup
        }
        "new" { return Create-WorkstationGroup }
        "cancel" { return $null }
        "" {
            Write-Host "Invalid workstation group name"
            return Get-WorkstationGroup
        }
        default { return $input }
    }
}

function Get-WorkstationGroupMembers
{
    param($group)
    return (irm "$bc/WorkstationGroups/_/select=$group" @getSettingsRaw)[0].$group
}

function Add-WorkstationGroupMember
{
    param($group)
    $workstationId = Get-WorkstationId
    if (!$workstationId) {
        return
    }
    [string[]]$currentMembers = Get-WorkstationGroupMembers $group
    if (!$currentMembers) {
        $currentMembers = @()
    }
    $currentMembers += $workstationId
    $body = @{ $group = $currentMembers } | ConvertTo-Json
    $result = irm "$bc/WorkStationGroups" -Body $body @patchSettings
    if ($result.Status -eq "success") {
        Write-Host "$workstationId was added to group $group"
    }
    Add-WorkstationGroupMember $group
}

function Remove-WorkstationGroupMember
{
    param($group)
    $workstationId = Get-WorkstationId
    if (!$workstationId) {
        return
    }
    $currentMembers = Get-WorkstationGroupMembers $group
    if ($currentMembers) {
        $newMembers = @()
        foreach ($member in $currentMembers) {
            if ($member -ine $workstationId) {
                $newMembers += $member
            }
        }
        $body = @{ $group = $newMembers } | ConvertTo-Json
        $result = irm "$bc/WorkStationGroups" -Body $body @patchSettings
    }
    Write-Host "$workstationId was removed from the group $group"
    Add-WorkstationGroupMember $group
}

function Manage-WorkstationGroup
{
    param($group)
    $input = Read-Host "> Enter 'members' to list the members of $group, 'add' or 'remove' to edit members, 'delete' to delete the group or 'cancel' to cancel"
    switch ( $input.Trim().ToLower()) {
        "cancel" { return }
        "members" {
            $members = Get-WorkstationGroupMembers $group
            if ($members.Count -eq 0) {
                Write-Host "$group has no members"
            } else {
                Write-Host
                $members | Out-Host
                Write-Host
            }
            Manage-WorkstationGroup $group
        }
        "delete" {
            $body = @{ $group = $null } | ConvertTo-Json
            $result = irm "$bc/WorkStationGroups" -Body $body @patchSettings
            Write-Host "$group was deleted"
            return
        }
        "remove" {
            Remove-WorkstationGroupMember $group
            Manage-WorkstationGroup $group
        }
        "add" {
            Add-WorkstationGroupMember $group
            Manage-WorkstationGroup $group
        }
        default { Manage-WorkstationGroup $group }
    }
}

function Get-WorkstationId
{
    param($instr)
    if ($instr) { $instr = " $instr" }
    $input = Read-Host "> Enter workstation ID$instr, 'list' to list workstation IDs or 'cancel' to cancel"
    switch ( $input.Trim().ToLower()) {
        "list" {
            irm "$bc/ReceiverLog/_/select=WorkstationId" @getSettingsRaw | Out-Host
            return Get-WorkstationId $instr
        }
        "" {
            Write-Host "Invalid workstation ID format"
            return Get-WorkstationId $instr
        }
        "cancel" { return $null }
        default { return $input }
    }
}

function Get-RemoteFolder
{
    $input = Read-Host "> Enter a path to a folder on the build output share (e.g. retail/23.1)"
    switch ( $input.Trim().ToLower()) {
        "" {
            Write-Host "Invalid folder format"
            return Get-RemoteFolder
        }
        "cancel" { return $null }
        default { return $input }
    }
}

function Get-WorkstationIds
{
    $input = Read-Host "> Enter a comma-separated list of workstation IDs, * for all, 'list' to list workstation IDs or 'cancel' to cancel"
    switch ( $input.Trim().ToLower()) {
        "*" {
            $values = irm "$bc/ReceiverLog/_/select=WorkstationId" @getSettingsRaw
            [string[]]$ids = $( )
            foreach ($value in $values) {
                $ids += $value.WorkstationId
            }
            if ($ids.Length -ne 0) {
                return $ids
            }
            Write-Host "Received an empty list"
            return Get-WorkstationIds
        }
        "list" {
            irm "$bc/ReceiverLog/_/select=WorkstationId" @getSettingsRaw | Out-Host
            return Get-WorkstationIds
        }
        "" {
            Write-Host "Invalid workstation ID format"
            return Get-WorkstationIds
        }
        "cancel" { return $null }
        default {
            [string[]]$ids = $input.Split(',', [System.StringSplitOptions]::TrimEntries + [System.StringSplitOptions]::RemoveEmptyEntries)
            if ($ids.Length -ne 0) {
                return $ids
            }
            Write-Host "Received an empty list"
            return Get-WorkstationIds
        }
    }
}

function Get-DeployableSoftwareProductVersion
{
    param($softwareProduct)
    $message = "> Enter $softwareProduct version to deploy, 'list' for deployable versions of $softwareProduct or 'cancel' to cancel"
    $input = Read-Host $message
    $input = $input.Trim()
    if ($input -ieq "list") {
        $versions = irm "$bc/RemoteFile/ProductName=$softwareProduct&SoftwareItemType=DeployScript/order_asc=CreatedUTC&select=Version,CreatedUtc&distinct=true" @getSettings
        if ($versions.status -eq "success") {
            if ($versions.DataCount -eq 0) {
                Write-Host "Found no deployable versions of $softwareProduct"
            }
            else {
                $versions.data | % {
                    [pscustomobject]@{
                        Version = $_.Version.ToString()
                        "Build time" = $_.CreatedUtc.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                } | Out-Host
            }
        }
        else {
            Write-Host $versions.message
            Write-Host "An error occured while getting the deployable versions list for $softwareProduct. Please try again"
        }
        return Get-DeployableSoftwareProductVersion $softwareProduct
    }
    if ($input -ieq "cancel") {
        return $null
    }
    $r = $null
    if (![System.Version]::TryParse($input, [ref]$r)) {
        Write-Host "Invalid version format. Try again."
        return Get-DeployableSoftwareProductVersion $softwareProduct
    }
    return $r
}

function Get-LaunchableSoftwareProductVersion
{
    param($softwareProduct)
    $message = "> Enter $softwareProduct version to launch, 'list' for launchable versions of $softwareProduct or 'cancel' to cancel"
    $input = Read-Host $message
    $input = $input.Trim()
    if ($input -ieq "list") {
        $versions = irm "$bc/File/ProductName=$softwareProduct/order_asc=Version&select=Version&distinct=true" @getSettingsRaw
        if ($versions.Count -eq 0) {
            Write-Host "Found no launchable versions of $softwareProduct"
        }
        else {
            Write-Host
            foreach ($v in $versions) {
                Write-Host $v.Version
            }
            Write-Host
        }
        return Get-LaunchableSoftwareProductVersion $softwareProduct
    }
    if ($input -ieq "cancel") {
        return $null
    }
    $r = $null
    if (![System.Version]::TryParse($input, [ref]$r)) {
        Write-Host "Invalid version format. Try again."
        return Get-LaunchableSoftwareProductVersion $softwareProduct
    }
    return $r
}

function Get-LaunchedSoftwareProductVersion
{
    param($softwareProduct)
    $versions = irm "$bc/LaunchSchedule/ProductName=$softwareProduct/select=Version&order_asc=Version&distinct=true" @getSettingsRaw
    if ($versions.Count -eq 0) {
        Write-Host "Found no launched versions of $softwareProduct"
        return $null
    }
    $latest = ($versions | select -first 1).Version
    $message = "> Enter $softwareProduct version to use, 'list' for launched versions of $softwareProduct, enter for latest ($latest) or 'cancel' to cancel"
    $input = Read-Host $message
    $input = $input.Trim()
    if ($input -ieq "") {
        return $latest
    }
    if ($input -ieq "list") {
        $versions = irm "$bc/LaunchSchedule/ProductName=$softwareProduct/select=Version&order_asc=Version&distinct=true" @getSettingsRaw
        Write-Host
        foreach ($v in $versions) {
            Write-Host $v.Version
        }
        Write-Host
        return Get-LaunchedSoftwareProductVersion $softwareProduct
    }
    if ($input -ieq "cancel") {
        return $null
    }
    $r = $null
    if (![System.Version]::TryParse($input, [ref]$r)) {
        Write-Host "Invalid version format. Try again."
        return Get-LaunchedSoftwareProductVersion $softwareProduct
    }
    return $r
}

function Get-RuntimeId
{
    param($softwareProduct, $instr)
    if ($instr) { $instr = " $instr" }
    $message = "> Enter runtime ID for the version$instr, press enter for 'win7-x64' or 'cancel' to cancel"
    $input = Read-Host $message
    $input = $input.Trim()
    if ($input -ieq "") {
        return "win7-x64"
    }
    if ($input -ieq "cancel") {
        return $null
    }
    else {
        return $input
    }
}

function Get-DateTime
{
    $input = Read-Host "> Enter date and time for the launch, press enter for now, 'examples' for examples or 'cancel' to cancel"
    $input = $input.Trim()
    if ($input -ieq "") {
        return Get-Date -AsUTC
    }
    if ($input -ieq "examples") {
        Write-Host "> The following input formats are accepted (examples):"
        Write-Host
        Write-Host "Local time:    " -NoNewline
        Write-Host "2023-04-30 15:00" -ForegroundColor Yellow
        Write-Host "UTC time:      " -NoNewline
        Write-Host "UTC 2023-04-30 13:00" -ForegroundColor Yellow
        Write-Host "Relative time: " -NoNewline
        Write-Host "+03:30" -NoNewline -ForegroundColor Yellow
        Write-Host " (in 3.5 hours)" -ForegroundColor Gray
        Write-Host
        $hostname = hostname
        Write-Host "Local times are expressed in the time-zone of your computer ($hostname)" -ForegroundColor Green
        return Get-DateTime
    }
    if ($input -ieq "cancel") {
        return $null
    }
    if ( $input.StartsWith("+")) {
        if (!$input.Contains(':')) {
            $input = $input + ":00"
        }
        $timeSpan = [TimeSpan] $input.Substring(1).Trim()
        return (Get-Date -AsUtc).Add($timeSpan)
    }
    $isUtc = $false
    if ( $input.StartsWith("UTC")) {
        $isUtc = $true
        $input = $input.Substring(3).Trim()
    }
    $dateTime = $null
    try {
        if ($input.Length -lt 10) {
            throw ""
        }
        if ($isUtc) {
            # The date is already in UTC, no conversion needed
            return Get-Date ($input) -Format "yyyy-MM-dd HH:mm"
        }
        # The date is not in UTC, convert to UTC using -AsUTC
        return Get-Date ($input) -AsUTC -Format "yyyy-MM-dd HH:mm"
    }
    catch {
        Write-Host "Invalid date and time format. Enter 'examples' for examples"
        return Get-DateTime
    }
}

function Get-LaunchSchedule
{
    $launches = irm "$bc/LaunchSchedule" @getSettingsRaw
    if ($launches.Count -eq 0) {
        Write-Host "Found no scheduled lauches"
    }
    else {
        $i = 1
        $items = @()
        foreach ($l in $launches | Sort-Object -Property "DateTime") {
            $items += [PSCustomObject]@{
                Id = $i
                ProductName = $l.ProductName
                Version = $l.Version
                RuntimeId = $l.RuntimeId
                DateTime = $l.DateTime
            }
            $i += 1
        }
        $items | Format-Table | Out-Host
        $input = Read-Host "> Enter 'delete' to delete a scheduled launch or press enter to continue"
        if ($input -ieq "delete") {
            $input = Read-Host "> Enter the Id of the scheduled launch to delete or 'cancel' to cancel"
            $input = $input.Trim()
            if ($input -ieq "cancel") {
            }
            else {
                $foundMatch = $false
                foreach ($item in $items) {
                    if ($item.Id -eq $input) {
                        $foundMatch = $true
                        $productName = $item.ProductName
                        $version = $item.Version
                        $runtimeId = $item.RuntimeId
                        $dateTicks = $item.DateTime.Ticks
                        $result = irm "$bc/LaunchSchedule/ProductName=$productName&Version=$version&RuntimeId=$runtimeId&DateTime.Ticks=$dateTicks/unsafe=true" @deleteSettings
                        if ($result.status -eq "success") {
                            if ($result.DeletedCount -gt 0) {
                                Write-Host "Successfully deleted scheduled launch with Id $input"
                                Start-Sleep -Seconds 1
                            } else {
                                Write-Host "An error occured while trying to delete scheduled launch with Id $input"
                            }
                        }
                        else {
                            Write-Host "An error occured while trying to delete scheduled launch with Id $input"
                            Write-Host $result
                        }
                        break
                    }
                }
                if (!$foundMatch) {
                    Write-Host "Found no scheduled launch with Id $input"
                }
                Get-LaunchSchedule
            }
        }
    }
}
#endregion
#region Status
$getStatusCommands = @(
@{
    Command = "Status"
    Description = "Prints a status overview of the Broadcaster"
    Action = {
        try {
            $results = Get-Batch @{
                Config = "GET /Config/_/select=Version,ComputerName&rename=General.CurrentVersion->Version"
                NextVersion = "GET /BroadcasterUpdate/_/order_desc=Version&limit=1"
                Notifications = "GET /NotificationLog"
            }
            $version = $results.Config[0].Version
            $hostName = $results.Config[0].ComputerName
            $nextVersion = $null
            $nextVersion = $results.NextVersion | select -First 1 -Exp Version
            $notifications = $results.Notifications

            Write-Host
            Write-Host "• Connected to: " -NoNewLine
            Write-Host $hostName -ForegroundColor Green
            Write-Host "• Broadcaster version: " -NoNewLine
            Write-Host $version -ForegroundColor Green
            if ($nextVersion) {
                Write-Host "• A new version: "  -NoNewline
                Write-Host $nextVersion -ForegroundColor Green -NoNewline
                Write-Host " is available (see " -NoNewline
                Write-Host "update" -ForegroundColor Yellow -NoNewline
                Write-Host ")"
            }
            $notificationsCount = $notifications.Length
            Write-Host "• You have " -NoNewline
            $color = "Green"
            if ($notificationsCount -gt 0) { $color = "Red" }
            $subject = " notification"
            if ($notificationsCount -gt 1) { $subject = "$subject`s" }
            Write-Host $notificationsCount -ForegroundColor $color -NoNewLine
            Write-Host $subject -NoNewline
            if ($notificationsCount -gt 0) {
                Write-Host " (see " -NoNewline
                Write-Host "notifications" -ForegroundColor Yellow -NoNewline
                Write-Host ")"
            }
            Write-Host
        }
        catch {
            Write-Host
        }
    }
}
@{
    Command = "ReceiverStatus"
    Description = "Prints the status for all connected Receivers"
    Action = {
        $list = irm "$bc/Receiver/_/select=WorkstationId,LastActive" @getSettingsRaw
        if ($list.Count -eq 0) { Write-Host "Found no connected Receivers" }
        else { $list | Sort-Object -Property "WorkstationId" | Out-Host }
    }
}
@{
    Command = "ReceiverLog"
    Description = "Prints the last recorded status for all connected and disconnected Receivers"
    Action = {
        $list = irm "$bc/ReceiverLog/_/select=WorkstationId,LastActive" @getSettingsRaw
        if ($list.Count -eq 0) { Write-Host "Found no connected or disconnected Receivers" }
        else { $list | Sort-Object -Property "WorkstationId" | Out-Host }
    }
}
@{
    Command = "Config"
    Description = "Prints the configuration of the Broadcaster"
    Action = {
        irm "$bc/Config" @getSettingsRaw | Out-Host
    }
}
@{
    Command = "DeploymentInfo"
    Description = "Prints details about deployed software versions on the Broadcaster"
    Action = {
        $list = irm "$bc/File/_/select=ProductName,Version&distinct=true" @getSettingsRaw
        if ($list.Count -eq 0) { Write-Host "Found no deployed software versions" }
        else { $list | Sort-Object -Property "ProductName" | Out-Host }
    }
}
@{
    Command = "VersionInfo"
    Description = "Prints details about a the installed software on Receivers"
    Action = $versioninfo_c = {
        $softwareProduct = Get-SoftwareProduct
        if (!$softwareProduct) {
            return
        }
        $response = irm "$bc/ReceiverLog/modules.$softwareProduct.isinstalled=true" @getSettingsRaw
        if ($response.Count -eq 0) {
            Write-Host "Found no connected or disconnected Receivers"
            return
        }
        $response | % {
            [pscustomobject]@{
                WorkstationId = $_.WorkstationId
                LastActive = $_.LastActive
                IsRunning = $_.Modules.$softwareProduct.IsRunning
                CurrentVersion = $_.Modules.$softwareProduct.CurrentVersion
                DeployedVersions = $_.Modules.$softwareProduct.DeployedVersions | Join-String -Separator ", "
                LaunchedVersion = $_.Modules.$softwareProduct.LaunchedVersion
            }
        } | Sort-Object -Property "WorkstationId" | % { Pad $_ } | Format-Table | Out-Host
        & $versioninfo_c
    }
}
@{
    Command = "ManualClientInfo"
    Description = "Prints details about the installed manual WPF clients on Receivers"
    Action = $manualclientinfo_c = {
        $response = irm "$bc/ReceiverLog/Modules.WpfClient.ExternalClients.Count>0" @getSettingsRaw
        if ($response.Count -eq 0) {
            Write-Host "Found no client computers with installed manual WPF Clients"
            return
        }
        Write-Host
        foreach ($item in $response) {
            Write-Host "WorkstationId: $( $item.WorkstationId )"
            Write-Host "Manual clients:"
            $item.Modules.WpfClient.ExternalClients | % {
                Write-Host "  InstallDir: $( $_.InstallDir )"
                Write-Host "  Version: $( $_.Version )"
                Write-Host "  IsVersionTracked: $( $_.IsVersionTracked )"
                Write-Host
            }
        }
    }
}
@{
    Command = "ReplicationInfo"
    Description = "Prints details about the replication status of Receivers"
    Action = {
        $response = irm "$bc/ReceiverLog/modules.replication.isactive=true" @getSettingsRaw
        if ($response.Count -eq 0) {
            Write-Host "Found no connected or disconnected Receivers"
            return
        }
        $response | % {
            [pscustomobject]@{
                WorkstationId = $_.WorkstationId
                LastActive = $_.LastActive
                ReplicationVersion = $_.Modules.Replication.ReplicationVersion
                AwaitsInitialization = $_.Modules.Replication.AwaitsInitialization
            }
        } | Sort-Object -Property "WorkstationId" | % { Pad $_ } | Out-Host
    }
}
@{
    Command = "ReceiverDetails"
    Description = "Prints the last known details about a specific Receiver (connected or disconnected)"
    Action = $receiverDetails_c = {
        $workstationId = Get-WorkstationId
        if (!$workstationId) {
            return
        }
        $response = irm "$bc/ReceiverLog/WorkstationId=$workstationId/select=Modules" @getSettingsRaw | Select-Object -first 1
        if (!$response) {
            Write-Host "Found no Receiver with workstation ID $workstationId"
            & $receiverDetails_c
        }
        else {
            Write-Host
            $response.Modules.PSObject.Properties | Sort-Object -Property "Name" | ForEach-Object {
                Write-Host ($_.Name + ":") -ForegroundColor Yellow
                Write-Host
                $value = $_.Value | select -ExcludeProperty "@Type", "ProductName"
                $ht = @{ }
                $value.PSObject.Properties | Foreach { $ht[$_.Name] = $_.Value }
                if (($ht.Count -eq 0) -and ($_.Name -eq "Downloads")) {
                    Write-Host "No download tasks"
                }
                else {
                    foreach ($key in $ht.Keys | Sort-Object) {
                        $id = $ht[$key] | ConvertTo-Json
                        Write-Host "$key`: $id"
                    }
                }
                Write-Host
            }
        }
    }
}
@{
    Command = "Notifications"
    Description = "Prints details about current Broadcaster notifications"
    Action = $notifications_c = {
        $response = irm "$bc/NotificationLog" @getSettings
        if ($response.DataCount -eq 0) {
            Write-Host "The are currently no notifications. Enjoy your day :)"
            return
        }
        $numId = 0
        [pscustomobject[]]$notifications = $response.Data | % {
            [pscustomobject]@{
                Id = ($numId += 1)
                Source = $_.Source
                Message = $_.Message
                TimestampUtc = $_.TimestampUtc.ToString("yyyy-MM-dd HH:mm:ss")
                Hash = $_.Id
            }
        }
        $notifications | % { Pad $_ } | Format-Table -AutoSize | Out-Host
        $id = Read-Host "> Enter the ID of a notification to clear it, or enter to continue"
        $id = $id.Trim() -as [int]
        if ($id -gt 0) {
            $match = $notifications | ? { $_.Id -eq $id }
            if (!$match) {
                Write-Host "Found no notification with ID $id"
            }
            else {
                # The hash is used as ID on the Broadcaster
                $result = irm "$bc/NotificationLog/Id=$( $match.Hash )" @deleteSettings
                if ($result.Status -eq "success") {
                    Write-Host "Notification cleared"
                } else {
                    Write-Host "An error occurred while clearing notification with ID $id"
                }
                sleep 0.3
            }
            & $notifications_c
        }
    }
}

)
#endregion
#region Status
#endregion
#region Dashboarda
$dashboardCommands = @(
@{
    Command = "SoftwareDashboard"
    Description = "Presents a live dashboard of the software status of clients"
    Action = {
        Write-Host "This command is under development..."
        return
        $softwareProduct = Get-SoftwareProduct
        if (!$softwareProduct) {
            return
        }
        $body = @{
            ReceiverLog = "GET /ReceiverLog"
            CurrentVersions = "GET /LaunchSchedule.CurrentVersions"
            Files = "GET /File/ProductName=$softwareProduct/select=Version&distinct=true"
        } | ConvertTo-Json

        $num = 0
        while ($true) {

            # Egenskaper att tracka:
            # - En modul åt gången
            # - R (receiver), W (wpf client), P (POS Server), C (CustomerServiceApplication) 
            # - View modes
            #       Deployment statis D – har deployat senaste versionen (as defined in /File)
            #       Launch status L - har launchat senaste versionen
            # - 
            # - Har launchat senaste launchad version (as defined in /LaunchSchedule)


            $data = Get-Batch $body
            $listData = $data.ReceiverLog | % {
                $status = "Up to date"
                [pscustomobject]@{
                    Status = "`e[32m$status`e[0m"
                    WorkstationId = $_.WorkstationId
                    LastActive = $_.LastActive
                    ReplicationVersion = $_.Replication.ReplicationVersion
                    AwaitsInitialization = $_.Replication.AwaitsInitialization
                    Version = $_.Modules.$softwareProduct.Version
                }
            }
            cls
            Write-DashboardHeader "DeploymentDashboard"
            $listData | % { Pad $_ } | Format-Table | Out-Host
            if (Quit-Dashboard) { return }
        }
    }
}
)
#endregion
#region Remote deployment
$remoteDeploymentCommands = @(
@{
    Command = "ISM"
    Description = "Starts Install Script Maker"
    Action = {
        Write-Host "Now starting ISM. Use " -NoNewLine
        Write-Host -ForegroundColor:Yellow "Ctrl+C" -NoNewLine
        Write-Host " to return to Broadcaster Manager"
        irm raw.githubusercontent.com/byheads/util/main/ism | iex
        Write-Host
        Write-Host "Returning to Broadcaster Manager..."
        Write-Host
    }
}
@{
    Command = "Install"
    Description = "Install or reinstall software on client computers through the Receiver"
    Action = $install_c = {
        [string[]]$workstationIds = Get-WorkstationIds "for the clients to install software for"
        if (!$workstationIds) {
            return
        }
        $workstationIds | Out-Host
        $softwareProduct = Get-SoftwareProduct
        if (!$softwareProduct) {
            return
        }
        $version = Get-LaunchedSoftwareProductVersion $softwareProduct
        if (!$version) {
            return
        }
        $runtimeId = Get-RuntimeId "to install"
        if (!$runtimeId) {
            return
        }
        $pms = @{ }
        $data = @{
            Workstations = $workstationIds
            Product = $softwareProduct
            Version = $version
            Runtime = $runtimeId
            Parameters = $pms
        }
        switch ($softwareProduct) {
            "WpfClient" {
                if (Yes "> Install as a manual client?") {
                    $bcUrl = Get-BroadcasterUrl "to get the manual client from"
                    $bcUrl = $bcUrl.Substring(0, ($bcUrl.Length - 4))
                    $data.BroadcasterUrl = $bcUrl
                    $data.InstallToken = Read-Host "> Enter the install token to use" -MaskInput
                    $label = Label
                    $pms.shortcutLabel = [System.Uri]::EscapeDataString("Heads Retail - $label")
                    $pms.installPath = [System.Uri]::EscapeDataString("C:\ProgramData\Heads\$label")
                }
                $pms.usePosServer = (Yes "> Connect client to local POS Server?")
                $pms.useArchiveServer = (Yes "> Connect client to central Archive Server?")
            }
            "PosServer" {
                $pms.createDump = (Yes "> Create a dump of an existing POS-server?")
                $pms.collation = (Collation "> Enter database collation, e.g. sv-SE")
                $pms.imageSize = (Num "> Enter database image size in MB (or enter for 1024)" 1024)
                $pms.logSize = (Num "> Enter database log size in MB (or enter for 1024)" 1024)
            }
            default {
                Write-Host "Can't remote-install $softwareProduct"
                & $install_c
                return
            }
        }
        $body = $data | ConvertTo-Json
        Write-Host "> This will install $softwareProduct on $( $workstationIds.Count ) workstations:"
        Write-Host $workstationIds
        if (Yes "> Do you want to proceed?") {
            Write-Host "Now installing. This could take a while, be patient..."
        }
        else {
            Write-Host "Aborted"
            return
        }
        $result = irm "$bc/RemoteInstall" @postSettings -Body $body
        if ($result.Status -eq "success") {
            Write-Host
            Write-Host "RESULTS:" -ForegroundColor Yellow
            Write-Host
            foreach ($item in $result.Data) {
                $id = $item.ExecutedScript.ExecutedBy
                if ($id -eq $item.WorkstationId) {
                    $id = $item.WorkstationId
                }
                Write-Host "$id`: " -NoNewline
                if ($item.ExecutedScript.ExecutedSuccessfully) {
                    Write-Host "Success" -ForegroundColor Green
                } else {
                    Write-Host "Failed" -ForegroundColor Red
                    Write-Host $item.ExecutedScript.Errors
                }
            }
            Write-Host
            Write-Host "Note that the new state of installed software may take a minute to update" -ForegroundColor Yellow
            Write-Host
        }
        else {
            Write-Host "An error occurred while remote-installing $softwareProduct"
        }
    }
}
@{
    Command = "Uninstall"
    Description = "Uninstall software on client computers through the Receiver"
    Action = $uninstall_c = {
        [string[]]$workstationIds = Get-WorkstationIds "for the clients to uninstall software for"
        if (!$workstationIds) {
            return
        }
        $data = @{
            Workstations = $workstationIds
        }
        if (Yes "> Uninstall legacy software?") {
            $data.Legacy = $true
        } else {
            $softwareProduct = Get-SoftwareProduct
            if (!$softwareProduct) {
                return
            }
            switch ($softwareProduct) {
                "WpfClient" {
                    if (Yes "> Uninstall a manual client?") {
                        $data.ManualClientName = Label $true
                    }
                }
                "PosServer" { }
                default {
                    Write-Host "Can't remote-uninstall $softwareProduct"
                    & $uninstall_c
                    return
                }
            }
            $data.Product = $softwareProduct
        }
        $body = $data | ConvertTo-Json

        Write-Host "> This will uninstall $( $data.Product ?? "legacy software" ) on $( $data.Workstations.Count ) workstations:"
        Write-Host $workstationIds
        if (!(Yes "> Do you want to proceed?")) {
            Write-Host "Aborted"
            return
        }
        $result = irm "$bc/RemoteUninstall" @postSettings -Body $body
        if ($result.Status -eq "success") {
            Write-Host
            Write-Host "RESULTS:" -ForegroundColor Yellow
            Write-Host
            foreach ($item in $result.Data) {
                $id = $item.ExecutedScript.ExecutedBy
                if ($id -eq $item.WorkstationId) {
                    $id = $item.WorkstationId
                }
                Write-Host "$id`: " -NoNewline
                if ($item.ExecutedScript.ExecutedSuccessfully) {
                    Write-Host "Success" -ForegroundColor Green
                } else {
                    Write-Host "Failed" -ForegroundColor Red
                    Write-Host $item.ExecutedScript.Errors
                }
            }
            Write-Host
            Write-Host "Note that the new state of installed software may take a minute to update" -ForegroundColor Yellow
            Write-Host
        }
        else {
            Write-Host "An error occurred while remote-uninstalling $softwareProduct"
        }
        & $uninstall_c
    }
}
@{
    Command = "Reset"
    Description = "Resets one or more POS server databases, optionally also closing their day journals"
    Action = {
        Write-Host "> This feature has not been tested and might not work as expected. Press enter to confirm and continue" -ForegroundColor Red
        Read-Host
        [string[]]$workstationIds = Get-WorkstationIds
        Write-Host "> Selected these workstations for reset:"
        Write-Host
        $workstationIds | Out-Host
        Write-Host
        $closeDayJournal = Yes "> Should we close relevant day journals before resetting these workstations?"
        if ($closeDayJournal -eq $null) {
            return
        }
        if ($closeDayJournal) {
            $posUser = Read-Host "> Enter the user name to call the POS-server APIs with when closing the day journals or 'cancel' to cancel"
            $posUser = $posUser.Trim()
            if ($posUser -ieq "cancel") {
                return
            }
            $posPassword = Read-Host "> Enter that user's password or 'cancel' to cancel" -MaskInput
            if ($posPassword -ieq "cancel") {
                return
            }
        }
        $confirm = Read-Host "> Ready to reset the selected workstations. Enter 'reset' to reset them now or 'cancel' to cancel"
        $confirm = $confirm.Trim()
        if ($confirm -ine "reset") {
            Write-Host "Aborting reset"
            return
        }
        $body = @{ Workstations = $workstationIds; SkipDayJournal = !$closeDayJournal; PosUser = $posUser; PosPassword = $posPassword; } | ConvertTo-Json
        $result = irm "$bc/Reset" -Body $body @postSettingsRaw -TimeoutSec 60
        $result | Select-Object -ExpandProperty ExecutedScript | Select-Object -Property ("ExecutedBy", "Information", "Errors", "ExecutedSuccessfully") | Format-Table | Out-Host
    }
}
@{
    Command = "Control"
    Description = "Start or stop services and applications on client computers"
    Action = $control_c = {
        Write-Host
        Write-Host "This command can do the following:"
        Write-Host
        Write-Host "Start" -ForegroundColor Yellow -NoNewline
        Write-Host " POS Servers if not already running"
        Write-Host "Stop" -ForegroundColor Yellow -NoNewline
        Write-Host " POS Servers and WPF Clients"
        Write-Host "Restart" -ForegroundColor Yellow -NoNewline
        Write-Host " running Receivers and POS Servers"
        Write-Host

        $command = Read-Host "> Enter a remote command: 'start', 'stop' or 'restart' or 'cancel' to cancel"
        $command = $command.Trim()
        if ($command -ieq "cancel") {
            return
        }
        if (!($command -in "start", "stop", "restart")) {
            Write-Host "Invalid remote command '$command'"
            & $control_c
            return
        }
        $softwareProduct = Get-SoftwareProduct
        if (!$softwareProduct) {
            return
        }
        if ($command -in ("start", "restart") -and $softwareProduct -eq "WpfClient") {
            Write-Host "Can't start or restart WPF Clients"
            & $control_c
            return
        }
        if ($command -in ("start", "stop") -and $softwareProduct -eq "Receiver") {
            Write-Host "Can't start or stop the Receiver"
            & $control_c
            return
        }
        [string[]]$workstationIds = Get-WorkstationIds "for the clients to control"
        if (!$workstationIds) {
            return
        }
        $data = @{
            Workstations = $workstationIds
            Command = $command
            Product = $softwareProduct
        }
        $body = $data | ConvertTo-Json
        Write-Host "> This will $command $softwareProduct on $( $workstationIds.Count ) workstations:"
        Write-Host $workstationIds
        if (Yes "> Do you want to proceed?") {
            Write-Host "Running command. This could take a while, be patient..."
        }
        else {
            Write-Host "Aborted"
            return
        }
        $result = irm "$bc/RemoteControl" @postSettings -Body $body -ErrorAction SilentlyContinue
        if ($result.Status -eq "success") {
            Write-Host
            Write-Host "RESULTS:" -ForegroundColor Yellow
            Write-Host
            foreach ($item in $result.Data) {
                $id = $item.ExecutedScript.ExecutedBy
                if ($id -eq $item.WorkstationId) {
                    $id = $item.WorkstationId
                }
                Write-Host "$id`: " -NoNewline
                if ($item.ExecutedScript.ExecutedSuccessfully) {
                    Write-Host "Success" -ForegroundColor Green
                } else {
                    Write-Host "Failed" -ForegroundColor Red
                    Write-Host $item.ExecutedScript.Errors
                }
            }
            Write-Host
        }
        else {
            Write-Host "An error occurred while remote-controlling the clients"
        }
    }
}
)
#endregion
#region Modify
$modifyCommands = @(
@{
    Command = "Forget"
    Description = "Removes the Receiver log entry for a given workstation"
    Action = $forget_c = {
        $workstationId = Get-WorkstationId "for the client that should be forgotten"
        if (!$workstationId) {
            return
        }
        $result = irm "$bc/ReceiverLog/WorkstationId=$workstationId" @deleteSettings
        if ($result.Status -eq "success") {
            if ($result.DeletedCount -gt 0) { Write-Host "$workstationId was forgotten" }
            else { Write-Host "Found no Receiver log entry with workstation ID $workstationId" }
        }
        else { Write-Host "An error occurred while removing a Receiver log entry for workstation with ID $workstationId" }
        & $forget_c
    }
}
@{
    Command = "Deploy"
    Description = "Lists and downloads deployable software versions to the Broadcaster"
    Action = $deploy_c = {
        $softwareProduct = Get-SoftwareProduct
        if (!$softwareProduct) {
            return
        }
        $version = Get-DeployableSoftwareProductVersion $softwareProduct
        if (!$version) {
            return
        }
        $ma = $version.Major; $mi = $version.Minor; $b = $version.Build; $r = $version.Revision
        $versionConditions = "version.major=$ma&version.minor=$mi&version.build=$b&version.revision=$r"
        Write-Host "Downloading $softwareProduct $version to the Broadcaster. Be patient..."
        $body = @{ Deploy = $true } | ConvertTo-Json
        $result = irm "$bc/RemoteFile/ProductName=$softwareProduct&$versionConditions/unsafe=true" -Body $body @patchSettings
        if ($result.Status -eq "success") {
            if ($result.DataCount -eq 0) {
                Write-Host "No version was deployed. Please ensure that version $version of $softwareProduct is deployable."
                & $deploy_c
            } else {
                Write-Host "$softwareProduct $version was successfully deployed!"
            }
        }
        else {
            Write-Host "An error occured while deploying $softwareProduct $version. This version might be partially deployed. Partially deployed versions are not deployed to clients"
            Write-Host $result
        }
    }
}
@{
    Command = "Launch"
    Description = "Lists launchable software versions and schedules launches"
    Action = $launch_c = {
        $message = "> Enter 'list' to list and edit scheduled launches, 'schedule' to schedule a new launch or 'cancel' to cancel"
        $input = Read-Host $message
        if ($input -ieq "list") {
            Get-LaunchSchedule
            & $launch_c
            return
        }
        if ($input -ieq "schedule") {
            $softwareProduct = Get-SoftwareProduct
            if (!$softwareProduct) {
                return
            }
            $version = Get-LaunchableSoftwareProductVersion $softwareProduct
            if (!$version) {
                return
            }
            $runtimeId = Get-RuntimeId "to launch"
            if (!$runtimeId) {
                return
            }
            $datetime = Get-DateTime
            if (!$datetime) {
                return
            }
            $body = @{
                ProductName = $softwareProduct
                Version = $version.ToString()
                RuntimeId = $runtimeId
                DateTime = [datetime]$datetime
            } | ConvertTo-Json
            $result = irm "$bc/LaunchSchedule" -Body $body @postSettings
            if ($result.Status -eq "success") {
                if ($result.DataCount -eq 0) {
                    Write-Host "No new launch was scheduled. There is likely an earlier launch with the same or a higher version."
                    & $launch_c
                } else {
                    Write-Host "A launch was successfully scheduled"
                    & $launch_c
                }
            }
            else {
                Write-Host "An error occured while scheduling launch"
                Write-Host $result
                & $launch_c
            }
        }
        if ($input -ieq "cancel") {
            return
        }
    }
}
@{
    Command = "RemoteFolders"
    Description = "Lists and assigns remote folders on the build output share, from where the BC can deploy client software versions"
    Action = $remotefolders_c = {
        $input = Read-Host "> Enter 'list' to list the remote folders, 'add' or 'remove' to edit the list or 'cancel' to cancel"
        switch ( $input.Trim().ToLower()) {
            "cancel" { return }
            "list" {
                [string[]]$folders = (irm "$bc/RemoteFile.Settings/_/select=RemoteDirectories" @getSettingsRaw).RemoteDirectories
                if ($folders.Count -eq 0) {
                    Write-Host "There are no assigned remote directories"
                } else {
                    Write-Host
                    $folders | Out-Host
                    Write-Host
                }
                & $remotefolders_c
            }
            "add" {
                $folder = Get-RemoteFolder
                [string[]]$folders = (irm "$bc/RemoteFile.Settings/_/select=RemoteDirectories" @getSettingsRaw).RemoteDirectories
                $folders += $folder
                $body = @{ RemoteDirectories = $folders } | ConvertTo-Json
                $result = irm "$bc/RemoteFile.Settings" -Body $body @patchSettings
                if ($result.Status -eq "success") {
                    Write-Host "$folder was added" -ForegroundColor Green
                } else {
                    Write-Host "An error occured while adding $folder to the assigned remote folder list"
                }
                & $remotefolders_c
            }
            "remove" {
                $folder = Get-RemoteFolder
                [System.Collections.Generic.List[string]]$folders = (irm "$bc/RemoteFile.Settings/_/select=RemoteDirectories" @getSettingsRaw).RemoteDirectories
                $removed = $folders.Remove($folder)
                if (!$removed) {
                    Write-Host "$folder is not an assigned remote folder"
                    & $remotefolders_c
                }
                else {
                    $body = @{ RemoteDirectories = $folders } | ConvertTo-Json
                    $result = irm "$bc/RemoteFile.Settings" -Body $body @patchSettings
                    if ($result.Status -eq "success") {
                        Write-Host "$folder was removed"  -ForegroundColor Green
                    } else {
                        Write-Host "An error occured while removing $folder from the assigned remote folder list"
                    }
                }
                & $remotefolders_c
            }
            default { & $remotefolders_c }
        }
    }
}
@{
    Command = "Groups"
    Description = "Lists and assigns workstation group members"
    Action = $groups_c = {
        $group = Get-WorkstationGroup
        if (!$group) {
            return
        }
        Manage-WorkstationGroup $group
        & $groups_c
    }
}
@{
    Command = "Update"
    Description = "Updates the Broadcaster to a new version"
    Action = {
        $version = (irm "$bc/Config/_/select=Version&rename=General.CurrentVersion->Version" @getSettingsRaw)[0].Version
        $nextAvailable = (irm "$bc/BroadcasterUpdate/_/order_desc=Version&limit=1" @getSettingsRaw)[0]
        if (!$nextAvailable) {
            Write-Host "> This Broadcaster is already running the latest version " -NoNewline
            Write-Host $version -ForegroundColor Green -NoNewline
            Write-Host
            return
        }
        Write-Host "> This Broadcaster is running version " -NoNewline
        Write-Host $version -ForegroundColor Yellow -NoNewline
        Write-Host ". A new version " -NoNewline
        Write-Host $nextAvailable.Version -ForegroundColor Green -NoNewline
        Write-Host " is available!"
        $response = Read-Host "> Enter 'update' to update and restart the Broadcaster right now or 'cancel' to cancel"
        $response = $response.Trim().ToLower()
        if ($response -ieq "update") {
            $fullName = [System.Uri]::EscapeDataString($nextAvailable.FullName)
            $body = @{ Install = $true } | ConvertTo-Json
            $result = irm "$bc/BroadcasterUpdate/FullName=$fullName" -Body $body @patchSettings
            Write-Host "> Updating Broadcaster to version " -NoNewline
            Write-Host $nextAvailable.Version -ForegroundColor Green -NoNewline
            Write-Host " " -NoNewline
            while ($true) {
                Write-Host "." -NoNewline -ForegroundColor Gray
                $interval = Start-Sleep 2 &
                try {
                    $currentVersion = (irm "$bc/Config/_/select=Version&rename=General.CurrentVersion->Version" -TimeoutSec 2 @getSettingsRaw -ErrorAction SilentlyContinue)[0].Version
                    if ($currentVersion -eq $nextAvailable.Version) {
                        Write-Host " Done!" -ForegroundColor Green -NoNewline
                        Write-Host
                        break
                    }
                }
                catch { }
                Receive-Job $interval -Wait
            }
        }
    }
}
)
#endregion
#region Terminals
$launchTerminalsCommands = @(
@{
    Command = "LaunchCommands"
    Description = "Enters the Broadcaster LaunchCommands terminal"
    Action = { Enter-Terminal "LaunchCommands" }
}
@{
    Command = "AccessToken"
    Description = "Enters the Broadcaster access token terminal"
    Action = { Enter-Terminal "AccessToken.Commands" }
}
@{
    Command = "Shell"
    Description = "Enters the Broadcaster shell terminal"
    Action = { Enter-Terminal "Shell" }
}
@{
    Command = "Terminal"
    Description = "Enters a Broadcaster terminal"
    Action = { Enter-Terminal (Get-Terminal) }
}
)
#endregion
#region Other
$global:fireworks = $false
$otherCommands = @(
@{ Command = "Help"; Description = "Prints the commands list"; Action = { WriteAll-Commands } }
@{
    Command = "Exit"
    Description = "Closes the Broadcaster Manager"
    Action = {
        if ($global:beaver) {
            Write-Host "> Detaching beaver. Be patient..."
            Start-Sleep 3
            Write-Host "> The beaver has been safely detached"
        }
        Write-Host "> Exiting..."
        Exit
    }
}
@{
    Command = "Fireworks"
    Description = "Perfect for various celebrations"
    Action = {
        if ($global:fireworks) {
            Write-Host "Less celebration, more motivation! You've had your fun..."
            Start-Sleep 1
            return
        }
        $global:fireworks = $true
        cls
        Write-Host
        Write-Host
        Start-Sleep 1
        cls
        Write-Host
        Write-Host
        Write-Host "       ####### " -ForegroundColor Red
        Write-Host "      ##     ##" -ForegroundColor Red
        Write-Host "             ##" -ForegroundColor Red
        Write-Host "       ####### " -ForegroundColor Red
        Write-Host "             ##" -ForegroundColor Red
        Write-Host "      ##     ##" -ForegroundColor Red
        Write-Host "       ####### " -ForegroundColor Red
        Write-Host
        Write-Host
        Start-Sleep 1
        cls
        Write-Host
        Write-Host
        Write-Host "       ####### " -ForegroundColor Yellow
        Write-Host "      ##     ##" -ForegroundColor Yellow
        Write-Host "             ##" -ForegroundColor Yellow
        Write-Host "       ####### " -ForegroundColor Yellow
        Write-Host "      ##       " -ForegroundColor Yellow
        Write-Host "      ##       " -ForegroundColor Yellow
        Write-Host "      #########" -ForegroundColor Yellow
        Write-Host
        Write-Host
        Start-Sleep 1
        cls
        Write-Host
        Write-Host
        Write-Host "          ##   " -ForegroundColor Green
        Write-Host "        ####   " -ForegroundColor Green
        Write-Host "          ##   " -ForegroundColor Green
        Write-Host "          ##   " -ForegroundColor Green
        Write-Host "          ##   " -ForegroundColor Green
        Write-Host "          ##   " -ForegroundColor Green
        Write-Host "        ###### " -ForegroundColor Green
        Write-Host
        Write-Host
        Start-Sleep 1
        cls
        Write-Host
        Write-Host "               *    *" -ForegroundColor Red
        Write-Host "   *         `'       *       .  *   `'     .           * *" -ForegroundColor Yellow
        Write-Host "                                                               `'" -ForegroundColor Red
        Write-Host "       *                *`'          *          *        `'" -ForegroundColor Green
        Write-Host "   .           *               |               /" -ForegroundColor Red
        Write-Host "               `'.         |    |      `'       |   `'     *" -ForegroundColor Yellow
        Write-Host "                 \*        \   \             /" -ForegroundColor Green
        Write-Host "       `'          \     `'* |    |  *        |*                *  *" -ForegroundColor Red
        Write-Host "            *      ``.       \   |     *     /    *      `'" -ForegroundColor Blue
        Write-Host "  .                  \      |   \          /               *" -ForegroundColor Yellow
        Write-Host "     *`'  *     `'      \      \   `'.       |" -ForegroundColor Red
        Write-Host "        -._            ``                  /         *" -ForegroundColor Blue
        Write-Host "  `' `'      ````._   *                           `'          .      `'" -ForegroundColor Green
        Write-Host "   *           *\*          * .   .      *" -ForegroundColor Yellow
        Write-Host "*  `'        *    ``-._                       .         _..:=`'        *" -ForegroundColor Red
        Write-Host "             .  `'      *       *    *   .       _.:--`'" -ForegroundColor Blue
        Write-Host "          *           .     .     *         .-`'         *" -ForegroundColor Green
        Write-Host "   .               `'             . `'   *           *         ." -ForegroundColor Red
        Write-Host "  *       ___.-=--..-._     *                `'               `'" -ForegroundColor Yellow
        Write-Host "                                  *       *" -ForegroundColor Red
        Write-Host "                *        _.`'  .`'       ``.        `'  *             *" -ForegroundColor Blue
        Write-Host "     *              *_.-`'   .`'            ``.               *" -ForegroundColor Green
        Write-Host "                   .`'                       ``._             *  `'" -ForegroundColor Yellow
        Write-Host "   `'       `'                        .       .  ``.     ." -ForegroundColor Green
        Write-Host "       .                      *                  ``" -ForegroundColor Blue
        Write-Host "               *        `'             `'                          ." -ForegroundColor Red
        Write-Host "     .                          *        .           *  *" -ForegroundColor Yellow
        Write-Host "             *        .                                    `'" -ForegroundColor Green
        Write-Host
        if ($global:beaver) {
            Write-Host "The beaver is going wild!"
        }
        Start-Sleep 2
        cls
        Write-Host
        Write-Host "OK, that's it. Back to work!"
        Write-Host
    }
}
)
function Write-Commands
{
    param($commands)
    $list = @()
    foreach ($c in $commands | Sort-Object -Property Command) {
        $list += [pscustomobject]@{
            Command = $c.Command + "    "
            Description = $c.Description
        }
    }
    $list | Format-Table | Out-Host
}

function WriteAll-Commands
{
    Write-Host
    Write-Host "STATUS:" -ForegroundColor Yellow
    Write-Commands $getStatusCommands
    Write-Host "MODIFY:" -ForegroundColor Yellow
    Write-Commands $modifyCommands
    Write-Host "DASHBOARDS:" -ForegroundColor Yellow
    Write-Commands $dashboardCommands
    Write-Host "REMOTE DEPLOYMENT:" -ForegroundColor Yellow
    Write-Commands $remoteDeploymentCommands
    Write-Host "TERMINALS:" -ForegroundColor Yellow
    Write-Commands $launchTerminalsCommands
    Write-Host "OTHER:" -ForegroundColor Yellow
    Write-Commands $otherCommands
}

function Write-HelpInfo
{
    Write-Host "> Use " -NoNewline
    Write-Host "help" -NoNewLine -ForegroundColor Yellow
    Write-Host " to list all commands"
}

$allCommands = $getStatusCommands + $modifyCommands + $remoteDeploymentCommands + $dashboardCommands + $launchTerminalsCommands + $otherCommands

function Call($command)
{
    $foundCommand = $false
    foreach ($c in $allCommands) {
        if ($c.Command -ieq $command) {
            $foundCommand = $true
            & $c.Action
        }
    }
    if (!$foundCommand) {
        Write-Host "> Unknown command $input"
        Write-HelpInfo
        Start-Sleep 1
    }
}

#endregion
#region Read-eval loop

Call "Status"
Write-HelpInfo
Write-Host

while ($true) {
    $input = Read-Host "> Enter a command"
    if ($input -eq "") {
        continue
    }
    $command = $input.Trim().ToLower()
    if ($command -ieq "hi" -or $command -ieq "hello") {
        Write-Host "Well hello there!"
        continue
    }
    if ($command -ieq "help") {
        WriteAll-Commands
        continue
    }
    Call $command
}

#endregion
