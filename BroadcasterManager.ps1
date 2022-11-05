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

$bc = $null
while (!$bc) {
    $a = Read-Host "> Enter the URL to the Broadcaster"
    $a = $a.Trim();
    $r = $null
    if (!$a.StartsWith("https://")) {
        $a = "https://" + $a
    }
    if (!$a.EndsWith("/api")) {
        $a += "/api"
    }
    if (![System.Uri]::TryCreate($a, 'Absolute', [ref]$r)) {
        Write-Host "Invalid URI format. Try again."
        continue
    }
    try {
        $options = irm $a -Method "OPTIONS" -TimeoutSec 5
        if (($options.Status -eq "success") -and ($options.Data[0].Resource -eq "RESTable.AvailableResource")) {
            $bc = $a
            break
        }
    }
    catch { }
    Write-Host "Found no Broadcaster API responding at $a. Ensure that the URL was input correctly and that the Broadcaster is running"
}
$credentials = $null
while (!$credentials) {
    $apiKey = Read-Host "> Enter the API key to use" -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential ("any", $apiKey)
    $result = irm "$bc/RESTable.Blank" -Credential $cred -TimeoutSec 5
    if (($result.Status -eq "success")) {
        $credentials = $cred
        break
    }
    Write-Host "Invalid API key. Ensure that the key has been given a proper access scope, including the RESTable.* resources"
}

$settings = @{
    Credential = $credentials
    TimeoutSec = 5
    Headers = @{ Accept = "application/json;raw=true" }
}

Write-Host "Connection established!"

#endregion

$commands = @(
@{
    Command = "Status"
    Description = "Prints the current status for all Receivers"
    Action = {
        irm "$bc/ReceiverLog/_/select=WorkstationId,LastActive" @settings | Out-Host
    }
}
@{
    Command = "Config"
    Description = "Prints the configuration of the Broadcaster"
    Action = {
        irm "$bc/Config" @settings | Out-Host
    }
}
@{
    Command = "Details"
    Description = "Prints details about a specific Receiver"
    Action = {
        $message = "Enter workstation ID or 'list' for a list of workstation IDs to choose from"
        $input = Read-Host $message
        while ($input -ieq "list") {
            irm "$bc/ReceiverLog/_/select=WorkstationId" @settings | Out-Host
            $input = Read-Host $message
        }
        $formattedOption = $input.Trim();
        $response = irm "$bc/ReceiverLog/WorkstationId=$formattedOption/select=Modules" @settings | Select-Object -first 1
        Write-Host ""
        $response.Modules.PSObject.Properties | ForEach-Object {
            Write-Host ($_.Name + ":") -ForegroundColor Yellow
            @($_.Value) | Out-Host
        }
        Write-Host ""
    }
}
@{
    Command = "VersionInfo"
    Description = "Prints details about a the installed software on Receivers"
    Action = {
        $softwareProduct = $null
        while (!$softwareProduct) {
            $input = Read-Host "Enter software product name: WpfClient, PosServer or Receiver"
            switch ( $input.Trim().ToLower()) {
                "receiver" { $softwareProduct = "Receiver"; break }
                "wpfclient" { $softwareProduct = "WpfClient"; break }
                "posserver" { $softwareProduct = "PosServer"; break }
                default { Write-Host "Unrecognized software product name $input"; break }
            }
        }
        $response = irm "$bc/ReceiverLog/_/rename=Modules.$softwareProduct->Product&select=WorkstationId,LastActive,Product" @settings
        $items = @()
        foreach ($r in $response) {
            $item = [pscustomobject]@{
                WorkstationId = $r.WorkstationId
                LastActive = $r.LastActive
                IsInstalled = $r.Product.IsInstalled
                IsRunning = $r.Product.IsRunning
                CurrentVersion = $r.Product.CurrentVersion
                DeployedVersions = $r.Product.DeployedVersions
                LaunchedVersion = $r.Product.LaunchedVersion
            }
            $items += $item
        }
        @($items) | Format-Table | Out-Host
    }
}
@{
    Command = "ReplicationInfo"
    Description = "Prints details about a the replication status of Receivers"
    Action = {
        $response = irm "$bc/ReceiverLog/_/rename=Modules.Replication->Replication&select=WorkstationId,LastActive,Replication" @settings
        $items = @()
        foreach ($r in $response) {
            $item = [pscustomobject]@{
                WorkstationId = $r.WorkstationId
                LastActive = $r.LastActive
                ReplicationVersion = $r.Replication.ReplicationVersion
                AwaitsInitialization = $r.Replication.AwaitsInitialization
            }
            $items += $item
        }
        @($items) | Format-Table | Out-Host
    }
}
@{
    Command = "Exit"
    Description = "Closes the Broadcaster Manager"
    Action = {
        Write-Host "> Exiting..."
        Exit
    }
}
)

#region Read-eval loop

function Get-Commands
{
    $list = @()
    foreach ($c in $commands) {
        $list += [pscustomobject]@{
            Command = $c.Command + "    "
            Description = $c.Description
        }
    }
    $list | Format-Table | Out-Host
}

Get-Commands

while ($true) {
    $input = Read-Host "> Enter a command"
    $command = $input.Trim().ToLower()
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
