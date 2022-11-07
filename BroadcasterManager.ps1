#region Welcome splash

Write-Host ""
Write-Host "                   ___                  _            _           "
Write-Host "                  | _ )_ _ ___  __ _ __| |__ __ _ __| |_ ___ _ _ "
Write-Host "      |\ |\       | _ \ '_/ _ \/ _`` / _`` / _/ _`` (_-<  _/ -_) '_|"
Write-Host "   |\ || || |\    |___/_| \___/\__,_\__,_\__\__,_/__/\__\___|_|  "
Write-Host "   || || || ||     __  __                                        "
Write-Host "   \| || || \|    |  \/  |__ _ _ _  __ _ __ _ ___ _ _            "
Write-Host "      \| \|       | |\/| / _`` | ' \/ _`` / _`` / -_) '_|           "
Write-Host "                  |_|  |_\__,_|_||_\__,_\__, \___|_|             "
Write-Host "                                        |___/                    "
Write-Host -NoNewline " To quit at any time, press "
Write-Host -ForegroundColor:Yellow "Ctrl+C"
Write-Host ""

#endregion
#region Setup Broadcaster connection

function Get-BroadcasterUrl
{
    $url = Read-Host "> Enter the URL to the Broadcaster"
    $url = $url.Trim();
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
Write-Host "Connection established!"

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
                return;
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
        $sender.Stop()
        $sender.Dispose()
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
    $input = $input.Trim();
    if ($input -eq "") {
        Write-Host "Invalid terminal name"
        return Get-WorkstationId
    }
    return $input
}

function Get-SoftwareProduct
{
    $input = Read-Host "> Enter software product name: WpfClient, PosServer or Receiver"
    switch ( $input.Trim().ToLower()) {
        "receiver" { return "Receiver" }
        "wpfclient" { return "WpfClient" }
        "posserver" { return "PosServer" }
        default {
            Write-Host "Unrecognized software product name $input"
            return Get-SoftwareProduct
        }
    }
}

function Get-WorkstationId
{
    $input = Read-Host "> Enter workstation ID or 'list' for a list of workstation IDs to choose from"
    if ($input -ieq "list") {
        irm "$bc/ReceiverLog/_/select=WorkstationId" @getSettings | Out-Host
        return Get-WorkstationId
    }
    $input = $input.Trim();
    if ($input -eq "") {
        Write-Host "Invalid workstation ID format"
        return Get-WorkstationId
    }
    return $input
}

function Get-SoftwareProductVersion
{
    param($softwareProduct)
    $message = "> Enter $softwareProduct version to deploy, 'list' for deployable versions of $softwareProduct or 'cancel' to cancel"
    $input = Read-Host $message
    if ($input -ieq "list") {
        Write-Host "Listing deployable versions of $softwareProduct from the build server. Be patient..."
        $versions = irm "$bc/RemoteFile/ProductName=$softwareProduct/order_asc=Version&select=Version&distinct=true" @getSettings
        Write-Host ""
        foreach ($v in $versions) {
            Write-Host $v.Version
        }
        Write-Host ""
        return Get-SoftwareProductVersion $softwareProduct
    }
    if ($input -ieq "cancel") {
        return $null
    }
    $r = $null
    if (![System.Version]::TryParse($input, [ref]$r)) {
        Write-Host "Invalid version format. Try again."
        return Get-SoftwareProductVersion $softwareProduct
    }
    return $r
}

#endregion

$commands = @(
@{
    Command = "Status"
    Description = "Prints the current status for all Receivers"
    Action = {
        irm "$bc/ReceiverLog/_/select=WorkstationId,LastActive" @getSettings | Out-Host
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
    Command = "Launch"
    Description = "Enters the Broadcaster LaunchCommands terminal"
    Action = {
        Enter-Terminal "LaunchCommands"
        Get-Commands
    }
}
@{
    Command = "Shell"
    Description = "Enters the Broadcaster shell terminal"
    Action = {
        Enter-Terminal "Shell"
        Get-Commands
    }
}
@{
    Command = "Terminal"
    Description = "Enters a Broadcaster terminal"
    Action = {
        Enter-Terminal (Get-Terminal)
        Get-Commands
    }
}
@{
    Command = "Deploy"
    Description = "Lists and downloads deployable software versions to the Broadcaster"
    Action = {
        $softwareProduct = Get-SoftwareProduct
        $version = Get-SoftwareProductVersion $softwareProduct
        if ($version) {
            $body = @{ Deploy = $true } | ConvertTo-Json
            $ma = $version.Major; $mi = $version.Minor; $b = $version.Build; $r = $version.Revision
            $versionConditions = "version.major=$ma&version.minor=$mi&version.build=$b&version.revision=$r"
            Write-Host "$softwareProduct $version is now downloading to the Broadcaster. Be patient..."
            $result = irm "$bc/RemoteFile/ProductName=$softwareProduct&$versionConditions/unsafe=true" -Body $body @patchSettings
            if ($result.Status -eq "success") {
                Write-Host "$softwareProduct $version was successfully deployed"
            }
            else {
                Write-Host "An error occured while deploying $softwareProduct $version. This version might be partially deployed. Partially deployed versions are not deployed to clients"
                Write-Host $result
            }
        }
    }
}
@{
    Command = "DeploymentInfo"
    Description = "Prints details about deployed software versions on the Broadcaster"
    Action = {
        irm "$bc/File/_/select=ProductName,Version&distinct=true" @getSettings | Out-Host
    }
}
@{
    Command = "VersionInfo"
    Description = "Prints details about a the installed software on Receivers"
    Action = {
        $softwareProduct = Get-SoftwareProduct
        $response = irm "$bc/ReceiverLog/_/rename=Modules.$softwareProduct->Product&select=WorkstationId,LastActive,Product" @getSettings
        $items = @()
        foreach ($r in $response) {
            $items += [pscustomobject]@{
                WorkstationId = $r.WorkstationId
                LastActive = $r.LastActive
                IsInstalled = $r.Product.IsInstalled
                IsRunning = $r.Product.IsRunning
                CurrentVersion = $r.Product.CurrentVersion
                DeployedVersions = $r.Product.DeployedVersions
                LaunchedVersion = $r.Product.LaunchedVersion
            }
        }
        $items | Format-Table | Out-Host
    }
}
@{
    Command = "ReplicationInfo"
    Description = "Prints details about a the replication status of Receivers"
    Action = {
        $response = irm "$bc/ReceiverLog/_/rename=Modules.Replication->Replication&select=WorkstationId,LastActive,Replication" @getSettings
        $items = @()
        foreach ($r in $response) {
            $items += [pscustomobject]@{
                WorkstationId = $r.WorkstationId
                LastActive = $r.LastActive
                ReplicationVersion = $r.Replication.ReplicationVersion
                AwaitsInitialization = $r.Replication.AwaitsInitialization
            }
        }
        $items | Format-Table | Out-Host
    }
}
@{
    Command = "Details"
    Description = "Prints details about a specific Receiver"
    Action = {
        function Details
        {
            $workstationId = Get-WorkstationId
            $response = irm "$bc/ReceiverLog/WorkstationId=$workstationId/select=Modules" @getSettings | Select-Object -first 1
            if (!$response) {
                Write-Host "Found no Receiver with workstation ID $workstationId"
                return Details
            }
            else {
                Write-Host ""
                $response.Modules.PSObject.Properties | ForEach-Object {
                    Write-Host ($_.Name + ":") -ForegroundColor Yellow
                    $_.Value | Out-Host
                }
                Write-Host ""
            }
        }
        Details
    }
}
)

#region Read-eval loop

function Get-Commands
{
    $list = @()
    foreach ($c in $commands | Sort-Object -Property Command) {
        $list += [pscustomobject]@{
            Command = $c.Command + "    "
            Description = $c.Description
        }
    }
    $list += [pscustomobject]@{ }
    $list += [pscustomobject]@{ Command = "Help"; Description = "Prints the commands list" }
    $list += [pscustomobject]@{ Command = "Exit"; Description = "Closes the Broadcaster Manager" }
    $list | Format-Table | Out-Host
}

Get-Commands

while ($true) {
    $input = Read-Host "> Enter a command"
    $command = $input.Trim().ToLower()
    if ($command -ieq "exit") {
        Write-Host "> Exiting..."
        Exit;
    }
    if ($command -ieq "help") {
        Get-Commands
        continue;
    }
    $foundCommand = $false;
    foreach ($c in $commands) {
        if ($c.Command -ieq $command) {
            $foundCommand = $true;
            & $c.Action
        }
    }
    if (!$foundCommand) {
        Write-Host "> Unknown command $input"
        Start-Sleep 1
        Get-Commands
    }
}

#endregion
