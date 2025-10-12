using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$Body = $Request.Body

if ([string]::IsNullOrEmpty($Request.Body)) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{
                error = 'Request body is empty.'
            }
        })
}

$Action = $Body.action

if ($Action -notin @('push', 'push_push')) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{
                error = "Action $Action is not supported."
            }
        })
}

$RegistryURL = $Body.request.host
$RegistryName = $RegistryURL.Split('.')[0]
$RepositoryName = $Body.target.repository
$Digest = $Body.target.digest
$Tag = $Body.target.tag
$Reference = $Digest

$RefreshToken = Get-ACRRefreshToken -RegistryURL $RegistryURL -Verbose
$AccessToken = Get-ACRAccessToken -RegistryURL $RegistryURL -RefreshToken $RefreshToken -Scope "repository:$RepositoryName`:pull"
$Manifest = Get-ACRManifest -RegistryURL $RegistryURL -RepositoryName $RepositoryName -Reference $Reference -AccessToken $AccessToken -ManifestType oci

$DocURI = $Manifest.annotations.'org.opencontainers.image.documentation'
$AdditionalTags = Get-ACRAdditionalTags

$Content = @"
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "summary": "A new module has been published to the registry",
    "sections": [
        {
            "activityTitle": "[$RepositoryName] was published to the registry!",
            "activitySubtitle": "$RegistryURL",
            "activityImage": "http://code.benco.io/icon-collection/azure-icons/Container-Registries.svg",
            "facts": [
                {
                    "name": "Module name",
                    "value": "``$RepositoryName``"
                },
                {
                    "name": "Version",
                    "value": "``$Tag``"
                },
                {
                    "name": "Reference in code",
                    "value": "``br:$RegistryURL/$RepositoryName`:$Tag``"
                },
                {
                    "name": "Other tags",
                    "value": "``$AdditionalTags``"
                },
                {
                    "name": "Digest",
                    "value": "``$Reference``"
                },
            ],
            "markdown": true
        }
    ],
    "potentialAction": [
        {
            "@type": "OpenUri",
            "name": "Read the docs",
            "targets": [
                {
                    "os": "default",
                    "uri": "$DocURI"
                }
            ]
        }
    ]
}
"@

$webhookURI = $env:TeamsWebhookURI
if ([string]::IsNullOrEmpty($webhookURI)) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::ExpectationFailed
            Body       = @{
                error = 'WebhookURI is not set. Check if the TeamsWebhookURI value is set in app settings.'
            }
        })
}

$params = @{
    'URI'         = $WebhookURI
    'Method'      = 'POST'
    'Body'        = $Content
    'ContentType' = 'application/json'
}
$response = Invoke-RestMethod @params

$body = @{
    Action       = $Action
    RegistryURL  = $RegistryURL
    RegistryName = $RegistryName
    repository   = $RepositoryName
    tag          = $Tag
    digest       = $Digest
    Manifest     = $Manifest
    DocURI       = $DocURI
    Content      = $Content
    WebhookURI   = $WebhookURI
    response     = $response
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
