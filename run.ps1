if ($PSVersionTable.PSVersion.Major -lt 7) {
    # Upgrade to PowerShell 7
    $coreVersion = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions\*" -Name "SemanticVersion" -ErrorAction SilentlyContinue
    if (!$coreVersion -or !$coreVersion.StartsWith("7")) {
        Write-Host -NoNewline "> Installing PowerShell 7... "
        iex "& { $( irm 'https://aka.ms/install-powershell.ps1' ) } -UseMSI -Quiet" *>&1 | Out-Null
        $env:path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        Write-Host "Done!"
    }
}
pwsh -Command "irm raw.githubusercontent.com/ByHeads/bcman/main/bcman.ps1 | iex"
