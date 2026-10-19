param(
    [Parameter(Mandatory = $true)]
    [string]$ServerToken,
    [string]$ApiVersion = '20200513',
    [int]$BatchSize = 100
)

$ErrorActionPreference = 'Stop'

if ($BatchSize -lt 1 -or $BatchSize -gt 200) {
    throw 'BatchSize must be between 1 and 200.'
}

$scriptPathValue = $MyInvocation.MyCommand.Path
if ($scriptPathValue) {
    $toolsDir = Split-Path -Parent $scriptPathValue
    $classificationDir = Split-Path -Parent $toolsDir
}
else {
    $classificationDir = Get-Location
}

$manifestPath = Join-Path $classificationDir 'training\classification_manifest.json'
$utterancesPath = Join-Path $classificationDir 'training\utterances.json'

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}
if (-not (Test-Path -LiteralPath $utterancesPath)) {
    throw "Utterances not found: $utterancesPath"
}

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
$utterances = Get-Content -Raw -Encoding UTF8 -LiteralPath $utterancesPath | ConvertFrom-Json
$utterances = @($utterances)
$baseUri = 'https://api.wit.ai'
$headers = @{
    Authorization = "Bearer $ServerToken"
    Accept = "application/vnd.wit.$ApiVersion+json"
}

function Invoke-WitApi {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [object]$Body
    )

    $separator = if ($Path.Contains('?')) { '&' } else { '?' }
    $uri = "$baseUri$Path${separator}v=$ApiVersion"
    $request = @{
        Method = $Method
        Uri = $uri
        Headers = $headers
        TimeoutSec = 60
        UseBasicParsing = $true
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $json = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
    }

    try {
        $response = Invoke-WebRequest @request
        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            return $null
        }
        $parsedResponse = $response.Content | ConvertFrom-Json
        return $parsedResponse
    }
    catch {
        $details = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $details = "$details Response: $($_.ErrorDetails.Message)"
        }
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                $reader.Dispose()
                if ($responseBody) { $details = "$details Response: $responseBody" }
            }
            catch {
                # Keep the original request exception if the response body cannot be read.
            }
        }
        throw "Wit.ai request failed: $Method $Path. $details"
    }
}

Write-Output 'Step 1/5: reading existing Wit.ai model'
$existingIntents = @(Invoke-WitApi -Method GET -Path '/intents')
$existingIntentNames = @($existingIntents | ForEach-Object { $_.name })

foreach ($intent in @($manifest.intents)) {
    if ($existingIntentNames -notcontains $intent.name) {
        $null = Invoke-WitApi -Method POST -Path '/intents' -Body ([ordered]@{ name = $intent.name })
        Write-Output "Created intent: $($intent.name)"
    }
    else {
        Write-Output "Intent already exists: $($intent.name)"
    }
}

Write-Output 'Step 2/5: creating entity and role'
$existingEntities = @(Invoke-WitApi -Method GET -Path '/entities')
$existingEntityNames = @($existingEntities | ForEach-Object { $_.name })
$entityName = [string]$manifest.entity.name
$entityRole = [string]$manifest.entity.role
$entityLookups = @([string]$manifest.entity.lookup_strategy)

if ($existingEntityNames -notcontains $entityName) {
    $entityBody = [ordered]@{
        name = $entityName
        roles = @($entityRole)
        lookups = $entityLookups
    }
    $null = Invoke-WitApi -Method POST -Path '/entities' -Body $entityBody
    Write-Output "Created entity: ${entityName}:${entityRole}"
}
else {
    $entityInfo = Invoke-WitApi -Method GET -Path ("/entities/" + [uri]::EscapeDataString($entityName))
    $roles = @($entityInfo.roles | ForEach-Object {
        if ($_ -is [string]) { $_ } else { $_.name }
    })
    $lookups = @($entityInfo.lookups)
    if ($roles -notcontains $entityRole -or $lookups -notcontains $manifest.entity.lookup_strategy) {
        $updatedRoles = @($roles + $entityRole | Select-Object -Unique)
        $updatedLookups = @($lookups + $manifest.entity.lookup_strategy | Select-Object -Unique)
        $entityBody = [ordered]@{
            name = $entityName
            roles = $updatedRoles
            lookups = $updatedLookups
        }
        $null = Invoke-WitApi -Method PUT -Path ("/entities/" + [uri]::EscapeDataString($entityName)) -Body $entityBody
        Write-Output "Updated entity roles/lookups: ${entityName}:${entityRole}"
    }
    else {
        Write-Output "Entity already exists: ${entityName}:${entityRole}"
    }
}

Write-Output 'Step 3/5: adding keyword values'
$entityInfo = Invoke-WitApi -Method GET -Path ("/entities/" + [uri]::EscapeDataString($entityName))
$existingKeywords = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($keyword in @($entityInfo.keywords)) {
    $null = $existingKeywords.Add([string]$keyword.keyword)
}

$addedKeywords = 0
foreach ($value in @($manifest.entity.values)) {
    $canonicalValue = [string]$value.value
    if (-not $existingKeywords.Contains($canonicalValue)) {
        $keywordBody = [ordered]@{
            keyword = $canonicalValue
            synonyms = @($value.synonyms)
        }
        $null = Invoke-WitApi -Method POST -Path ("/entities/" + [uri]::EscapeDataString($entityName) + '/keywords') -Body $keywordBody
        $null = $existingKeywords.Add($canonicalValue)
        $addedKeywords++
        if (($addedKeywords % 10) -eq 0) {
            Write-Output "Added keywords: $addedKeywords"
        }
    }
}
Write-Output "Keyword values present: $($existingKeywords.Count); added in this run: $addedKeywords"

Write-Output 'Step 4/5: reading existing utterances'
$existingTexts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$offset = 0
$pageSize = 200
do {
    $page = @(Invoke-WitApi -Method GET -Path "/utterances?limit=$pageSize&offset=$offset")
    foreach ($item in $page) {
        $null = $existingTexts.Add([string]$item.text)
    }
    $offset += $page.Count
} while ($page.Count -eq $pageSize)

$missingUtterances = @($utterances | Where-Object { -not $existingTexts.Contains([string]$_.text) })
Write-Output "Existing utterances: $($existingTexts.Count); missing: $($missingUtterances.Count)"

Write-Output 'Step 5/5: uploading utterances'
for ($start = 0; $start -lt $missingUtterances.Count; $start += $BatchSize) {
    $end = [Math]::Min($start + $BatchSize - 1, $missingUtterances.Count - 1)
    $batch = @($missingUtterances[$start..$end])
    $result = Invoke-WitApi -Method POST -Path '/utterances' -Body $batch
    Write-Output "Uploaded utterances: $($end + 1) / $($missingUtterances.Count)"
}

$finalIntents = @(Invoke-WitApi -Method GET -Path '/intents')
$finalEntity = Invoke-WitApi -Method GET -Path ("/entities/" + [uri]::EscapeDataString($entityName))
$finalUtterances = @(Invoke-WitApi -Method GET -Path '/utterances?limit=1&offset=0')
$finalRoles = @($finalEntity.roles | ForEach-Object {
    if ($_ -is [string]) { $_ } else { $_.name }
})

[pscustomobject]@{
    Intents = $finalIntents.Count
    Entity = $finalEntity.name
    Roles = $finalRoles -join ', '
    Keywords = @($finalEntity.keywords).Count
    UploadedUtterances = $missingUtterances.Count
    ApiReachable = $true
} | Format-List
