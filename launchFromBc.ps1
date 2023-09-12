# This is an example of a script that launches a hosted Broadcaster Manager from a Broadcaster

$url = Read-Host "> Enter the URL of the Broadacster (beginning with http:// or https://)" # Or hardcode it if appropriate
$apiKey = Read-Host "> Enter the API key to use" -AsSecureString
$scriptText = irm "$url/api/bcman" -Cr ([PSCredential]::new("any", $apiKey))
icm ([scriptblock]::Create($scriptText)) -Arg $url, $apiKey
