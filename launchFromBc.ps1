# This is an example of a script that launches a hosted Broadcaster Manager from a Broadcaster

# If using http instead of https, you need to set the AllowUnencryptedAuthentication flag
# $PSDefaultParameterValues['Invoke-RestMethod:AllowUnencryptedAuthentication'] = $true

$url = Read-Host "> Enter the URL of the Broadcaster" # Or hardcode it if appropriate
$apiKey = Read-Host "> Enter the API key to use" -AsSecureString
$scriptText = irm "$url/api/bcman" -Cr ([PSCredential]::new("any", $apiKey))
$scriptBlock = [scriptblock]::Create($scriptText)
icm $scriptBlock -Arg $url, $apiKey
