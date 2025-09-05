param($injectedUrl, $injectedKey, $initialCommand)
$OutputEncoding = [System.Text.Encoding]::UTF8
if ($PSVersionTable.PSVersion.Major -lt 7) {
    return "Broadcaster Manager requires PowerShell 7 or later"
}
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
function Try-Url
{
    param($url)
    if ( $url.StartsWith("http://")) {
        # Using unencrypted HTTP
        Write-Host "> You are using an unencrypted Broadcaster connection. Use Ctrl+C to abort..." -ForegroundColor Yellow
        $PSDefaultParameterValues['Invoke-RestMethod:AllowUnencryptedAuthentication'] = $true
    }
    try {
        $options = irm $url -Method "OPTIONS" -TimeoutSec 5
        if (($options.Status -eq "success") -and ($options.Data[0].Resource -eq "RESTable.AvailableResource")) {
            return $true
        }
    }
    catch { }
    Write-Host "Found no Broadcaster API responding at $url. Ensure that the URL was input correctly and that the Broadcaster is running."
    return $false
}

function Get-BroadcasterUrl
{
    param($instr)
    if ($instr) { $instr = " $instr" }
    $input = Read-Host "> Enter the URL or hostname of the Broadcaster$instr"
    $input = $input.Trim()
    if ( $input.StartsWith("@")) { $input = $input.SubString(1) }
    elseif (!$input.StartsWith("http")) {
        if ( $input.Contains(".")) { $input = "https://$input" }
        else { $input = "https://broadcaster.$input.heads-api.com" }
    }
    if (!$input.EndsWith("/api")) {
        $input += "/api"
    }
    $r = $null
    if (![System.Uri]::TryCreate($input, 'Absolute', [ref]$r)) {
        Write-Host "Invalid URI format. Try again."
        return Get-BroadcasterUrl
    }
    if (Try-Url $input) {
        return $input
    }
    return Get-BroadcasterUrl $instr
}

function Get-BroadcasterUrl-Ism
{
    $input = Read-Host "> Enter the URL or hostname of the Broadcaster (or 'enter' to use this Broadcaster)"
    $input = $input.Trim()
    if ($input -eq "") {
        Write-Host "> Using URL $bc"
        return $bc
    }
    if ( $input.StartsWith("@")) {
        $input = $input.SubString(1)
    }
    elseif (!$input.StartsWith("http")) {
        if ( $input.Contains(".")) { $input = "https://$input" }
        else { $input = "https://broadcaster.$input.heads-api.com" }
    }
    if (!$input.EndsWith("/api")) {
        $input += "/api"
    }
    $r = $null
    if (![System.Uri]::TryCreate($input, 'Absolute', [ref]$r)) {
        Write-Host "Invalid URI format. Try again."
        return Get-BroadcasterUrl
    }
    if ( $input.StartsWith("http://")) {
        Write-Host "> You are using an unencrypted Broadcaster connection. Use Ctrl+C to abort..." -ForegroundColor Yellow
        $PSDefaultParameterValues['Invoke-RestMethod:AllowUnencryptedAuthentication'] = $true
    }
    try {
        $options = irm $input -Method "OPTIONS" -TimeoutSec 5
        if (($options.Status -eq "success") -and ($options.Data[0].Resource -eq "RESTable.AvailableResource")) {
            Write-Host "That Broadcaster exists! 🎉" -ForegroundColor Green
            return $input
        }
    }
    catch { }
    Write-Host "Warning: Could not verify if a Broadcaster exists at $input" -ForegroundColor Yellow
    return $input
}

function Get-ApiKeyCredentials
{
    $apiKey = Read-Host "> Enter the API key to use" -AsSecureString
    return [PSCredential]::new("any", $apiKey)
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

$bc = ""
if ($injectedUrl) {
    $bc = $injectedUrl
    if (!$bc.EndsWith("/api")) {
        $bc += "/api"
    }
    if (!(Try-Url $bc)) {
        return "Invalid URL given as argument"
    }
}
else {
    $bc = Get-BroadcasterUrl
}
$credentials = $null
if ($injectedKey) {
    if ($injectedKey -is [System.Security.SecureString]) {
        $credentials = [PSCredential]::new("any", $injectedKey)
    } else {
        return "Invalid API key given as argument. Expected an instance of System.Security.SecureString"
    }
}
else {
    $credentials = Get-ApiKeyCredentials
}

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
        if ($_.Exception.Response.StatusCode -in 401, 403) {
            Write-Host "Invalid API key for $bc. Ensure that the key has been given the required access scope." -ForegroundColor Red
            exit
        }
        throw
    }
}

function Yes
{
    param($message)
    $val = Read-Host "$message (yes/no)"
    $val = $val.Trim()
    if ($val -eq "yes") { return $true }
    if ($val -eq "no") { return $false }
    if ($val -eq "y") { return $true }
    if ($val -eq "n") { return $false }
    Write-Host "Invalid value, expected yes or no"
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
    if ($name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ne -1) {
        return $true
    }
    if ( $name.Contains(".")) {
        return $true
    }
    return $false
}
function Label
{
    param($existing)
    $label = ""
    if ($existing) {
        $label = Read-Host "> Enter the unique name of the manual client, e.g. Heads Testmiljö"
    } else {
        $label = Read-Host "> Enter a unique name for the manual client, e.g. Heads Testmiljö"
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
function Write-RemoteResult
{
    param($result)
    if ($result.Status -eq "success" -and $result.DataCount -gt 0) {
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
                Write-Host "Failed" -ForegroundColor Red -NoNewline
                Write-Host " – " -NoNewline
                Write-Host $item.ExecutedScript.Errors
            }
        }
    }
    else {
        throw $result
    }
}
function Write-DashboardHeader
{
    param($name, $context, $filterActive)
    Write-Host "`e[1;93m$name`e[0m" -NoNewline
    if ($context) {
        Write-Host " for " -NoNewline
        Write-Host $context -ForegroundColor Yellow -NoNewline

    }
    Write-Host " – " -NoNewline
    Write-Host "Space" -ForegroundColor Yellow -NoNewline
    Write-Host " to refresh, " -NoNewline
    Write-Host "Ctrl+C" -ForegroundColor Yellow -NoNewline
    Write-Host " to quit, " -NoNewline
    Write-Host "`e[1m`e[97mI`e[92mnitial`e[0m to sort (again to toggle)" -NoNewline
    if ($filterActive -ne $null) {
        Write-Host ", `e[1m`e[97mF`e[92m`e[0m toggles " -NoNewline
        if ($filterActive) { Write-Host "`e[1m`e[93mPOS filter`e[0m" }
        else { Write-Host "POS filter" }
    } else {
        Write-Host
    }
}
function Get-DashboardInput
{
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$args
    )
    $originalMode = [System.Console]::TreatControlCAsInput
    [System.Console]::TreatControlCAsInput = $true
    try {
        while ($true) {
            $keyInfo = [System.Console]::ReadKey($true)
            $keyChar = $keyInfo.KeyChar
            $ctrlC = $keyInfo.Key -eq [System.ConsoleKey]::C -and $keyInfo.Modifiers -eq [System.ConsoleModifiers]::Control
            if ($ctrlC) {
                Write-Host "Received Ctrl+C, quitting...";
                Write-Host;
                return "quit"
            }
            if ($keyChar -eq " ") {
                Write-Host "Refreshing...";
                return "refresh"
            }
            if ($args -contains $keyChar) {
                return $keyChar
            }
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
                while ((-not $receiveTask.IsCompleted) -and ($ws.State -eq [Net.WebSockets.WebSocketState]::Open)) {
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
                Write-Host "Returning to Broadcaster Manager" -ForegroundColor Yellow
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
    $input = Read-Host "> Enter a software product name, 'list' for all names or 'cancel' to cancel"
    switch ( $input.Trim().ToLower()) {
        "list"{
            Write-Host
            "Receiver", "WpfClient", "PosServer", "CustomerServiceApplication" | Out-Host
            Write-Host
            return Get-SoftwareProduct
        }
        "receiver" { return "Receiver" }
        "wpfclient" { return "WpfClient" }
        "posserver" { return "PosServer" }
        "customerserviceapplication" { return "CustomerServiceApplication" }
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
function Add-WorkstationGroupMembers
{
    param($group)
    $workstationIds = Get-WorkstationIds
    if (!$workstationIds) {
        return
    }
    [string[]]$currentMembers = Get-WorkstationGroupMembers $group
    if (!$currentMembers) {
        $currentMembers = @()
    }
    $currentMembers += $workstationIds
    $body = @{ $group = $currentMembers } | ConvertTo-Json
    $result = irm "$bc/WorkStationGroups" -Body $body @patchSettings
    if ($result.Status -eq "success") {
        $count = $workstationIds.Count
        Write-Host "$count workstation(s) were added to group $group"
    }
}
function Remove-WorkstationGroupMember
{
    param($group)
    $toRemove = Get-WorkstationIds
    if (!$toRemove) {
        return
    }
    [string[]]$currentMembers = Get-WorkstationGroupMembers $group
    if ($currentMembers) {
        $newMembers = @()
        foreach ($member in $currentMembers) {
            if ($toRemove -notcontains $member) {
                $newMembers += $member
            }
        }
        $body = @{ $group = $newMembers } | ConvertTo-Json
        $result = irm "$bc/WorkStationGroups" -Body $body @patchSettings
    }
    $count = $toRemove.Count
    Write-Host "$count workstation(s) were removed from the group $group"
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
            Add-WorkstationGroupMembers $group
            Manage-WorkstationGroup $group
        }
        default { Manage-WorkstationGroup $group }
    }
}
function Get-WorkstationId
{
    param($instr)
    if ($instr) { $instr = " $instr" }
    $workstationIds = irm "$bc/ReceiverLog/_/select=WorkstationId" @getSettingsRaw | % { $_.WorkstationId }
    if ($workstationIds.Count -eq 0) {
        Write-Host "Found no connected or disconnected Receivers"
        return $null
    }
    $input = Read-Host "> Enter workstation ID$instr, 'list' to list workstation IDs or 'cancel' to cancel"

    switch ( $input.Trim().ToLower()) {
        "list" {
            Write-Host
            $workstationIds | Out-Host
            Write-Host
            return Get-WorkstationId $instr
        }
        "" {
            Write-Host "Invalid workstation ID format"
            return Get-WorkstationId $instr
        }
        "cancel" { return $null }
        default {
            if ($workstationIds -notcontains $input) {
                Write-Host "Found no workstation with ID $input"
                return Get-WorkstationId $instr
            }
            return $input
        }
    }
}
function Get-RetailVersion
{
    $input = Read-Host "> Enter the name of a Retail version (e.g. 22.3 or 23.400)"
    switch ( $input.Trim().ToLower()) {
        "" {
            Write-Host "Invalid retail version format"
            return Get-RetailVersion
        }
        "cancel" { return $null }
        default {
            if ( $input.StartsWith("@")) {
                return $input.Substring(1)
            }
            if ($input -notmatch '^\d{2}\.\d{1,3}$') {
                $revisionPattern = '^\d{2}\.\d{1,3}\.\d{1,4}\.[1-9]\d*$'
                if ($input -notmatch $revisionPattern) {
                    Write-Host "Invalid retail version format"
                    return Get-RetailVersion
                }
            }
            return $input
        }
    }
}
function Get-WorkstationIds
{
    param($instr)
    if ($instr) { $instr = " $instr" }
    $workstationIds = irm "$bc/ReceiverLog/_/select=WorkstationId" @getSettingsRaw | % { $_.WorkstationId }
    if ($workstationIds.Count -eq 0) {
        Write-Host "Found no connected or disconnected Receivers"
        return $null
    }
    $input = Read-Host "> Enter a comma-separated list of workstation IDs$instr, * for all, 'list' to list workstation IDs or 'cancel' to cancel"
    switch ( $input.Trim().ToLower()) {
        "*" { return $workstationIds }
        "list" {
            Write-Host
            $workstationIds | Out-Host
            Write-Host
            return Get-WorkstationIds
        }
        "" {
            Write-Host "Invalid workstation ID format"
            return Get-WorkstationIds
        }
        "cancel" { return $null }
        default {
            [string[]]$ids = $input.Split(',', [System.StringSplitOptions]::TrimEntries + [System.StringSplitOptions]::RemoveEmptyEntries)
            foreach ($id in $ids) {
                if ($workstationIds -notcontains $id) {
                    Write-Host "Found no workstation with ID $id"
                    return Get-WorkstationIds $instr
                }
            }
            if ($ids.Length -eq 0) {
                Write-Host "Received an empty list"
                return Get-WorkstationIds
            }
            return $ids
        }
    }
}
function Get-DeployableSoftwareProductVersion
{
    param($softwareProduct)
    $message = "> Enter version to deploy, 'list' for all deployable versions or 'cancel' to cancel"
    $input = Read-Host $message
    $input = $input.Trim()
    if ($input -ieq "list") {
        $versions = irm "$bc/RemoteFile/ProductName=$softwareProduct&SoftwareItemType=DeployScript/order_asc=CreatedUTC&select=Version,CreatedUtc" @getSettings
        if ($versions.status -eq "success") {
            if ($versions.DataCount -eq 0) {
                Write-Host "Found no deployable versions of $softwareProduct"
            }
            else {
                $versions.data | Group-Object 'Version' | % { $_.Group | Select -Last 1 } | % {
                    [pscustomobject]@{
                        Version = $_.Version.ToString()
                        "Build time" = $_.CreatedUtc.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                } | % { Pad $_ } | Out-Host
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
    $versions = irm "$bc/File/ProductName=$softwareProduct/order_asc=Version&select=Version&distinct=true" @getSettingsRaw | % { $_.Version }
    if ($versions.Count -eq 0) {
        Write-Host "Found no launchable versions of $softwareProduct"
        return $null
    }
    $message = "> Enter $softwareProduct version to launch, 'list' for launchable versions of $softwareProduct or 'cancel' to cancel"
    $input = Read-Host $message
    $input = $input.Trim()
    if ($input -ieq "list") {
        Write-Host
        foreach ($v in $versions) {
            Write-Host $v
        }
        Write-Host
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
    if ($versions -notcontains $r) {
        Write-Host "Version $r is not launchable"
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
    param($prompt)
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
        if ($input.Length -lt 10 -or $input[4] -ne '-') {
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
function Update-Dependencies
{
    $body = @{ Install = $true } | ConvertTo-Json
    Write-Host "> Downloading dependencies... " -NoNewline
    $result = irm "$bc/DependencyUpdate" -Body $body @patchSettings
    if ($result.Status -eq "success") {
        Write-Host "Done!"
    } else {
        Write-Host
        Write-Host "> An error occurred while updating dependencies" -ForegroundColor Red
        $result | Out-Host
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
                    ReplicationFilter = "GET /ReplicationFilter"
                }
                $version = $results.Config[0].Version
                $hostName = $results.Config[0].ComputerName
                $nextVersion = $null
                $nextVersion = $results.NextVersion | select -First 1 -Exp Version -ErrorAction SilentlyContinue
                $notifications = $results.Notifications -as [System.Collections.IEnumerable]
                $filter = $results.ReplicationFilter -as [System.Collections.IEnumerable]
                Write-Host
                Write-Host "`u{2022} Connected with URL: " -NoNewline
                Write-Host $bc
                if ($hostname) {
                    Write-Host "`u{2022} Connected to: " -NoNewLine
                    Write-Host $hostName -ForegroundColor Green
                }
                if ($version) {
                    Write-Host "`u{2022} Broadcaster version: " -NoNewLine
                    Write-Host $version -ForegroundColor Green
                }
                if ($nextVersion) {
                    Write-Host "`u{2022} A new version: "  -NoNewline
                    Write-Host $nextVersion -ForegroundColor Magenta -NoNewline
                    Write-Host " is available (see " -NoNewline
                    Write-Host "update" -ForegroundColor Yellow -NoNewline
                    Write-Host ")"
                }
                if ($notifications) {
                    $notificationsCount = $notifications.Length
                    Write-Host "`u{2022} You have " -NoNewline
                    $color = "Green"
                    if ($notificationsCount -gt 0) { $color = "Yellow" }
                    $subject = " notification"
                    if ($notificationsCount -ne 1) { $subject = "$subject`s" }
                    Write-Host $notificationsCount -ForegroundColor $color -NoNewLine
                    Write-Host $subject -NoNewline
                    if ($notificationsCount -gt 0) {
                        Write-Host " (see " -NoNewline
                        Write-Host "notifications" -ForegroundColor Yellow -NoNewline
                        Write-Host ")"
                    }
                }
                if ($filter) {
                    if ($filter.AllowAll) { }
                    elseif ($filter.AllowNone) {
                        Write-Host "`u{2022} " -NoNewline
                        Write-Host "Replication disabled for all recipients " -ForegroundColor Red -NoNewline
                        Write-Host "(see " -NoNewline
                        Write-Host "replicationfilter" -ForegroundColor Yellow -NoNewline
                        Write-Host ")"
                    }
                    else {
                        Write-Host "`u{2022} " -NoNewline
                        Write-Host "Replication is currently enabled " -NoNewline
                        Write-Host "only for some" -ForegroundColor Yellow -NoNewline
                        Write-Host " recipients (see " -NoNewline
                        Write-Host "replicationfilter" -ForegroundColor Yellow -NoNewline
                        Write-Host ")"
                    }
                }
                Write-Host
            }
            catch {
                Write-Host
            }
        }
    }
    @{
        Command = "ClientReport"
        Description = "Prints a overview of the Broadcaster's clients"
        Action = {
            $cutoff = Read-Host "> Enter a start date to gather data from (e.g. 2024-01-01), or enter to include all"
            if ("" -eq $cutoff) { $startDateString = "1970-01-01"; $cutoff = "beginning of time" } else { $startDateString = $cutoff }
            $startDate = Get-Date -AsUTC $startDateString
            $startDateISO = $startDate.ToString("O")
            Write-Host
            Write-Host "Broadcaster:"$bc.Split("/api")[0]
            Write-Host "For clients active since: `e[92m$cutoff`e[0m"
            $spec = [pscustomobject]@{
                ReceiverCount = "REPORT /ReceiverLog/LastActive>$startDateISO"
                WpfClientNoPOSCount = "REPORT /ReceiverLog/LastActive>$startDateISO&Modules.PosServer.IsInstalled=false&Modules.WpfClient.IsInstalled=true"
                WpfClientWithPOSCount = "REPORT /ReceiverLog/LastActive>$startDateISO&Modules.PosServer.IsInstalled=true&Modules.WpfClient.IsInstalled=true"
                CustomerServiceApplicationCount = "REPORT /ReceiverLog/LastActive>$startDateISO&Modules.CustomerServiceApplication.IsInstalled=true"
            }
            $results = Get-Batch $spec
            $results | Out-Host
        }
    }
    @{
        Command = "ReceiverStatus"
        Description = "Prints the status for all connected Receivers"
        Resources = @{
            "Broadcaster.Admin.Receiver" = "GET"
        }
        Action = {
            $list = irm "$bc/Receiver/_/select=WorkstationId,LastActive" @getSettingsRaw
            if ($list.Count -eq 0) { Write-Host "Found no connected Receivers" }
            else { $list | Sort-Object -Property "WorkstationId" | Out-Host }
        }
    }
    @{
        Command = "ReceiverLog"
        Description = "Prints the last recorded status for all connected and disconnected Receivers"
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "GET"
        }
        Action = {
            $list = irm "$bc/ReceiverLog/_/select=WorkstationId,LastActive,IsConnected" @getSettingsRaw
            if ($list.Count -eq 0) { Write-Host "Found no connected or disconnected Receivers" }
            else { $list | Sort-Object -Property "WorkstationId" | Out-Host }
        }
    }
    @{
        Command = "Config"
        Description = "Prints the configuration of the Broadcaster"
        Resources = @{
            "Broadcaster.Admin.Config" = "GET"
        }
        Action = {
            irm "$bc/Config" @getSettingsRaw | Out-Host
        }
    }
    @{
        Command = "DeploymentInfo"
        Description = "Prints details about deployed software versions on the Broadcaster"
        Resources = @{
            "Broadcaster.Deployment.File" = "GET"
        }
        Action = {
            $list = irm "$bc/File/_/select=ProductName,Version&distinct=true" @getSettingsRaw
            if ($list.Count -eq 0) { Write-Host "Found no deployed software versions" }
            else { $list | Sort-Object -Property "ProductName" | Out-Host }
        }
    }
    @{
        Command = "VersionInfo"
        Description = "Prints details about a the installed software on Receivers"
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "GET"
        }
        Action = $versioninfo_c = {
            $softwareProduct = Get-SoftwareProduct
            if (!$softwareProduct) {
                return
            }
            $response = irm "$bc/ReceiverLog/modules.$softwareProduct.isinstalled=true" @getSettingsRaw
            if ($response.Count -eq 0) {
                Write-Host "Found no connected or disconnected Receivers with $softwareProduct installed"
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
        Command = "OsInfo"
        Description = "Prints details about a the operating system running on Receiver computers"
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "GET"
        }
        Action = {
            $response = irm "$bc/ReceiverLog/_/select=workstationid,modules.machine.osstatus" @getSettingsRaw
            $response | % {
                [pscustomobject]@{
                    WorkstationId = $_.WorkstationId
                    Architecture = $_."modules.machine.osstatus".architecture ?? "???"
                    ".NET version" = $_."modules.machine.osstatus".netfx ?? "???"
                    OS = $_."modules.machine.osstatus".description ?? "???"
                }
            } | Sort-Object -Property "WorkstationId" | % { Pad $_ } | Format-Table | Out-Host
        }
    }
    @{
        Command = "ManualClientInfo"
        Description = "Prints details about the installed manual WPF clients on Receivers"
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "GET"
        }
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
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "GET"
        }
        Action = {
            $response = irm "$bc/ReceiverLog/modules.replication.isactive=true" @getSettingsRaw
            if ($response.Count -eq 0) {
                Write-Host "Found no connected or disconnected Receivers that use replication"
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
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "GET"
        }
        Action = $receiverDetails_c = {
            $workstationId = Get-WorkstationId
            if (!$workstationId) {
                return
            }
            $widLower = $workstationId.ToLower()
            $widUpper = $workstationId.ToUpper()
            $response = irm "$bc/ReceiverLog/WorkstationId>=$widLower&WorkstationId<=$widUpper/select=LastActive,Modules" @getSettingsRaw | Select-Object -first 1
            if (!$response) {
                Write-Host "Found no Receiver with workstation ID $workstationId"
                & $receiverDetails_c
            }
            elseif ($response.PSObject.Properties.Count -eq 0) {
                Write-Host
                Write-Host "Found no details for $workstationId. Details will sync automatically the next time the Receiver is connected"
                Write-Host
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
        Alias = "not"
        Resources = @{
            "Broadcaster.Admin.NotificationLog" = "GET", "DELETE"
        }
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
                    TimestampUtc = $_.TimestampUtc.ToString("yyyy-MM-dd HH:mm:ss")
                    Source = $_.Source
                    Message = $_.Message
                    Hash = $_.Id
                }
            }
            $notifications | % { Pad $_ } | Format-Table -AutoSize -Wrap | Out-Host
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
    @{
        Command = "CheckRetailConnection"
        Description = "Prints details about the Heads Retail Connection"
        Resources = @{
            "Broadcaster.Replication.CheckRetailConnection" = "GET"
        }
        Action = {
            $response = irm "$bc/CheckRetailConnection" @getSettingsRaw
            $status = $response[0].Status
            switch ($status) {
                "NotConfigured" {
                    Write-Host "The Heads Retail connection is not configured" -ForegroundColor Yellow
                }
                "Connected" {
                    Write-Host "The Heads Retail is connected" -ForegroundColor Green
                }
                "Unreachable" {
                    Write-Host "Heads Retail is unreachable. Check the URL field in the RetailConnection section of the Broadcaster configuration" -ForegroundColor Yellow
                }
                "Unauthorized" {
                    Write-Host "Cannot authorize with Heads Retail. Check the BasicAuth field in the RetailConnection section of the Broadcaster configuration and make sure that the use exists with the correct access in Heads Retail" -ForegroundColor Yellow
                }
                "InternalError" {
                    Write-Host "An internal error occurred when contacting Heads Retail. Check the Broadcaster logs for more information" -ForegroundColor Yellow
                }
            }
        }
    }
)
#endregion
#region Dashboards
$dashboardCommands = @(
    @{
        Command = "UpdateDashboard"
        Alias = "ud"
        Description = "Presents a live dashboard of the software update status of clients"
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "GET"
            "Broadcaster.Deployment.LaunchSchedule" = "GET"
        }
        Action = {
            $softwareProduct = Get-SoftwareProduct
            if (!$softwareProduct) {
                return
            }
            $body = @{
                ReceiverLog = "GET /ReceiverLog"
                CurrentVersions = "GET /LaunchSchedule.CurrentVersions//select=$softwareProduct.Version"
            } | ConvertTo-Json
            $runtime = "win7-x64" # Parameterize if necessary
            $sortMember = "Status"
            $descending = $true
            $onlyPos = $false

            $upToDate = "`e[92mUp to date`e[0m"
            $updating = "`e[95mUpdating`e[0m"
            $restarting = "`e[96mRestarting`e[0m"
            $offline = "`e[91mOffline`e[0m"
            $waitingToDownload = "`e[93mWaiting to download`e[0m"
            $downloading = "`e[96mDownloading`e[0m"

            function Sort-Order()
            {
                param($value)
                switch ($value) {
                    $offline { return 0 }
                    $waitingToDownload { return 1 }
                    $downloading { return 2 }
                    $updating { return 3 }
                    $restarting { return 4 }
                    $upToDate { return 5 }
                }
                return $value
            }

            while ($true) {
                $members = @{
                    Status = "`e[97mS`e[92mtatus"
                    Kind = "`e[97mK`e[92mind"
                    WorkstationId = "Workstation`e[97m I`e[92mD"
                    LastActive = "`e[97mL`e[92mast active (UTC)"
                    Version = "`e[97mV`e[92mersion"
                    "Download %" = "`e[97mD`e[92mownload %"
                }
                if ($onlyPos) {
                    $members.Kind = "`e[97mK`e[93mind`e[92m"
                }
                if ($descending) {
                    $postfix = "`e[95m▼`e[92m"
                } else {
                    $postfix = "`e[95m▲`e[92m"
                }
                $data = Get-Batch $body
                $currentVersion = [System.Version]$data.CurrentVersions[0]."$softwareProduct.Version"
                if (!$currentVersion) {
                    Write-Host "No version of $softwareProduct is currently active" -ForegroundColor Yellow
                    $command = Get-DashboardInput
                    if ($command -eq "quit") { return }
                    continue
                }
                $listData = $data.ReceiverLog | % {
                    $status = ""
                    $isRecent = $_.LastActive -gt (Get-Date -AsUTC).AddMinutes(-2)
                    $downloadPercent = $null
                    if ($_.Modules."$softwareProduct".CurrentVersion -eq $currentVersion) {
                        if ($softwareProduct -eq "PosServer") {
                            if ($_.Modules.PosServer.IsRunning) {
                                $status = $upToDate
                            }
                            else {
                                $status = $restarting
                            }
                        }
                        $status = $upToDate
                    }
                    elseif ($currentVersion -in $_.Modules."$softwareProduct".DeployedVersions) {
                        $downloadPercent = 100
                        $status = $updating
                    }
                    elseif (!$_.IsConnected -and !$isRecent) {
                        $status = $offline
                    }
                    else {
                        $download = $data.Modules.Downloads."SoftwareBinary/$softwareProduct-$currentVersion-$runtime";
                        if ($download) {
                            if ($download.ByteCount > 0) {
                                $downloadPercent = [int]($download.BytesDownloaded / $download.ByteCount * 100)
                            }
                            if ($download.BytesDownloaded -eq 0) {
                                $status = $waitingToDownload
                            }
                            else { $status = $downloading }
                        }
                    }
                    $target = [ordered]@{ }
                    function S()
                    {
                        param($o, $name, $value)
                        $displayName = $members[$name]
                        if ($sortMember -eq $name) { $o."$displayName $postfix" = $value }
                        else { $o.$displayName = $value }
                    }
                    $kind = ""
                    if ($_.Modules.PosServer.IsInstalled -eq $true) {
                        $kind = "POS"
                    }
                    elseif ($_.Modules.CustomerServiceApplication.IsInstalled -eq $true) {
                        $kind = "CSA"
                    }
                    elseif ($_.Modules.WpfClient.IsInstalled -eq $true) {
                        $kind = "BO"
                    }
                    else {
                        $kind = "--"
                    }
                    S $target Status $status
                    S $target Kind $kind
                    S $target WorkstationId $_.WorkstationId
                    S $target LastActive $_.LastActive
                    $version = $_.Modules."$softwareProduct".CurrentVersion
                    if ($status -eq $upToDate) {
                        $version = "`e[92m$version`e[0m"
                    } else {
                        $version = "`e[91m$version`e[0m"
                    }
                    S $target Version $version
                    if ($downloadPercent -eq 100) {
                        $downloadPercent = "`e[92m$downloadPercent`e[0m"
                    }
                    elseif ($downloadPercent) {
                        $downloadPercent = "`e[93m$downloadPercent`e[0m"
                    }
                    S $target "Download %" $downloadPercent
                    return [pscustomobject]$target
                }
                cls
                Write-DashboardHeader "UpdateDashboard" $softwareProduct $onlyPos
                $listData |  ? { !$onlyPos -or $_."$( $members["Kind"] )" -eq "POS" } | % { Pad $_ } | Sort-Object @{ Expression = { Sort-Order $_."$( $members[$sortMember] ) $postfix" }; Ascending = !$descending } |`
                Format-Table | Out-Host

                $prevSort = $sortMember
                switch (Get-DashboardInput s w k f l d v) {
                    quit { return }
                    refresh {
                        $prevSort = $null
                        break
                    }
                    f {
                        $onlyPos = !$onlyPos
                        $prevSort = $null
                        break;
                    }
                    s {
                        $sortMember = "Status"
                        break
                    }
                    k {
                        $sortMember = "Kind"
                        break
                    }
                    w {
                        $sortMember = "WorkstationId"
                        break
                    }
                    l {
                        $sortMember = "LastActive"
                        break
                    }
                    v {
                        $sortMember = "Version"
                        break
                    }
                    d {
                        $sortMember = "Download %"
                        break
                    }
                }
                if ($prevSort -eq $sortMember) {
                    $descending = !$descending
                }
            }
        }
    }
    @{
        Command = "SoftwareDashboard"
        Description = "Presents a live dashboard of the installed software on clients"
        Alias = "sd"
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "GET"
            "Broadcaster.Deployment.LaunchSchedule" = "GET"
        }
        Action = {
            $body = @{
                ReceiverLog = "GET /ReceiverLog"
                CurrentVersions = "GET /LaunchSchedule.CurrentVersions"
            } | ConvertTo-Json
            $runtime = "win7-x64" # Parameterize if necessary
            $sortMember = "Status"
            $descending = $true
            $onlyPos = $false
            while ($true) {

                $members = @{
                    Status = "`e[97mS`e[92mtatus"
                    Kind = "`e[97mK`e[92mind"
                    WorkstationId = "Workstation`e[97m I`e[92mD"
                    LastActive = "`e[97mL`e[92mast active (UTC)"
                    Receiver = "`e[97mR`e[92meceiver"
                    WpfClient = "`e[97mW`e[92mPF Client"
                    PosServer = "`e[97mP`e[92mOS Server"
                    CustomerServiceApplication = "`e[97mC`e[92mustomer Service Application"
                }
                if ($onlyPos) {
                    $members.Kind = "`e[97mK`e[93mind`e[92m"
                }
                if ($descending) {
                    $postfix = "`e[95m▼`e[92m"
                } else {
                    $postfix = "`e[95m▲`e[92m"
                }
                $data = Get-Batch $body
                $currentVersions = $data.CurrentVersions[0]
                $listData = $data.ReceiverLog | % {
                    $isRecent = $_.LastActive -gt (Get-Date -AsUTC).AddMinutes(-2)
                    if ($_.IsConnected -or $isRecent) { $status = "`e[92mOnline`e[0m" }
                    else { $status = "`e[91mOffline`e[0m" }
                    $target = [ordered]@{ }
                    function S()
                    {
                        param($o, $name, $value)
                        $displayName = $members[$name]
                        if ($sortMember -eq $name) { $o."$displayName $postfix" = $value }
                        else { $o.$displayName = $value }
                    }
                    function HL()
                    {
                        param($name, $version)
                        if (!$version) { return "" }
                        $post = ""
                        $fixedLength = 20
                        if ($_.IsConnected -or $isRecent) {
                            if ($_.Modules.$name.IsRunning) { $post = " `e[1m`e[92m`u{2713}`e[0m" }
                            else { $post = " `e[1m`e[91m`u{2717}`e[0m" }
                        } else { $post = " `e[1m`e[97m`u{2300}`e[0m" }
                        $versionPart = $version
                        if (($version.Length % 2) -ne 0) {
                            $versionPart = "$versionPart "
                        }
                        $versionPart = $versionPart.PadRight($versionPart.Length + 1)
                        if ($currentVersions.$name.Version -eq $version) {
                            return "`e[92m$versionPart`e[0m$post"
                        }
                        elseif ($currentVersions.$name.Version -lt $version) {
                            return "`e[95m$versionPart`e[0m$post"
                        }
                        else {
                            return "`e[91m$versionPart`e[0m$post"
                        }
                    }
                    $kind = ""
                    if ($_.Modules.PosServer.IsInstalled -eq $true) {
                        $kind = "POS"
                    }
                    elseif ($_.Modules.CustomerServiceApplication.IsInstalled -eq $true) {
                        $kind = "CSA"
                    }
                    elseif ($_.Modules.WpfClient.IsInstalled -eq $true) {
                        $kind = "BO"
                    }
                    else {
                        $kind = "--"
                    }
                    S $target Status $status
                    S $target Kind $kind
                    S $target WorkstationId $_.WorkstationId
                    S $target LastActive $_.LastActive
                    $receiver = HL Receiver $_.Modules.Receiver.CurrentVersion
                    S $target Receiver $receiver
                    $wpfClient = HL WpfClient $_.Modules.WpfClient.CurrentVersion
                    S $target WpfClient $wpfClient
                    $posServer = HL PosServer $_.Modules.PosServer.CurrentVersion
                    S $target PosServer $posServer
                    $csa = HL CustomerServiceApplication $_.Modules.CustomerServiceApplication.CurrentVersion
                    if ($csa) {
                        S $target CustomerServiceApplication $csa
                    }
                    return [pscustomobject]$target
                }
                cls
                Write-DashboardHeader "SoftwareDashboard" "" $onlyPos
                $listData | ? { !$onlyPos -or $_."$( $members["Kind"] )" -eq "POS" } | % { Pad $_ } | Sort-Object @{ Expression = { $_."$( $members[$sortMember] ) $postfix" }; Ascending = !$descending } | `
                Format-Table | Out-Host

                $prevSort = $sortMember
                switch (Get-DashboardInput s i l f k r w p c) {
                    quit { return }
                    refresh {
                        $prevSort = $null
                        break
                    }
                    f {
                        $onlyPos = !$onlyPos
                        $prevSort = $null
                        break;
                    }
                    s {
                        $sortMember = "Status"
                        break
                    }
                    k {
                        $sortMember = "Kind"
                        break
                    }
                    i {
                        $sortMember = "WorkstationId"
                        break
                    }
                    l {
                        $sortMember = "LastActive"
                        break
                    }
                    r {
                        $sortMember = "Receiver"
                        break
                    }
                    w {
                        $sortMember = "WpfClient"
                        break
                    }
                    p {
                        $sortMember = "PosServer"
                        break
                    }
                    c {
                        $sortMember = "CustomerServiceApplication"
                        break
                    }
                }
                if ($prevSort -eq $sortMember) {
                    $descending = !$descending
                }
            }
        }
    }
    @{
        Command = "ReplicationDashboard"
        Description = "Presents a live dashboard of the replication status of clients"
        Alias = "rd"
        Resources = @{
            "Broadcaster.Admin.ReplicationState" = "GET"
            "Broadcaster.Deployment.LaunchSchedule" = "GET"
        }
        Action = {
            $body = @{
                ReplicationState = "GET /ReplicationState"
                CurrentVersions = "GET /LaunchSchedule.CurrentVersions"
            } | ConvertTo-Json
            $url = "$bc/ReplicationState"
            $sortMember = "Status"
            $descending = $true

            $upToDate = "`e[92mUp to date`e[0m"
            $replicating = "`e[92mReplicating`e[0m"
            $awaitUpdate = "`e[93mAwait update`e[0m"
            $awaitInit = "`e[96mAwait init`e[0m"
            $blocked = "`e[95mBlocked`e[0m"
            $obsolete = "`e[91mObsolete`e[0m"

            function Sort-Order()
            {
                param($value)
                switch ($value) {
                    $obsolete { return 0 }
                    $blocked { return 1 }
                    $awaitInit { return 2 }
                    $awaitUpdate { return 3 }
                    $replicating { return 4 }
                    $upToDate { return 5 }
                }
                return $value
            }

            while ($true) {
                $members = @{
                    Status = "`e[97mS`e[92mtatus"
                    Connection = "`e[97mC`e[92monnection"
                    "Filter" = "`e[97mF`e[92milter"
                    WorkstationId = "Workstation`e[97m I`e[92mD"
                    LastReceived = "`e[97mL`e[92mast received (UTC)"
                    LastActive = "Last ac`e[97mt`e[92mive (UTC)"
                    PosServerVersion = "`e[97mP`e[92mOS Server version"
                    ReplicationVersion = "`e[97mR`e[92meplication version"
                    Applicable = "`e[97mA`e[92mpplicable"
                    NonApplicable = "`e[97mN`e[92mon-applicable"
                }
                if ($descending) {
                    $postfix = "`e[95m▼`e[92m"
                } else {
                    $postfix = "`e[95m▲`e[92m"
                }
                $data = Get-Batch $body
                $currentPosVersion = $data.CurrentVersions[0].PosServer.Version
                $listData = $data.ReplicationState | % {
                    $status = ""
                    if ($_.AwaitsInitialization -eq $false -and $_.IsInSequence -eq $false) {
                        $status = $obsolete
                    }
                    elseif ($_.AwaitsInitialization -eq $true) {
                        $status = $awaitInit
                    }
                    elseif ($_.IsBlocked -eq $true) {
                        $status = $blockedt
                    }
                    elseif($_.RequiresPosServerUpdate) {
                        $status = $awaitUpdate
                    }
                    elseif($_.ApplicableCount -eq 0) {
                        $status = $upToDate
                    }
                    else {
                        $status = $replicating
                    }
                    $target = [ordered]@{ }
                    function S()
                    {
                        param($o, $name, $value)
                        $displayName = $members[$name]
                        if ($sortMember -eq $name) { $o."$displayName $postfix" = $value }
                        else { $o.$displayName = $value }
                    }
                    S $target Status $status
                    $connection = ""
                    $isRecent = $_.LastActive -gt (Get-Date -AsUTC).AddMinutes(-2)
                    if ($_.IsConnected -or $isRecent) { $connection = "`e[92mOnline`e[0m" }
                    else { $connection = "`e[91mOffline`e[0m" }
                    S $target Connection $connection
                    $filter = ""
                    if ($_.IncludedInFilter) { $filter = "`e[92m`u{2713}`e[0m" }
                    else { $filter = "`e[91m`u{2717}`e[0m" }
                    S $target "Filter" $filter
                    S $target WorkstationId $_.WorkstationId
                    S $target LastReceived $_.LastReceived
                    S $target LastActive $_.LastActive
                    $posServerVersion = $_.PosServerVersion
                    if ($posServerVersion -eq $currentPosVersion) {
                        $posServerVersion = "`e[92m$posServerVersion`e[0m"
                    }
                    else {
                        $posServerVersion = "`e[93m$posServerVersion`e[0m"
                    }
                    S $target PosServerVersion $posServerVersion
                    S $target ReplicationVersion $_.ReplicationVersion
                    S $target Applicable $_.ApplicableCount
                    S $target NonApplicable $_.NonApplicableCount
                    return [pscustomobject]$target
                }
                cls
                Write-DashboardHeader "ReplicationDashboard" $softwareProduct
                $listData | % { Pad $_ } | Sort-Object @{ Expression = { Sort-Order $_."$( $members[$sortMember] ) $postfix" }; Ascending = !$descending } |`
                Format-Table | Out-Host

                $prevSort = $sortMember
                switch (Get-DashboardInput s c f w i l t p r a n) {
                    quit { return }
                    refresh {
                        $prevSort = $null
                        break
                    }
                    s {
                        $sortMember = "Status"
                        break
                    }
                    c {
                        $sortMember = "Connection"
                        break
                    }
                    f {
                        $sortMember = "Filter"
                        break
                    }
                    i {
                        $sortMember = "WorkstationId"
                        break
                    }
                    l {
                        $sortMember = "LastReceived"
                        break
                    }
                    t {
                        $sortMember = "LastActive"
                        break
                    }
                    p {
                        $sortMember = "PosServerVersion"
                        break
                    }
                    r {
                        $sortMember = "ReplicationVersion"
                        break
                    }
                    a {
                        $sortMember = "Applicable"
                        break
                    }
                    n {
                        $sortMember = "NonApplicable"
                        break
                    }
                }
                if ($prevSort -eq $sortMember) {
                    $descending = !$descending
                }
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
        Resources = @{
            "Broadcaster.Admin.InstallToken" = "GET"
        }
        Action = {
            Write-Host
            Write-Host "This tool will help create a Broadcaster install script!" -ForegroundColor Green
            Write-Host
            $bcUrl = Get-BroadcasterUrl-Ism
            $hosted = $bcUrl.Contains("heads-api.com") -or $bcUrl.Contains("heads-app.com")
            if ($bcUrl -eq $bc -and (Has-Access "Broadcaster.Admin.DependencyStatus" "GET")) {
                $status = (irm "$bc/DependencyStatus" @getSettingsRaw)[0]
                if ($status.CurrentPolicy -eq "Local" -and !$status.HasPowerShell) {
                    Write-Host "Warning: This Broadcaster uses the dependency source policy 'Local', but has no deployed dependencies" -ForegroundColor Yellow
                    if (Yes "> Do you want to deploy dependencies now?") {
                        Update-Dependencies
                    }
                }
            }
            if ($hosted) {
                Write-Host "The URI has the format of a Heads-hosted Broadcaster. If an error occurs during install, IP diagnostics will be included in the output" -ForegroundColor Yellow
            }
            $token = Read-Host "> Now enter the install token (or 'enter' for a new 7 day token)" -MaskInput
            if ($token -eq "") {
                $token = irm "$bcUrl/InstallToken" @getSettingsRaw | % { $_.Token }
            }
            $token = $token.Trim()
            $uris = @()
            if (Yes "> Should we first uninstall existing client software, if present?") {
                if (Yes "--> Also uninstall legacy (SUS/RA) client software?") {
                    $uris += "'uninstall.legacy'"
                }
                $uris += "'uninstall.all'"
            }
            if (Yes "> Install Receiver?") {
                $uris += "'install/p=Receiver'"
            }
            $csa = $false
            if (Yes "> Install WpfClient?") {
                $part = "p=WpfClient"
                Write-Host "WpfClient can be installed as a 'manual' client, next to a regular client, targeting a separate Heads Retail environment (for example a test environment)" -ForegroundColor Yellow
                if (Yes "--> Install as a manual client?") {
                    $label = Label
                    $installPath = [System.Uri]::EscapeDataString("C:\ProgramData\Heads\$label")
                    $part += "&installPath=$installPath"
                    $shortcutLabel = [System.Uri]::EscapeDataString("Heads Retail - $label")
                    $part += "&shortcutLabel=$shortcutLabel"
                }
                $part += "&usePosServer=" + (Yes "--> Connect client to local POS Server?")
                $part += "&useArchiveServer=" + (Yes "--> Connect client to central Archive Server?")
                $uris += "'install/$part'"
            }
            elseif (Yes "> Install CustomerServiceApplication?") {
                $uris += "'install/p=CustomerServiceApplication'"
                $csa = $true
            }
            if (!$csa -and (Yes "> Install POS Server?")) {
                $part = "p=PosServer"
                $part += "&createDump=" + (Yes "--> Create a dump of an existing POS-server?")
                $part += "&collation=" + (Collation "--> Enter database collation, e.g. sv-SE")
                $part += "&databaseImageSize=" + (Num "--> Enter database image size in MB (or enter for 1024)" 1024)
                $part += "&databaseLogSize=" + (Num "--> Enter database log size in MB (or enter for 1024)" 1024)
                $uris += "'install/$part'"
            }
            $arr = $uris | Join-String -Separator ","
            $ip = "+'|'"
            if ($hosted) {
                $ip = "+'@'+`$(irm('icanhazip.com'))"
            }
            $outUrl = $bcUrl.Substring(0, ($bcUrl.Length - 4))
            Write-Host
            Write-Host "Always test scripts before sending them to customers!" -ForegroundColor Yellow
            Write-Host
            Sleep 3
            Write-Host "# Here's your install script! Run it in PowerShell as administrator on a client computer:"
            Write-Host
            Write-Host "$arr|%{try{`$u='$outUrl'+'/api/'+`$_;irm(`$u)-He:@{Authorization='Bearer'+[char]0x0020+'$token'}|iex}catch{throw(`$u+'|OS:'+`$PSVersionTable.OS+'|'+`$(hostname)$ip+`$_)}};"
            Write-Host
            Write-Host "# End of script"
            Write-Host
            Write-Host "Returning to Broadcaster Manager..." -ForegroundColor Yellow
            Write-Host
        }
    }
    @{
        Command = "Install"
        Description = "Install or reinstall software on client computers through the Receiver"
        Resources = @{
            "Broadcaster.RemoteDeployment.RemoteInstall" = "POST"
        }
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
            $pms = @{ }
            $version = $null
            $runtimeId = $null
            $data = @{
                Workstations = $workstationIds
                Product = $softwareProduct
                Parameters = $pms
            }
            switch ($softwareProduct) {
                "WpfClient" {
                    if (Yes "> Install as a manual client?") {
                        $bcUrl = Get-BroadcasterUrl "to get the manual client from"
                        $bcUrl = $bcUrl.Substring(0, ($bcUrl.Length - 4))
                        $data.BroadcasterUrl = $bcUrl
                        $token = Read-Host "> Enter the install token to use at $bcUrl " -MaskInput
                        $data.InstallToken = $token
                        $label = Label
                        $pms.shortcutLabel = [System.Uri]::EscapeDataString("Heads Retail - $label")
                        $pms.installPath = [System.Uri]::EscapeDataString("C:\ProgramData\Heads\$label")
                        function Get-Version
                        {
                            Write-Host "> Note: The version of the manual client used below should be launched at $bcUrl" -ForegroundColor Yellow
                            $message = "> Enter $softwareProduct version to use or 'cancel' to cancel"
                            $input = Read-Host $message
                            $input = $input.Trim()
                            if ($input -eq "cancel") {
                                return $null
                            }
                            $r = $null
                            if (![System.Version]::TryParse($input, [ref]$r)) {
                                Write-Host "Invalid version format. Try again."
                                return Get-Version
                            }
                            return $input
                        }
                        $version = Get-Version
                        if (!$version) {
                            return
                        }
                    }
                    $pms.usePosServer = (Yes "> Connect client to local POS Server?")
                    $pms.useArchiveServer = (Yes "> Connect client to central Archive Server?")
                }
                "PosServer" {
                    $pms.createDump = (Yes "> Create a dump of an existing POS-server?")
                    $pms.collation = (Collation "> Enter database collation, e.g. sv-SE")
                    $pms.databaseImageSize = (Num "> Enter database image size in MB (or enter for 1024)" 1024)
                    $pms.databaseLogSize = (Num "> Enter database log size in MB (or enter for 1024)" 1024)
                }
                "CustomerServiceApplication" { }
                default {
                    Write-Host "Can't remote-install $softwareProduct"
                    & $install_c
                    return
                }
            }
            if (!$version) {
                $version = Get-LaunchedSoftwareProductVersion $softwareProduct
                if (!$version) {
                    return
                }
            }
            $runtimeId = Get-RuntimeId "to install"
            if (!$runtimeId) {
                return
            }
            $data.Version = $version.ToString()
            $data.Runtime = $runtimeId

            $body = $data | ConvertTo-Json
            Write-Host "> This will install $softwareProduct $version on $( $workstationIds.Count ) workstations:" -ForegroundColor Yellow
            $workstationIds | Out-Host
            if (!(Yes "> Do you want to proceed?")) {
                Write-Host "Aborted"
                return
            }
            Write-Host "Running remote install (this could take a while)" -ForegroundColor Yellow
            $result = irm "$bc/RemoteInstall" @postSettings -Body $body -TimeoutSec 3600 -ErrorAction SilentlyContinue
            try {
                Write-RemoteResult $result
                Write-Host
                Write-Host "Note that the new state of installed software may take a minute to update" -ForegroundColor Yellow
            }
            catch {
                Write-Host "An error occurred while remote-installing $softwareProduct"
                $result | Out-Host
            }
            & $install_c
        }
    }
    @{
        Command = "Uninstall"
        Description = "Uninstall software on client computers through the Receiver"
        Resources = @{
            "Broadcaster.RemoteDeployment.RemoteUninstall" = "POST"
        }
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
            $workstationIds | Out-Host
            if (!(Yes "> Do you want to proceed?")) {
                Write-Host "Aborted"
                return
            }
            Write-Host "Running remote uninstall (this could take a while)" -ForegroundColor Yellow
            $result = irm "$bc/RemoteUninstall" @postSettings -Body $body -TimeoutSec 3600 -ErrorAction SilentlyContinue
            try {
                Write-RemoteResult $result
                Write-Host
                Write-Host "Note that the new state of installed software may take a minute to update" -ForegroundColor Yellow
            }
            catch {
                Write-Host "An error occurred while remote-uninstalling $softwareProduct"
                $result | Out-Host
            }
            & $uninstall_c
        }
    }
    @{
        Command = "Reset"
        Description = "Resets one or more POS server databases"
        Resources = @{
            "Broadcaster.RemoteDeployment.Reset" = "POST"
        }
        Action = {
            [string[]]$workstationIds = Get-WorkstationIds
            Write-Host "> This will reset the POS-Server databases on $( $workstationIds.Length ) workstations:"
            $workstationIds | Out-Host
            Write-Host "> `e[93mWarning:`e[0m Day journals must now be manually closed using `e[93mCloseDayJournal`e[0m before running reset"
            if (!(Yes "> Do you want to proceed? This will reset all selected POS-Server databases and cannot be undone")) {
                Write-Host "Aborted"
                return
            }
            Write-Host "Running reset (this could take a while)" -ForegroundColor Yellow
            $body = @{ Workstations = $workstationIds; } | ConvertTo-Json
            $result = irm "$bc/Reset" -Body $body @postSettings -TimeoutSec 3600 -ErrorAction SilentlyContinue
            try {
                Write-RemoteResult $result
                Write-Host
            }
            catch {
                Write-Host "An error occurred while running reset"
                $result | Out-Host
            }
        }
    }
    @{
        Command = "CloseDayJournal"
        Description = "Closes the day journals of one or more POS server clients"
        Resources = @{
            "Broadcaster.RemoteDeployment.CloseDayJournal" = "POST"
        }
        Action = {
            [string[]]$workstationIds = Get-WorkstationIds
            Write-Host "> Selected these workstations to close day journals for:"
            $workstationIds | Out-Host
            $posUser = Read-Host "> Enter the user name to call the POS-server APIs with when closing the day journals or 'cancel' to cancel"
            $posUser = $posUser.Trim()
            if ($posUser -ieq "cancel") {
                return
            }
            $posPassword = Read-Host "> Enter that user's password or 'cancel' to cancel" -MaskInput
            if ($posPassword -ieq "cancel") {
                return
            }
            Write-Host "> This will close the day journals on $( $workstationIds.Length ) workstations:"
            $workstationIds | Out-Host
            if (!(Yes "> Do you want to proceed?")) {
                Write-Host "Aborted"
                return
            }
            Write-Host "Closing day journals (this could take a while)" -ForegroundColor Yellow
            $body = @{ Workstations = $workstationIds; PosUser = $posUser; PosPassword = $posPassword; } | ConvertTo-Json
            $result = irm "$bc/CloseDayJournal" -Body $body @postSettings -TimeoutSec 3600 -ErrorAction SilentlyContinue
            try {
                Write-RemoteResult $result
                Write-Host
            }
            catch {
                Write-Host "An error occurred while closing day journals"
                $result | Out-Host
            }
        }
    }
    @{
        Command = "Control"
        Description = "Start or stop services and applications on client computers"
        Resources = @{
            "Broadcaster.RemoteDeployment.RemoteControl" = "POST"
        }
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
            $workstationIds | Out-Host
            if (!(Yes "> Do you want to proceed?")) {
                Write-Host "Aborted"
                return
            }
            Write-Host "Running $command (this could take a while)" -ForegroundColor Yellow
            $result = irm "$bc/RemoteControl" @postSettings -Body $body -ErrorAction SilentlyContinue -TimeoutSec 3600
            try {
                Write-RemoteResult $result
                Write-Host
            }
            catch {
                Write-Host "An error occurred while running $command on the selected clients:"
                $result | Out-Host
            }
        }
    }
    @{
        Command = "ManualLaunch"
        Description = "Run an unscheduled launch of a client software version on selected connected client computers"
        Resources = @{
            "Broadcaster.RemoteDeployment.ManualLaunch" = "POST"
        }
        Action = $mlaunch_c = {
            $softwareProduct = Get-SoftwareProduct
            if (!$softwareProduct) {
                return
            }
            $version = Get-LaunchableSoftwareProductVersion $softwareProduct
            [string[]]$workstationIds = Get-WorkstationIds
            if (!$workstationIds) {
                return
            }
            $data = @{
                Workstations = $workstationIds
                Product = $softwareProduct
                Version = $version.ToString()
            }
            $body = $data | ConvertTo-Json
            Write-Host "> This will launch $softwareProduct $version on $( $workstationIds.Count ) workstations:"
            $workstationIds | Out-Host
            Write-Host "> The operation will fail if $softwareProduct $version is not deployed on all workstations"
            if (!(Yes "> Do you want to proceed?")) {
                Write-Host "Aborted"
                return
            }
            Write-Host "Launching..." -ForegroundColor Yellow
            $result = irm "$bc/ManualLaunch" @postSettings -Body $body -ErrorAction SilentlyContinue -TimeoutSec 3600
            if ($result.Status -eq "success" -and $result.DataCount -gt 0) {
                Write-Host
                Write-Host "RESULTS:" -ForegroundColor Yellow
                Write-Host
                foreach ($item in $result.Data) {
                    $id = $item.Workstations[0]
                    Write-Host "$id`: " -NoNewline
                    if ($item.Launching) {
                        Write-Host "Success" -ForegroundColor Green
                    } else {
                        Write-Host "Failed" -ForegroundColor Red -NoNewline
                        Write-Host " – " -NoNewline
                        Write-Host $item.ErrorMessage
                    }
                }
                Write-Host
            }
            else {
                Write-Host "An error occurred while launching $softwareProduct $version on the selected clients:"
                $result | Out-Host
            }
        }
    }
    @{
        Command = "InstallToken"
        Resources = @{
            "Broadcaster.Admin.InstallToken" = "GET"
        }
        Description = "Generates a new install token with a 7 day expiration"
        Action = {
            $token = irm "$bc/InstallToken" @getSettingsRaw
            Write-Host
            Write-Host "Token:       " -NoNewline
            Write-Host $token.Token -ForegroundColor Yellow
            Write-Host "Expires at:  " -NoNewline
            Write-Host $token.ExpiresAtUtc.ToString("yyyy-MM-dd HH:mm:ss UTC") -ForegroundColor Yellow
            Write-Host
        }
    }
    @{
        Command = "DownloadFile"
        Resources = @{
            "Broadcaster.Admin.ReceiverHeadsTextFile" = "GET"
        }
        Description = "Downloads a text file from within the 'C:\ProgramData\Heads' directory on a client computer"
        Action = {
            $path = Read-Host "> Enter a file path to the file to download or 'cancel' to cancel. The path must begin with C:\ProgramData\Heads"
            if ($path -ieq "cancel") {
                return
            }
            if ($path -notmatch "^C:\\ProgramData\\Heads\\") {
                Write-Host "Invalid path. The path must begin with C:\ProgramData\Heads"
                return
            }
            $workstationId = Get-WorkstationId "for the client to download the file from"
            $downloads = "";
            if ($IsWindows) {
                $downloads = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
            } else {
                $downloads = "~/Downloads"
            }
            $path = [System.Uri]::EscapeDataString($path)
            $tempFile = [System.IO.Path]::GetTempFileName()
            $response = iwr "$bc/ReceiverHeadsTextFile/WorkstationId=$workstationId&FilePath=$path" @getSettings -PassThru -OutFile $tempFile -AllowUnencryptedAuthentication
            $contentDisposition = $response.Headers."Content-Disposition"
            $fileName = $contentDisposition.SubString(21)
            $outputFile = Join-Path $downloads $filename
            echo "> Downloaded file to '$outputFile'"
            Move-Item -Path $tempFile -Destination $outputFile -Force
        }
    }

)
#endregion
#region Modify
$modifyCommands = @(
    @{
        Command = "Forget"
        Description = "Removes the Receiver log entry for a given workstation"
        Resources = @{
            "Broadcaster.Admin.ReceiverLog" = "DELETE"
        }
        Action = $forget_c = {
            $workstationId = Get-WorkstationId "for the client that should be forgotten"
            if (!$workstationId) {
                return
            }
            $widLower = $workstationId.ToLower()
            $widUpper = $workstationId.ToUpper()
            $result = irm "$bc/ReceiverLog/WorkstationId>=$widLower&WorkstationId<=$widUpper" @deleteSettings
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
        Resources = @{
            "Broadcaster.Deployment.RemoteFile" = "GET", "PATCH"
        }
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
            Write-Host
            Write-Host "Downloading $softwareProduct $version to the Broadcaster. Be patient..." -ForegroundColor Yellow
            $body = @{ Deploy = $true } | ConvertTo-Json
            $result = irm "$bc/RemoteFile/ProductName=$softwareProduct&$versionConditions/offset=-4&unsafe=true" -Body $body @patchSettings
            if ($result.Status -eq "success") {
                if ($result.DataCount -eq 0) {
                    Write-Host "No version was deployed. Please ensure that version $version of $softwareProduct is deployable." -ForegroundColor Red
                    & $deploy_c
                } else {
                    Write-Host "Success!" -ForegroundColor Green
                }
            }
            else {
                Write-Host "An error occured while deploying $softwareProduct $version. This version might be partially deployed. Partially deployed versions are not deployed to clients"
                Write-Host $result
            }
            Write-Host
            & $deploy_c
        }
    }
    @{
        Command = "Launch"
        Description = "Lists launchable software versions and schedules launches"
        Resources = @{
            "Broadcaster.Deployment.LaunchSchedule" = "GET", "POST"
        }
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
                        Write-Host "A launch was successfully scheduled" -ForegroundColor Green
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
        Command = "Versions"
        Description = "Lists and assigns the Retail versions that are tracked on the build output share, from where the BC can deploy client software versions"
        Resources = @{
            "Broadcaster.Deployment.RemoteFile" = "GET", "PATCH"
        }
        Action = $versions_c = {
            $input = Read-Host "> Enter 'list' to list the tracked Retail versions, 'add' or 'remove' to edit the list or 'cancel' to cancel"
            switch ( $input.Trim().ToLower()) {
                "cancel" { return }
                "list" {
                    [string[]]$tags = (irm "$bc/RemoteFile.Settings/_/select=RetailBuildTags" @getSettingsRaw).RetailBuildTags
                    if ($tags.Count -eq 0) {
                        Write-Host "There are no tracked Retail versions"
                    } else {
                        Write-Host
                        $tags | Out-Host
                        Write-Host
                    }
                    & $versions_c
                }
                "add" {
                    $version = Get-RetailVersion
                    [string[]]$versions = (irm "$bc/RemoteFile.Settings/_/select=RetailBuildTags" @getSettingsRaw).RetailBuildTags
                    $versions += $version
                    $body = @{ RetailBuildTags = $versions } | ConvertTo-Json
                    $result = irm "$bc/RemoteFile.Settings" -Body $body @patchSettings
                    if ($result.Status -eq "success") {
                        Write-Host "$version was added" -ForegroundColor Green
                    } else {
                        Write-Host "An error occured while adding $version to the tracked Retail versions list"
                    }
                    & $versions_c
                }
                "remove" {
                    $version = Get-RetailVersion
                    [System.Collections.Generic.List[string]]$versions = (irm "$bc/RemoteFile.Settings/_/select=RetailBuildTags" @getSettingsRaw).RetailBuildTags
                    $removed = $versions.Remove($version)
                    if (!$removed) {
                        Write-Host "$version is not a tracked Retail version"
                        & $versions_c
                    }
                    else {
                        $body = @{ RetailBuildTags = $versions } | ConvertTo-Json
                        $result = irm "$bc/RemoteFile.Settings" -Body $body @patchSettings
                        if ($result.Status -eq "success") {
                            Write-Host "$version was removed"  -ForegroundColor Green
                        } else {
                            Write-Host "An error occured while removing $version from the tracked Retail versions list"
                        }
                    }
                    & $versions_c
                }
                default { & $versions_c }
            }
        }
    }
    @{
        Command = "ReplicationFilter"
        Description = "View and edit the Replication filter, defining the enabled replication recipients"
        Resources = @{
            "Broadcaster.Replication.ReplicationFilter" = "GET", "PATCH"
        }
        Action = $replicationfilter_c = {
            $filter = irm "$bc/ReplicationFilter" @getSettingsRaw
            if ($filter.AllowAll) {
                Write-Host "Replication is currently enabled for all recipients" -ForegroundColor Green
            }
            elseif ($filter.AllowNone) {
                Write-Host "Replication is currently disabled for all recipients" -ForegroundColor Red
            }
            else {
                Write-Host "Replication is currently enabled ONLY for the following recipients:" -ForegroundColor Yellow
                $filter.EnabledRecipients | Out-Host
            }
            $input = Read-Host "> Enter 'enable' to enable for all, 'disable' to disable for all, 'edit' to manage enabled recipients or 'enter' to continue"
            $input = $input.Trim().ToLower()
            $body = $null
            switch ($input) {
                "enable" {
                    $body = @{ EnabledRecipients = @("*") } | ConvertTo-Json
                    break
                }
                "disable" {
                    $body = @{ EnabledRecipients = @() } | ConvertTo-Json
                    break
                }
                "edit" {
                    Write-Host "Replication recipients can be workstation IDs or group names" -ForegroundColor Yellow
                    [string[]]$recipients = Get-WorkstationIds
                    $body = @{ EnabledRecipients = $recipients } | ConvertTo-Json
                    break
                }
                default { return }
            }
            $result = irm "$bc/ReplicationFilter" -Body $body @patchSettings
            if ($result.Status -eq "success") {
            } else {
                Write-Host "An error occured while updating the replication filter"
            }
            & $replicationfilter_c
        }
    }
    @{
        Command = "Groups"
        Description = "Lists and assigns workstation group members"
        Resources = @{
            "Broadcaster.Replication.WorkstationGroups" = "GET", "PATCH"
        }
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
        Resources = @{
            "Broadcaster.Admin.Config" = "GET"
            "Broadcaster.Admin.BroadcasterUpdate" = "GET", "PATCH"
        }
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
            Write-Host $nextAvailable.Version -ForegroundColor Magenta -NoNewline
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
    @{
        Command = "Dependencies"
        Description = "Lists and updates the Broadcaster dependencies to a new or existing version"
        Resources = @{
            "Broadcaster.Admin.DependencyStatus" = "GET"
            "Broadcaster.Admin.DependencyUpdate" = "GET", "PATCH"
        }
        Action = {
            $status = (irm "$bc/DependencyStatus" @getSettingsRaw)[0]
            $nextAvailable = (irm "$bc/DependencyUpdate" @getSettingsRaw)[0]
            $status | Out-Host
            if ($nextAvailable.IsNewerThanCurrent) {
                Write-Host "> A new dependency bundle is available!" -ForegroundColor Green
                $response = Read-Host "> Enter 'update' to update the dependencies or 'cancel' to cancel"
                $response = $response.Trim().ToLower()
                if ($response -ieq "update") {
                    Update-Dependencies
                }
            } else {
                Write-Host "> Dependencies are up-to-date"
            }
        }
    }
)
#endregion
#region Terminals
$launchTerminalsCommands = @(
    @{
        Command = "AccessToken"
        Description = "Enters the Broadcaster access token terminal"
        Resources = @{
            "Broadcaster.Auth.AccessToken" = "GET"
        }
        Action = { Enter-Terminal "AccessToken.Commands" }
    }
    @{
        Command = "Shell"
        Description = "Enters the Broadcaster shell terminal"
        Hide = $true
        Resources = @{
            "RESTable.Shell" = "GET"
        }
        Action = { Enter-Terminal "Shell" }
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
                Write-Host "Less celebration, more concentration! You've had your fun..."
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

$availabeResourcesMap = @{ }
$availableResourcesJob = irm "$bc/AvailableResource" -Cr $credentials -AllowUnencryptedAuthentication -He @{ Accept = "application/json;raw=true" } &

function Command-HasAccess
{
    param($command)
    if ($command.Resources) {
        if ($availableResourcesJob -ne "completed") {
            $list = Receive-Job $availableResourcesJob -Wait
            foreach ($r in $list) {
                $availabeResourcesMap[$r.Name] = $r.Methods
            }
        }
        foreach ($resource in $command.Resources.Keys) {
            $granted = $availabeResourcesMap[$resource]
            foreach ($required in $command.Resources[$resource]) {
                if ($granted -notcontains $required) {
                    return $false;
                }
            }
        }
    }
    return $true
}

function Has-Access
{
    param($resource, $method)
    if ($availableResourcesJob -ne "completed") {
        $list = Receive-Job $availableResourcesJob -Wait
        foreach ($r in $list) {
            $availabeResourcesMap[$r.Name] = $r.Methods
        }
    }
    $granted = $availabeResourcesMap[$resource]
    return $granted -contains $method.ToUpper()
}

function Write-Commands
{
    param($label, $commands)
    $list = @()
    foreach ($c in $commands | Sort-Object -Property Command) {
        if ($c.Hide) {
            continue;
        }
        if (Command-HasAccess $c) {
            $aliases = $c.Alias ? ", " + $c.Alias : ""
            $list += [pscustomobject]@{
                Command = $c.Command + $aliases + "    "
                Description = $c.Description
            }
        }
    }
    if ($list.Count -eq 0) {
        return
    }
    Write-Host "$label`:" -ForegroundColor Yellow
    $list | Format-Table | Out-Host
}


function WriteAll-Commands
{
    Write-Host
    Write-Commands "STATUS" $getStatusCommands
    Write-Commands "MODIFY" $modifyCommands
    Write-Commands "DASHBOARDS" $dashboardCommands
    Write-Commands "REMOTE DEPLOYMENT" $remoteDeploymentCommands
    Write-Commands "TERMINALS" $launchTerminalsCommands
    Write-Commands "OTHER" $otherCommands
}

function Write-HelpInfo
{
    Write-Host "> Use " -NoNewline
    Write-Host "help" -NoNewLine -ForegroundColor Yellow
    Write-Host " to list available commands"
}

$allCommands = $getStatusCommands + $modifyCommands + $remoteDeploymentCommands + $dashboardCommands + $launchTerminalsCommands + $otherCommands

function Call($command)
{
    $foundCommand = $false
    foreach ($c in $allCommands) {
        if ($c.Command -ieq $command -or $c.Alias -ieq $command) {
            $foundCommand = $true
            if (Command-HasAccess $foundCommand) {
                & $c.Action
            } else {
                Write-Host "> You don't have permission to use command $resource" -ForegroundColor Red
            }
            return
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

if ($initialCommand) {
    Call $initialCommand.Trim().ToLower()
}
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
