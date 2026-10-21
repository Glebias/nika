# Классификация сообщений о фокусах — ЛР № 2

Каталог содержит вторую лабораторную работу по ТиИСПИС: SCs-формализацию классов сообщений и сущностей, сценарий диалога, набор данных Wit.ai и локальные SCs-правила классификации.

## Что формализовано

- стандартный intent NIKA `about_entity` для вопросов «Что такое …?»;
- intent `magic_prop_query` для вопросов о реквизите фокуса;
- intent `magic_technique_query` для вопросов о технике исполнения;
- intent `magic_effect_query` для вопросов об иллюзионном эффекте;
- entity `magic_entity` с ролью `rrel_entity`;
- 60 понятий ЛР № 1 и 10 связанных экземпляров как распознаваемые значения entity;
- диалог из четырёх вопросов и четырёх ответов.

Имена intent, entity и role в Wit.ai должны в точности совпадать со значениями `nrel_wit_ai_idtf` в SCs-файлах.

## Подготовка набора данных

Из этого каталога выполнить:

```powershell
$source = Get-Content -Raw -Encoding UTF8 .\tools\New-WitAiTrainingData.ps1
& ([scriptblock]::Create($source))
```

Скрипт читает основные русские идентификаторы прямо из базы знаний ЛР № 1, проверяет границы выделенных сущностей и создаёт:

- `training/utterances.json` — 79 размеченных сообщений: обязательный вопрос «Что такое …?» для каждого из 70 значений и по три примера для каждого нового класса сценария;
- `training/classification_manifest.json` — перечень четырёх intents и 70 значений entity.

## Настройка Wit.ai

1. Создать приложение с русским языком.
2. Создать intents `about_entity`, `magic_prop_query`, `magic_technique_query`, `magic_effect_query`.
3. Создать keyword entity `magic_entity` и роль `rrel_entity`.
4. Добавить значения из `training/classification_manifest.json` и размеченные сообщения из `training/utterances.json`. Это можно сделать через интерфейс Wit.ai либо его HTTP API.
5. Дождаться окончания обучения и проверить четыре сообщения из `dialogue_scenario.md` в окне Understanding.
6. Экспортировать приложение из Wit.ai и сохранить полученный JSON/архив в `wit_ai_export/`.
7. Получить Server Access Token и записать его локально в секцию `[wit-ai]` файла `nika.ini`. Секретный токен нельзя публиковать в Git.
8. Перезапустить `nika-problem-solver`, проверить вопросы в NIKA и сохранить скриншоты классификации и диалога.

Проверить API после обучения можно так:

```powershell
$source = Get-Content -Raw -Encoding UTF8 .\tools\Test-WitAiClassification.ps1
& ([scriptblock]::Create($source)) -ServerToken $env:WIT_AI_SERVER_TOKEN
```

Создать отсутствующие intents, entity, keywords и загрузить обучающие сообщения можно идемпотентным скриптом:

```powershell
$source = Get-Content -Raw -Encoding UTF8 .\tools\Publish-WitAiTrainingData.ps1
& ([scriptblock]::Create($source)) -ServerToken $env:WIT_AI_SERVER_TOKEN
```

Скрипт сначала читает текущее состояние приложения, поэтому при повторном запуске не создаёт уже существующие intent, keyword и utterance с тем же текстом.

## Результат облачного обучения

В приложении Wit.ai созданы 4 intent, entity `magic_entity`, роль `rrel_entity`, 70 keyword-значений и 79 utterances. Обучение завершилось, а штатный экспорт модели сохранён в `wit_ai_export/`.

На момент итоговой проверки API Wit.ai не возвращает intent даже для точной обученной фразы, хотя приложение имеет статус `done`. Это воспроизводит открытые проблемы сервиса Wit.ai для новых приложений: `wit-ai/wit#2833` и `wit-ai/wit#2858`. Локальная SCs-часть и содержимое облачной модели при этом проверены отдельно.

## Локальная классификация SCs

По согласованию с преподавателем для работы без Wit.ai добавлен набор из 79 правил: 70 вопросов вида «Что такое …?» и 9 специализированных вопросов о реквизите, технике и эффекте. Правила находятся в `rules/lr_magic_tricks_message_classification.scs`.

Перегенерация правил из исходного набора фраз:

```powershell
$source = Get-Content -Raw -Encoding UTF8 .\tools\New-ScsClassificationRules.ps1
& ([scriptblock]::Create($source))
```

После изменения базы нужно перезапустить решатель, дождаться состояния `healthy`, а затем перезапустить сервер Python-агентов:

```powershell
docker compose restart problem-solver
docker compose ps
docker compose restart py-sc-server
```

Контрольный вопрос `Что такое фокус?` успешно классифицируется как `concept_message_about_entity`, получает сущность `concept_magic_trick` в роли `rrel_entity`, после чего NIKA выводит определение из базы знаний.
