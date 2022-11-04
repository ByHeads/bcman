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

$broadcasterUrl = $null
while (!$broadcasterUrl) {
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
            $broadcasterUrl = $a
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
    $result = irm "$broadcasterUrl/RESTable.Blank" -Credential $cred -TimeoutSec 5
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

#endregion

Write-Host "Connection established!"

$commands = [ordered]@{
    Status = "Prints the current status for all receivers"
    Config = "Prints the configuration of the Broadcaster"
    "Exit" = "Closes the Broadcaster Manager"
}

Write-Host "> Available commands:"
Write-Host ($commands | Out-String)

function Get-Data
{
    param($uri); irm "$broadcasterUrl/$uri" @settings | Out-Host
}

$exit = $false
while (!$exit) {
    $input = Read-Host "> Enter a command"
    $command = $input.ToLower()
    switch ($command) {
        "config" {
            Get-Data "Config"
            break;
        }
        "status" {
            Get-Data "ReceiverLog/_/select=WorkstationId,LastActive"
            break;
        }
        "exit" {
            $exit = $true;
            Write-Host "> Exiting..."
            break
        }
    }
}
