if ($PSVersionTable.PSVersion.Major -lt 7) {
    # Upgrade to PowerShell 7
    $coreVersion = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions\*" -Name "SemanticVersion" -ErrorAction SilentlyContinue
    if (!$coreVersion -or !$coreVersion.StartsWith("7")) {
        Write-Host -NoNewline "> Installing PowerShell 7... "
        iex "& { $( irm 'https://aka.ms/install-powershell.ps1' ) } -UseMSI -Quiet" *>&1 | Out-Null
        $env:path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        Write-Host "Done!"
    }
    & pwsh.exe -Command { irm 'https://raw.githubusercontent.com/ByHeads/BroadcasterManager/master/BroadcasterManager.ps1' | iex }
    return
}

#region Welcome splash

Write-Host ""
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
Write-Host ""

#endregion
#region Setup Broadcaster connection

function Get-BroadcasterUrl
{
    $url = Read-Host "> Enter the URL to the Broadcaster"
    $url = $url.Trim()
    if (!$url.StartsWith("https://")) {
        $url = "https://" + $url
    }
    if (!$url.EndsWith("/api")) {
        $url += "/api"
    }
    $r = $null
    if (![System.Uri]::TryCreate($url, 'Absolute', [ref]$r)) {
        Write-Host "Invalid URI format. Try again."
        return Get-BroadcasterUrl
    }
    try {
        $options = irm $url -Method "OPTIONS" -TimeoutSec 5
        if (($options.Status -eq "success") -and ($options.Data[0].Resource -eq "RESTable.AvailableResource")) {
            return $url
        }
    }
    catch { }
    Write-Host "Found no Broadcaster API responding at $url. Ensure that the URL was input correctly and that the Broadcaster is running"
    return Get-BroadcasterUrl
}

function Get-Credentials
{
    $apiKey = Read-Host "> Enter the API key to use" -AsSecureString
    $credentials = New-Object System.Management.Automation.PSCredential ("any", $apiKey)
    try {
        $result = irm "$bc/RESTable.Blank" -Credential $credentials -TimeoutSec 5
        if (($result.Status -eq "success")) {
            return $credentials
        }
    }
    catch { }
    Write-Host "Invalid API key. Ensure that the key has been given a proper access scope, including the RESTable.* resources"
    return Get-Credentials
}

$bc = Get-BroadcasterUrl
$credentials = Get-Credentials
Write-Host "Broadcaster connection confirmed!" -ForegroundColor "Green"

$getSettings = @{
    Method = "GET"
    Credential = $credentials
    Headers = @{ Accept = "application/json;raw=true" }
}

$patchSettings = @{
    Method = "PATCH"
    Credential = $credentials
    Headers = @{ "Content-Type" = "application/json" }
}

$postSettings = @{
    Method = "POST"
    Credential = $credentials
    Headers = @{ "Content-Type" = "application/json" }
}

$deleteSettings = @{
    Method = "DELETE"
    Credential = $credentials
}

#endregion 
#region Lib

function Enter-Terminal
{
    param($terminal)
    Write-Host "Now entering a Broadcaster terminal. Send 'exit' to return to the Broadcaster Manager" -ForegroundColor "Yellow"
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
        irm "$bc/AvailableResource/Kind=TerminalResource/select=Name" @getSettings | Out-Host
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
            Write-Host "Sorry, I can't really deploy elephants ¯\_(ツ)_/¯ ... only squirrels, beavers and the occasional hedgehog"
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
    $existingGroups = irm "$bc/WorkstationGroups" @getSettings | Select-Object -first 1
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
            Write-Host ""
            $groups = irm "$bc/WorkstationGroups" @getSettings | Select-Object -first 1
            $groups | Get-Member -MemberType NoteProperty | ForEach-Object {
                $_.Name | Out-Host
            }
            Write-Host ""
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
    return (irm "$bc/WorkstationGroups/_/select=$group" @getSettings)[0].$group
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
                Write-Host ""
                $members | Out-Host
                Write-Host ""
            }
            Manage-WorkstationGroup $group
        }
        "delete"{
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
    $input = Read-Host "> Enter workstation ID, 'list' for a list of workstation IDs to choose from or 'cancel' to cancel"
    switch ( $input.Trim().ToLower()) {
        "list" {
            irm "$bc/ReceiverLog/_/select=WorkstationId" @getSettings | Out-Host
            return Get-WorkstationId
        }
        "" {
            Write-Host "Invalid workstation ID format"
            return Get-WorkstationId
        }
        "cancel" { return $null }
        default { return $input }
    }
}

function Get-DeployableSoftwareProductVersion
{
    param($softwareProduct)
    $message = "> Enter $softwareProduct version to deploy, 'list' for deployable versions of $softwareProduct or 'cancel' to cancel"
    $input = Read-Host $message
    $input = $input.Trim()
    if ($input -ieq "list") {
        Write-Host "Listing deployable versions of $softwareProduct from the build server. Be patient..."
        $versions = irm "$bc/RemoteFile/ProductName=$softwareProduct/order_asc=Version&select=Version&distinct=true" @getSettings
        if ($versions.Count -eq 0) {
            Write-Host "Found no deployable versions of $softwareProduct"
        }
        else {
            Write-Host ""
            foreach ($v in $versions) {
                Write-Host $v.Version
            }
            Write-Host ""
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
        $versions = irm "$bc/File/ProductName=$softwareProduct/order_asc=Version&select=Version&distinct=true" @getSettings
        if ($versions.Count -eq 0) {
            Write-Host "Found no launchable versions of $softwareProduct"
        }
        else {
            Write-Host ""
            foreach ($v in $versions) {
                Write-Host $v.Version
            }
            Write-Host ""
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

function Get-RuntimeId
{
    param($softwareProduct)
    $message = "> Enter runtime ID for the version to launch, press enter for 'win7-x64' or 'cancel' to cancel"
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
    $input = Read-Host "> Enter date and time (UTC) for the launch or 'cancel' to cancel. Example: 2023-05-01 12:15"
    $input = $input.Trim()
    if ($input -ieq "cancel") {
        return $null
    }
    $dateTime = $null
    try {
        return Get-Date ([DateTime]$input) -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "Invalid date and time format. Example: 2023-05-01 12:15"
        return Get-DateTime
    }
}

function Get-LaunchSchedule
{
    $launches = irm "$bc/LaunchSchedule" @getSettings
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
                "DateTime (UTC)" = $l.DateTime
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

$getStatusCommands = @(
@{
    Command = "Status"
    Description = "Prints a status overview of the Broadcaster"
    Action = {
        $config = (irm "$bc/Config/_/select=Version,ComputerName&rename=General.CurrentVersion->Version,COMPUTERNAME->ComputerName" @getSettings)[0]
        $receiverCount = (irm "$bc/Receiver" @getSettings).Count
        $nextAvailableVersion = (irm "$bc/BroadcasterUpdate/_/order_desc=Version&limit=1" @getSettings)[0].Version
        Write-Host ""
        Write-Host "Host" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Broadcaster URL: $bc"
        Write-Host "Host computer: $( $config.ComputerName )"
        Write-Host "Connected receivers: $receiverCount"
        Write-Host ""
        Write-Host "Broadcaster version" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Current version: " -NoNewline
        Write-Host $config.Version
        Write-Host "Latest version: " -NoNewline
        if ($nextAvailableVersion) {
            Write-Host $nextAvailableVersion -ForegroundColor Green -NoNewline
            Write-Host " (use " -NoNewline
            Write-Host "Update" -ForegroundColor Yellow -NoNewline
            Write-Host " to update now)"
        }
        else {
            Write-Host $config.Version
        }
        Write-Host ""
    }
}
@{
    Command = "ReceiverStatus"
    Description = "Prints the status for all connected Receivers"
    Action = {
        $list = irm "$bc/Receiver/_/select=WorkstationId,LastActive" @getSettings
        if ($list.Count -eq 0) { Write-Host "Found no connected Receivers" }
        else { $list | Sort-Object -Property "WorkstationId" | Out-Host }
    }
}
@{
    Command = "ReceiverLog"
    Description = "Prints the last recorded status for all connected and disconnected Receivers"
    Action = {
        $list = irm "$bc/ReceiverLog/_/select=WorkstationId,LastActive" @getSettings
        if ($list.Count -eq 0) { Write-Host "Found no connected or disconnected Receivers" }
        else { $list | Sort-Object -Property "WorkstationId" | Out-Host }
    }
}
@{
    Command = "Config"
    Description = "Prints the configuration of the Broadcaster"
    Action = {
        irm "$bc/Config" @getSettings | Out-Host
    }
}
@{
    Command = "DeploymentInfo"
    Description = "Prints details about deployed software versions on the Broadcaster"
    Action = {
        $list = irm "$bc/File/_/select=ProductName,Version&distinct=true" @getSettings
        if ($list.Count -eq 0) { Write-Host "Found no deployed software versions" }
        else { $list | Sort-Object -Property "ProductName" | Out-Host }
    }
}
@{
    Command = "VersionInfo"
    Description = "Prints details about a the installed software on Receivers"
    Action = $versionInfo_c = {
        $softwareProduct = Get-SoftwareProduct
        if (!$softwareProduct) {
            return
        }
        $response = irm "$bc/ReceiverLog/_/rename=Modules.$softwareProduct->Product&select=WorkstationId,LastActive,Product" @getSettings
        if ($response.Count -eq 0) {
            Write-Host "Found no connected or disconnected Receivers"
            return
        }
        $items = @()
        foreach ($r in $response) {
            $items += [pscustomobject]@{
                WorkstationId = $r.WorkstationId
                LastActive = $r.LastActive
                IsInstalled = $r.Product.IsInstalled
                IsRunning = $r.Product.IsRunning
                CurrentVersion = $r.Product.CurrentVersion
                DeployedVersions = $r.Product.DeployedVersions | Sort-Object
                LaunchedVersion = $r.Product.LaunchedVersion
            }
        }
        $items | Sort-Object -Property "WorkstationId" | Format-Table | Out-Host
        & $versionInfo_c
    }
}
@{
    Command = "ReplicationInfo"
    Description = "Prints details about a the replication status of Receivers"
    Action = {
        $response = irm "$bc/ReceiverLog/_/rename=Modules.Replication->Replication&select=WorkstationId,LastActive,Replication" @getSettings
        if ($response.Count -eq 0) {
            Write-Host "Found no connected or disconnected Receivers"
            return
        }
        $items = @()
        foreach ($r in $response) {
            $items += [pscustomobject]@{
                WorkstationId = $r.WorkstationId
                LastActive = $r.LastActive
                ReplicationVersion = $r.Replication.ReplicationVersion
                AwaitsInitialization = $r.Replication.AwaitsInitialization
            }
        }
        $items | Sort-Object -Property "WorkstationId" | Format-Table | Out-Host
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
        $response = irm "$bc/ReceiverLog/WorkstationId=$workstationId/select=Modules" @getSettings | Select-Object -first 1
        if (!$response) {
            Write-Host "Found no Receiver with workstation ID $workstationId"
            & $receiverDetails_c
        }
        else {
            Write-Host ""
            $response.Modules.PSObject.Properties | Sort-Object -Property "Name" | ForEach-Object {
                Write-Host ($_.Name + ":") -ForegroundColor Yellow
                Write-Host ""
                $value = $_.Value | select -ExcludeProperty "@Type", "ProductName"
                $ht = @{ }
                $value.PSObject.Properties | Foreach { $ht[$_.Name] = $_.Value }
                if (($ht.Count -eq 0) -and ($_.Name -eq "Downloads")) {
                    Write-Host "No download tasks"
                }
                else {
                    foreach ($key in $ht.Keys | Sort-Object) {
                        $val = $ht[$key] | ConvertTo-Json
                        Write-Host "$key`: $val"
                    }
                }
                Write-Host ""
            }
            Write-Host ""
        }
    }
}
)
$modifyCommands = @(
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
        Write-Host "Attempting to download $softwareProduct $version to the Broadcaster. Be patient..."
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
            $runtimeId = Get-RuntimeId
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
                DateTime = $datetime
            } | ConvertTo-Json
            $result = irm "$bc/LaunchSchedule" -Body $body @postSettings
            if ($result.Status -eq "success") {
                Write-Host "A launch was successfully scheduled"
                & $launch_c
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
        $version = (irm "$bc/Config/_/select=Version&rename=General.CurrentVersion->Version" @getSettings)[0].Version
        $nextAvailable = (irm "$bc/BroadcasterUpdate/_/order_desc=Version&limit=1" @getSettings)[0]
        if (!$nextAvailable) {
            Write-Host "> This Broadcaster is already running the latest version " -NoNewline
            Write-Host $version -ForegroundColor Green -NoNewline
            Write-Host ""
            return
        }
        Write-Host "> This Broadcaster is running version $version. A new version " -NoNewline
        Write-Host $nextAvailable.Version -ForegroundColor Green -NoNewline
        Write-Host " is available"
        $response = Read-Host "> Enter 'update' to update and restart the Broadcaster right now or 'cancel' to cancel"
        $response = $response.Trim().ToLower()
        if ($response -ieq "update") {
            Write-Host "> Updating Broadcaster to version " -NoNewline
            Write-Host $nextAvailable.Version -ForegroundColor Green -NoNewline
            Write-Host " * " -NoNewline
            $out = Start-Job -ScriptBlock {
                $fullName = [System.Web.HttpUtility]::UrlEncode($using:nextAvailable.FullName)
                $body = @{ Install = $true } | ConvertTo-Json
                $lbc = $using:bc; $lpatchSettings = $using:patchSettings;
                irm "$lbc/BroadcasterUpdate/FullName=$fullName" -Body $body @lpatchSettings
            }
            while ($true) {
                Write-Host "* " -NoNewline
                $interval = Start-Sleep 3 &
                try {
                    $currentVersion = (irm "$bc/Config/_/select=Version&rename=General.CurrentVersion->Version" -TimeoutSec 3 @getSettings -ErrorAction SilentlyContinue)[0].Version
                    if ($currentVersion -eq $nextAvailable.Version) {
                        Write-Host "Update complete!" -ForegroundColor Green -NoNewline
                        Write-Host ""
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
$otherCommands = @(
@{ Command = "Help"; Description = "Prints the commands list"; Action = { WriteAll-Commands } }
@{ Command = "Exit"; Description = "Closes the Broadcaster Manager"; Action = { Exit } }
)

#region Read-eval loop

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
    Write-Host ""
    Write-Host "GET STATUS:" -ForegroundColor Yellow
    Write-Commands $getStatusCommands
    Write-Host "MODIFY BROADCASTER:" -ForegroundColor Yellow
    Write-Commands $modifyCommands
    Write-Host "BROADCASTER TERMINALS:" -ForegroundColor Yellow
    Write-Commands $launchTerminalsCommands
    Write-Host "OTHER:" -ForegroundColor Yellow
    Write-Commands $otherCommands
}

function Write-HelpInfo
{
    Write-Host "Enter " -NoNewline
    Write-Host "help" -NoNewLine -ForegroundColor Yellow
    Write-Host " to print a list of all commands"
}

Write-Host ""
Write-HelpInfo
Write-Host ""

$allCommands = $getStatusCommands + $modifyCommands + $launchTerminalsCommands + $otherCommands

while ($true) {
    $input = Read-Host "> Enter a command"
    $command = $input.Trim().ToLower()
    if ($command -ieq "exit") {
        Write-Host "> Exiting..."
        Exit
    }
    if ($command -ieq "hi" -or $command -ieq "hello") {
        Write-Host "Well hello there!"
        continue
    }
    if ($command -ieq "help") {
        WriteAll-Commands
        continue
    }
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
