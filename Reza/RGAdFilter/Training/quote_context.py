"""Framing for reviewed short-quotation intent examples (not whole-message labels).

Label the quoted part in its author context. A quoted sales pitch in a report/test is
content; an author's sponsorship footer is promotion. Keep the literal framing and
bounds aligned with AdSemanticClassifier.swift. Callers must normalize text using the
same train.py/native tokenizer contract after constructing this input.
"""

import regex  # Extended grapheme clusters, matching Swift Character slicing.


def quote_context(preceding: str, quote: str, promotional_menu: str) -> str:
    quote = quote.strip()
    if len(regex.findall(r'\X', quote)) > 64:
        raise ValueError('Long quotations keep conservative display protection')
    context = ''.join(regex.findall(r'\X', preceding.strip())[-32:])
    menu = ''.join(regex.findall(r'\X', promotional_menu)[:16])
    return '上文：' + context + '\n引用：' + quote + '\n后续入口：' + menu
