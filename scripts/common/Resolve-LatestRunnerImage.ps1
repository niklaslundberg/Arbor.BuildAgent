[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Repository = 'actions/runner-images',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OsName = 'windows2025'
)

$ProgressPreference = 'SilentlyContinue'

$uri = "https://api.github.com/repos/$Repository/releases/latest"
$headers = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'Arbor.BuildAgent'
}

$release = $null
$fetchError = $null

try {
    $release = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
} catch {
    $fetchError = $_.Exception.Message
}

[pscustomobject]@{
    Repository      = $Repository
    LatestTag       = $release?.tag_name
    ReleaseName     = $release?.name
    PublishedAtUtc  = $release?.published_at
    HtmlUrl         = $release?.html_url
    RequestedOsName = $OsName
    Note            = 'Use this release reference when refreshing your own base image/template.'
    FetchError      = $fetchError
}
