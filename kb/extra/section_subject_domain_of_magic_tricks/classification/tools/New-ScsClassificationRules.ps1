param(
    [string]$TrainingDirectory,
    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'

$scriptDirectory = $PSScriptRoot
if (-not $scriptDirectory) {
    $scriptDirectory = Join-Path (Get-Location) 'tools'
}
if (-not $TrainingDirectory) {
    $TrainingDirectory = Join-Path $scriptDirectory '..\training'
}
if (-not $OutputFile) {
    $OutputFile = Join-Path $scriptDirectory '..\rules\lr_magic_tricks_message_classification.scs'
}

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (
    Join-Path $TrainingDirectory 'classification_manifest.json'
) | ConvertFrom-Json
$utterances = Get-Content -Raw -Encoding UTF8 -LiteralPath (
    Join-Path $TrainingDirectory 'utterances.json'
) | ConvertFrom-Json

$messageClasses = @{
    about_entity = 'concept_message_about_entity'
    magic_prop_query = 'concept_message_about_magic_prop'
    magic_technique_query = 'concept_message_about_magic_technique'
    magic_effect_query = 'concept_message_about_magic_effect'
}

$systemIdentifiersByValue = @{}
foreach ($value in $manifest.entity.values) {
    $systemIdentifiersByValue[[string]$value.value] = [string]$value.system_identifier
}

$builder = [System.Text.StringBuilder]::new()
for ($index = 0; $index -lt $utterances.Count; $index++) {
    $utterance = $utterances[$index]
    $number = '{0:D3}' -f ($index + 1)
    $messageClass = $messageClasses[[string]$utterance.intent]

    if (-not $messageClass) {
        throw "Неизвестный класс сообщения '$($utterance.intent)'."
    }
    if ($utterance.entities.Count -ne 1) {
        throw "Для фразы '$($utterance.text)' ожидалась ровно одна сущность."
    }

    $entityValue = [string]$utterance.entities[0].body
    $entitySystemIdentifier = $systemIdentifiersByValue[$entityValue]
    if (-not $entitySystemIdentifier) {
        throw "Для значения '$entityValue' не найден системный идентификатор."
    }
    if ([string]$utterance.text -match '[\[\]]') {
        throw "Фраза содержит неподдерживаемую квадратную скобку: '$($utterance.text)'."
    }

    [void]$builder.AppendLine("if_magic_message_$number = [*")
    [void]$builder.AppendLine("    _message_$number")
    [void]$builder.AppendLine('        _<- concept_message;')
    [void]$builder.AppendLine("        _<= nrel_sc_text_translation:: .._translation_$number;;")
    [void]$builder.AppendLine("    @magic_message_link_$number = _[$($utterance.text)];;")
    [void]$builder.AppendLine("    .._translation_$number _-> @magic_message_link_$number;;")
    [void]$builder.AppendLine('*];;')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("@magic_message_link_$number => nrel_system_identifier: [_magic_message_link_$number];;")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("then_magic_message_$number = [*")
    [void]$builder.AppendLine("    $messageClass _-> _message_$number;;")
    [void]$builder.AppendLine("    _message_$number _-> rrel_entity:: $entitySystemIdentifier;;")
    [void]$builder.AppendLine('*];;')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("lr_classify_magic_message_$number")
    [void]$builder.AppendLine('<- concept_classify_message_rule_priority_1;')
    [void]$builder.AppendLine("-> rrel_main_key_sc_element: (if_magic_message_$number => then_magic_message_$number)")
    [void]$builder.AppendLine('    (* <- nrel_implication;; *);;')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('atomic_logical_formula')
    [void]$builder.AppendLine("-> if_magic_message_$number;")
    [void]$builder.AppendLine("-> then_magic_message_$number;;")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('concept_template_with_links')
    [void]$builder.AppendLine("-> if_magic_message_$number;;")
    [void]$builder.AppendLine()
}

$outputDirectory = Split-Path -Parent $OutputFile
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutputFile, $builder.ToString(), $utf8WithoutBom)

Write-Output "RULES=$($utterances.Count)"
Write-Output "OUTPUT=$((Resolve-Path -LiteralPath $OutputFile).Path)"
