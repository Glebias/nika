param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

$scriptDirectory = $PSScriptRoot
if (-not $scriptDirectory) {
    $scriptDirectory = Join-Path (Get-Location) 'tools'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $scriptDirectory '..\training'
}

$classificationDirectory = Split-Path -Parent $scriptDirectory
$repositoryRoot = (Resolve-Path (Join-Path $classificationDirectory '..\..\..\..')).Path
$domainDirectory = Join-Path $repositoryRoot 'kb\section_subject_domain_of_magic_tricks'

$systemIdentifiers = @(
    'concept_magic_performance_entity',
    'concept_magic_trick',
    'concept_magic_routine',
    'concept_magic_show',
    'concept_magic_participant',
    'concept_magician',
    'concept_assistant',
    'concept_spectator',
    'concept_magic_prop',
    'concept_playing_card',
    'concept_card_deck',
    'concept_coin',
    'concept_rope',
    'concept_cup',
    'concept_ball',
    'concept_magic_technique',
    'concept_sleight_of_hand',
    'concept_misdirection',
    'concept_magic_effect',
    'concept_appearance_effect',
    'concept_vanish_effect',
    'concept_transformation_effect',
    'concept_transposition_effect',
    'concept_restoration_effect',
    'concept_levitation_effect',
    'concept_mentalism_effect',
    'concept_card_trick',
    'concept_coin_trick',
    'concept_rope_trick',
    'concept_cups_and_balls_trick',
    'concept_close_up_trick',
    'concept_stage_trick',
    'concept_silk_handkerchief',
    'concept_magic_wand',
    'concept_magic_box',
    'concept_escape_trick',
    'concept_mentalism_trick',
    'concept_production_effect',
    'concept_penetration_effect',
    'concept_prediction_effect',
    'nrel_uses_prop',
    'nrel_uses_technique',
    'nrel_creates_effect',
    'nrel_performed_by',
    'nrel_assisted_by',
    'nrel_presented_to',
    'nrel_part_of_show',
    'nrel_precedes_trick',
    'nrel_variant_of_trick',
    'nrel_contains_card',
    'nrel_selected_by_spectator',
    'nrel_hidden_by_magician',
    'nrel_attention_directed_to',
    'nrel_participates_in_show',
    'nrel_included_in_routine',
    'nrel_routine_begins_with',
    'nrel_routine_ends_with',
    'nrel_transforms_into',
    'nrel_restored_from',
    'nrel_effect_achieved_by',
    'trick_ambitious_card',
    'trick_coin_vanish',
    'trick_cut_and_restored_rope',
    'trick_cups_and_balls',
    'trick_floating_table',
    'trick_book_test',
    'trick_handcuff_escape',
    'french_drop',
    'half_dollar_coin',
    'effect_coin_vanish'
)

$scsFiles = Get-ChildItem -LiteralPath $domainDirectory -Recurse -Filter '*.scs'
$labelsBySystemIdentifier = @{}

foreach ($file in $scsFiles) {
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    foreach ($systemIdentifier in $systemIdentifiers) {
        if ($labelsBySystemIdentifier.ContainsKey($systemIdentifier)) { continue }

        $escapedIdentifier = [regex]::Escape($systemIdentifier)
        $pattern = "(?ms)^$escapedIdentifier\s.*?=>\s*nrel_main_idtf:\s*\[([^\]]+)\]"
        $match = [regex]::Match($content, $pattern)
        if ($match.Success) {
            $labelsBySystemIdentifier[$systemIdentifier] = $match.Groups[1].Value.Trim()
        }
    }
}

$missing = @($systemIdentifiers | Where-Object { -not $labelsBySystemIdentifier.ContainsKey($_) })
if ($missing.Count -gt 0) {
    throw "Не найдены основные русские идентификаторы: $($missing -join ', ')"
}

function New-AnnotatedUtterance {
    param(
        [string]$Text,
        [string]$Intent,
        [string]$EntityText
    )

    $start = $Text.IndexOf($EntityText, [System.StringComparison]::OrdinalIgnoreCase)
    if ($start -lt 0) {
        throw "Сущность '$EntityText' отсутствует в сообщении '$Text'."
    }

    [ordered]@{
        text = $Text
        intent = $Intent
        entities = @(
            [ordered]@{
                entity = 'magic_entity:rrel_entity'
                start = $start
                end = $start + $EntityText.Length
                body = $Text.Substring($start, $EntityText.Length)
                entities = @()
            }
        )
        traits = @()
    }
}

$utterances = [System.Collections.Generic.List[object]]::new()

foreach ($systemIdentifier in $systemIdentifiers) {
    $label = $labelsBySystemIdentifier[$systemIdentifier]
    $utterances.Add((New-AnnotatedUtterance "Что такое ${label}?" 'about_entity' $label))
}

$trick = $labelsBySystemIdentifier['trick_coin_vanish']

@(
    "Какой реквизит используется в ${trick}?",
    "Что из реквизита нужно для фокуса ${trick}?",
    "Назови реквизит для фокуса ${trick}."
) | ForEach-Object {
    $utterances.Add((New-AnnotatedUtterance $_ 'magic_prop_query' $trick))
}

@(
    "Какая техника используется в ${trick}?",
    "Какой техникой выполняют ${trick}?",
    "Назови технику исполнения фокуса ${trick}."
) | ForEach-Object {
    $utterances.Add((New-AnnotatedUtterance $_ 'magic_technique_query' $trick))
}

@(
    "Какой эффект создаёт ${trick}?",
    "Что видит зритель во время фокуса ${trick}?",
    "Назови эффект фокуса ${trick}."
) | ForEach-Object {
    $utterances.Add((New-AnnotatedUtterance $_ 'magic_effect_query' $trick))
}

$duplicateTexts = @($utterances | Group-Object { $_.text } | Where-Object Count -gt 1)
if ($duplicateTexts.Count -gt 0) {
    throw "Найдены повторяющиеся обучающие сообщения: $($duplicateTexts.Name -join '; ')"
}

foreach ($utterance in $utterances) {
    foreach ($entity in $utterance.entities) {
        $fragment = $utterance.text.Substring($entity.start, $entity.end - $entity.start)
        if ($fragment -cne $entity.body) {
            throw "Некорректные границы сущности в сообщении '$($utterance.text)'."
        }
    }
}

$entityValues = foreach ($systemIdentifier in $systemIdentifiers) {
    [ordered]@{
        system_identifier = $systemIdentifier
        value = $labelsBySystemIdentifier[$systemIdentifier]
        synonyms = @($labelsBySystemIdentifier[$systemIdentifier])
    }
}

$manifest = [ordered]@{
    language = 'ru'
    entity = [ordered]@{
        name = 'magic_entity'
        role = 'rrel_entity'
        lookup_strategy = 'keywords'
        values = $entityValues
    }
    intents = @(
        [ordered]@{ name = 'about_entity'; description = 'Запрос определения сущности предметной области' },
        [ordered]@{ name = 'magic_prop_query'; description = 'Запрос реквизита фокуса' },
        [ordered]@{ name = 'magic_technique_query'; description = 'Запрос техники исполнения фокуса' },
        [ordered]@{ name = 'magic_effect_query'; description = 'Запрос эффекта фокуса' }
    )
    utterance_count = $utterances.Count
    entity_value_count = $entityValues.Count
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    (Join-Path $OutputDirectory 'utterances.json'),
    ($utterances | ConvertTo-Json -Depth 8),
    $utf8WithoutBom
)
[System.IO.File]::WriteAllText(
    (Join-Path $OutputDirectory 'classification_manifest.json'),
    ($manifest | ConvertTo-Json -Depth 8),
    $utf8WithoutBom
)

Write-Output "ENTITY_VALUES=$($entityValues.Count)"
Write-Output "UTTERANCES=$($utterances.Count)"
Write-Output "OUTPUT=$((Resolve-Path -LiteralPath $OutputDirectory).Path)"
