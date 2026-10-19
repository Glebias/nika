param(
    [Parameter(Mandatory = $true)]
    [string]$ServerToken,
    [string]$ApiVersion = '20200513'
)

$ErrorActionPreference = 'Stop'

$tests = @(
    [ordered]@{ text = 'Что такое фокус?'; intent = 'about_entity'; entity = 'фокус' },
    [ordered]@{ text = 'Какой реквизит используется в исчезновении монеты французским сбросом?'; intent = 'magic_prop_query'; entity = 'Исчезновение монеты французским сбросом' },
    [ordered]@{ text = 'Какая техника используется в исчезновении монеты французским сбросом?'; intent = 'magic_technique_query'; entity = 'Исчезновение монеты французским сбросом' },
    [ordered]@{ text = 'Какой эффект создаёт исчезновение монеты французским сбросом?'; intent = 'magic_effect_query'; entity = 'Исчезновение монеты французским сбросом' }
)

$headers = @{ Authorization = "Bearer $ServerToken" }
$failed = 0

foreach ($test in $tests) {
    $encodedText = [uri]::EscapeDataString($test.text)
    $uri = "https://api.wit.ai/message?v=$ApiVersion&q=$encodedText"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 30

    $actualIntent = if ($response.intents.Count -gt 0) { $response.intents[0].name } else { '' }
    $entityProperty = $response.entities.PSObject.Properties |
        Where-Object Name -eq 'magic_entity:rrel_entity' |
        Select-Object -First 1
    $actualEntity = if ($entityProperty -and $entityProperty.Value.Count -gt 0) {
        [string]$entityProperty.Value[0].value
    }
    else {
        ''
    }

    $passed = $actualIntent -eq $test.intent -and $actualEntity -eq $test.entity
    if (-not $passed) { $failed++ }

    [pscustomobject]@{
        Message = $test.text
        ExpectedIntent = $test.intent
        ActualIntent = $actualIntent
        ExpectedEntity = $test.entity
        ActualEntity = $actualEntity
        Passed = $passed
    }
}

if ($failed -gt 0) {
    throw "$failed из $($tests.Count) проверок классификации не пройдены."
}
