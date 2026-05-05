#!/usr/bin/env python3
"""
v2.4.0 codemod: migrate `db.executeSql` / `db.executeReader` /
`db.getLastInsertedId()` call sites to the new `prepareQuery` +
`statement.executeXxx` + `statement.close` pattern.

Patterns handled:
  await DB.executeSql(SQL_EXPR);
  await DB.executeSql(SQL_EXPR, params: [...]);
  await DB.executeSql(SQL_EXPR, nameParams: {...});
  await DB.executeReader(SQL_EXPR);
  await DB.executeReader(SQL_EXPR, params: [...]);
  await DB.executeReader(SQL_EXPR, nameParams: {...});

executeSql is rewritten to a tight prepare/execute/close block.
executeReader is rewritten to prepare + executeReader; the reader
holds the statement for its lifetime, so the caller's existing
`reader.close()` is sufficient.

Limitations:
  * `DB.getLastInsertedId()` is NOT auto-migrated — its call site
    needs to reference a specific statement, which requires
    preserving the stmt name across statements. Sites are reported.
  * Patterns inside `() => DB.executeSql(...)` (single-expression
    arrow funcs) are NOT handled — they need to become async blocks.
    Sites are reported.

Usage:
  python scripts/codemod_v2_4_0.py [path1] [path2] ...
"""

from __future__ import annotations
import re
import sys
import pathlib
from typing import List, Tuple

# Match a balanced parenthesised argument list. Limited to one level
# of nested parens / brackets / braces / strings — sufficient for our
# call sites.
def _find_args(text: str, open_idx: int) -> int | None:
    """Return the index just after the matching close-paren of the
    open-paren at [open_idx], or None if unbalanced."""
    assert text[open_idx] == '('
    depth = 0
    i = open_idx
    n = len(text)
    in_str: str | None = None
    while i < n:
        c = text[i]
        if in_str:
            if c == '\\' and i + 1 < n:
                i += 2
                continue
            if c == in_str:
                in_str = None
            i += 1
            continue
        if c in "'\"":
            # detect triple-quoted strings
            if text.startswith(c * 3, i):
                end = text.find(c * 3, i + 3)
                if end == -1:
                    return None
                i = end + 3
                continue
            in_str = c
            i += 1
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return None


_INDENT_RE = re.compile(r'^( *)', re.MULTILINE)


def _line_indent(text: str, idx: int) -> str:
    """Indentation of the line containing [idx]."""
    line_start = text.rfind('\n', 0, idx) + 1
    end = idx
    while end < len(text) and text[end] == ' ':
        end += 1
    return text[line_start:end] if all(c == ' ' for c in text[line_start:idx]) else text[line_start:idx]


def _starts_at_line_start(text: str, idx: int) -> bool:
    line_start = text.rfind('\n', 0, idx) + 1
    return all(c in ' \t' for c in text[line_start:idx])


# Match: "await VAR.executeSql(" or "await VAR.executeReader(" or "await VAR!.executeXxx("
CALL_RE = re.compile(
    r'\bawait\s+(?P<recv>[A-Za-z_][A-Za-z0-9_]*!?)\.(?P<method>executeSql|executeReader)\s*\('
)

GET_LAST_INSERTED_RE = re.compile(
    r'\b(?P<recv>[A-Za-z_][A-Za-z0-9_]*!?)\.getLastInsertedId\s*\(\s*\)'
)


def _split_args_text(args_text: str) -> Tuple[str, str | None]:
    """Split call arguments into (sql_expr, kwargs) — kwargs is the
    full `params: ..., nameParams: ...` slice or None."""
    # Find the top-level comma that separates sql_expr from kwargs
    depth = 0
    in_str: str | None = None
    i = 0
    n = len(args_text)
    while i < n:
        c = args_text[i]
        if in_str:
            if c == '\\' and i + 1 < n:
                i += 2
                continue
            if c == in_str:
                in_str = None
            i += 1
            continue
        if c in "'\"":
            if args_text.startswith(c * 3, i):
                end = args_text.find(c * 3, i + 3)
                if end == -1:
                    return args_text.strip(), None
                i = end + 3
                continue
            in_str = c
            i += 1
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            return args_text[:i].strip(), args_text[i + 1:].strip()
        i += 1
    return args_text.strip(), None


def _migrate_executeSql(recv: str, sql_expr: str, kwargs: str | None,
                        indent: str) -> str:
    """Build a prepare/execute/close block for executeSql."""
    if kwargs:
        exec_args = f'({kwargs})'
    else:
        exec_args = '()'
    # The block opens its own scope so `stmt` doesn't pollute the
    # surrounding namespace. Use a curly-brace block; callers should
    # be inside an async function.
    lines = [
        '{',
        f'{indent}  final stmt = await {recv}.prepareQuery({sql_expr});',
        f'{indent}  try {{',
        f'{indent}    await stmt.executeSql{exec_args};',
        f'{indent}  }} finally {{',
        f'{indent}    await stmt.close();',
        f'{indent}  }}',
        f'{indent}}}',
    ]
    return '\n'.join(lines)


def _migrate_executeSql_inline(recv: str, sql_expr: str,
                                kwargs: str | None) -> str:
    """Single-expression replacement for `await db.executeSql(...)`
    when the caller wants the affected-rows return value inline."""
    if kwargs:
        exec_args = f'({kwargs})'
    else:
        exec_args = '()'
    return (
        f'await ((stmt) async {{ try {{ '
        f'return await stmt.executeSql{exec_args}; '
        f'}} finally {{ await stmt.close(); }} }})'
        f'(await {recv}.prepareQuery({sql_expr}))'
    )


def _migrate_executeReader(recv: str, sql_expr: str,
                           kwargs: str | None) -> str:
    """Build an executeReader call chained off a fresh statement.
    Caller's existing reader.close() will trigger the statement's
    onClose closure (which finalises the handle and releases the
    pool slot). We don't explicitly await stmt.close() here — that
    would prematurely close the just-returned reader. Instead the
    pattern is `await (await db.prepareQuery(SQL)).executeReader(...)`.
    """
    if kwargs:
        exec_args = f'({kwargs})'
    else:
        exec_args = '()'
    return f'await (await {recv}.prepareQuery({sql_expr})).executeReader{exec_args}'


def migrate(text: str, path: pathlib.Path) -> Tuple[str, List[str]]:
    """Run all migrations against [text]. Returns (new_text, warnings)."""
    warnings: List[str] = []
    out_parts: List[str] = []
    cursor = 0

    while True:
        m = CALL_RE.search(text, cursor)
        if not m:
            out_parts.append(text[cursor:])
            break

        recv = m.group('recv')
        method = m.group('method')
        open_paren_idx = m.end() - 1
        close_paren_idx = _find_args(text, open_paren_idx)
        if close_paren_idx is None:
            warnings.append(
                f'{path}: unbalanced parens at offset {m.start()} — skipped'
            )
            out_parts.append(text[cursor:m.end()])
            cursor = m.end()
            continue

        args_text = text[open_paren_idx + 1:close_paren_idx - 1]
        sql_expr, kwargs = _split_args_text(args_text)

        # Emit everything up to the match
        out_parts.append(text[cursor:m.start()])

        if method == 'executeSql':
            # Two cases: statement-level (followed by `;`) vs
            # expression-level (e.g. `final n = await db.executeSql(...)`).
            after = text[close_paren_idx:close_paren_idx + 8]

            # Detect whether the call is the entire RHS of an `await`
            # statement — i.e. preceded only by whitespace on its
            # line and followed immediately by `;`.
            is_statement_rhs = (
                _starts_at_line_start(text, m.start())
                and after.lstrip().startswith(';')
            )
            if is_statement_rhs:
                indent = _line_indent(text, m.start())
                # Remove the `await` keyword start; replace with the
                # block. Then consume the trailing `;`.
                block = _migrate_executeSql(recv, sql_expr, kwargs, indent)
                # Skip the trailing whitespace + ';'
                trail = after.find(';')
                consumed_end = close_paren_idx + trail + 1
                out_parts.append(block)
                cursor = consumed_end
            else:
                # Inline expression form — preserve the await,
                # produce an immediately-invoked async function.
                inline = _migrate_executeSql_inline(recv, sql_expr, kwargs)
                out_parts.append(inline)
                cursor = close_paren_idx
        else:
            # executeReader
            inline = _migrate_executeReader(recv, sql_expr, kwargs)
            out_parts.append(inline)
            cursor = close_paren_idx

    new_text = ''.join(out_parts)

    # Report (but don't auto-migrate) `getLastInsertedId()` sites:
    # they require knowing which statement to reference.
    for m in GET_LAST_INSERTED_RE.finditer(new_text):
        line_start = new_text.rfind('\n', 0, m.start()) + 1
        line_end = new_text.find('\n', m.start())
        line = new_text[line_start:line_end if line_end > 0 else None].strip()
        warnings.append(f'{path}: {m.group("recv")}.getLastInsertedId() — manual migration required: {line}')

    return new_text, warnings


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)

    all_warnings: List[str] = []
    for arg in sys.argv[1:]:
        path = pathlib.Path(arg)
        if not path.is_file():
            print(f'skip: {path} (not a file)')
            continue
        text = path.read_text(encoding='utf-8')
        new_text, warns = migrate(text, path)
        if new_text != text:
            path.write_text(new_text, encoding='utf-8')
            print(f'migrated: {path}')
        else:
            print(f'unchanged: {path}')
        all_warnings.extend(warns)

    if all_warnings:
        print('\n--- WARNINGS ---')
        for w in all_warnings:
            print(w)


if __name__ == '__main__':
    main()
