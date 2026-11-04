"""Generate the compact SCs rules and phrase classes for lab 3."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
KINDS = (
    ("prop", "concept_message_about_magic_prop", "nrel_uses_prop", "реквизит", "использует реквизит"),
    ("technique", "concept_message_about_magic_technique", "nrel_uses_technique", "техника", "использует технику"),
    ("effect", "concept_message_about_magic_effect", "nrel_creates_effect", "эффект", "создаёт эффект"),
)

parts = ["// ЛР-03: ответы по фактам о фокусах. Приоритет 1 — факт найден, 3 — сведений нет.\n"]
for kind, message_class, relation, noun, verb in KINDS:
    for state in ("found", "unknown"):
        base = f"magic_{kind}_{state}"
        phrase = f"concept_phrase_{base}"
        rule = f"lr_answer_{base}"
        cond = f"    _entity _=> {relation}:: _value;;\n" if state == "found" else ""
        template_value = (
            f"    _entity _=> {relation}:: _value;;\n"
            f"    _value _=> nrel_magic_ru_name:: @{base}_value_name;;\n"
            if state == "found" else ""
        )
        priority = 1 if state == "found" else 3
        state_ru = "факт найден" if state == "found" else "сведений нет"
        noun_genitive = {"prop": "реквизите", "technique": "технике", "effect": "эффекте"}[kind]
        parts.append(f"""
@{rule}_if = [*
    concept_message _-> _message;;
    {message_class} _-> _message;;
    _message _-> rrel_entity:: _entity;;
{cond}*];;

@{rule}_then = [*
    _message _=> nrel_reply:: _reply_message;;
    {message_class} _-> _reply_message;;
    concept_atomic_message _-> _reply_message;;
*];;

@{rule}_impl = (@{rule}_if => nrel_implication: @{rule}_then);;

{rule}
<- concept_answer_on_standard_message_rule;
<- concept_answer_on_standard_message_rule_priority_{priority};
=> nrel_answer_pattern: ..{rule}_pattern;
-> rrel_main_key_sc_element: @{rule}_impl;;

..{rule}_pattern
<- sc_node_tuple;
-> rrel_1: {phrase};;

atomic_logical_formula
-> @{rule}_if;
-> @{rule}_then;;

@{base}_entity_name = _[];;
@{base}_entity_name => nrel_system_identifier: [_{base}_entity_name];;
""")
        if state == "found":
            parts.append(f"@{base}_value_name = _[];;\n@{base}_value_name => nrel_system_identifier: [_{base}_value_name];;\n")
        parts.append(f"""
@{phrase}_template = [*
    concept_message _-> _message;;
    _message _-> rrel_entity:: _entity;;
    _entity _=> nrel_magic_ru_name:: @{base}_entity_name;;
{template_value}*];;

{phrase}
<- sc_node_class;
<= nrel_inclusion: concept_phrase;
=> nrel_main_idtf:
    [фраза о {noun_genitive} фокуса: {state_ru}] (* <- lang_ru;; *);;
""")
        if state == "found":
            phrases = (
                f"Фокус ${{_{base}_entity_name}} {verb} ${{_{base}_value_name}}.",
                f"Для фокуса ${{_{base}_entity_name}} {noun} — ${{_{base}_value_name}}.",
            )
        else:
            phrases = (
                f"Для фокуса ${{_{base}_entity_name}} в базе знаний не указан {noun}.",
                f"В базе знаний пока нет сведений по теме «{noun}» для фокуса ${{_{base}_entity_name}}.",
            )
        for phrase_text in phrases:
            parts.append(
                f"{phrase}\n-> [{phrase_text}]\n"
                f"    (* <- lang_ru;; => nrel_phrase_template: @{phrase}_template;; *);;\n"
            )

(ROOT / "lr_magic_tricks_answers.scs").write_text("\n".join(parts), encoding="utf-8")
