#!/usr/bin/env python3
"""Recuperacao ESTRUTURAL de um SQLite com integrity_check falho (Q01).

- Nunca altera o arquivo de origem (abre em modo somente leitura).
- Faz um backup consistente (API de backup do SQLite) quando possivel.
- Recria o esquema (tabelas, indices, triggers, views) num arquivo NOVO e copia
  as linhas lendo cada tabela com NOT INDEXED (varredura da arvore da tabela,
  ignorando indices corrompidos). Reporta contagens, perdas e duplicacoes.
- Nao faz correcao semantica de dados (isso e feito por tools/sanitize_br.R).

Uso:
  python tools/sqlite_recover.py funding_intelligence.sqlite \
      --out backups/funding_intelligence.recovered.sqlite \
      --backup backups/funding_intelligence.pre_recovery.sqlite
"""
import argparse
import hashlib
import json
import os
import sqlite3
import sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def qid(name):
    return '"' + name.replace('"', '""') + '"'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--out", required=True)
    ap.add_argument("--backup")
    ap.add_argument("--report")
    args = ap.parse_args()

    if os.path.abspath(args.out) == os.path.abspath(args.source):
        sys.exit("--out nao pode ser o arquivo de origem")
    if os.path.exists(args.out):
        sys.exit(f"{args.out} ja existe; remova-o explicitamente antes de recuperar")
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)

    report = {"source": args.source, "source_sha256": sha256(args.source), "tables": {}}
    src = sqlite3.connect(f"file:{args.source}?mode=ro", uri=True)

    if args.backup:
        os.makedirs(os.path.dirname(os.path.abspath(args.backup)), exist_ok=True)
        try:
            dst = sqlite3.connect(args.backup)
            src.backup(dst)
            dst.close()
            report["backup_method"] = "sqlite3 backup API"
        except sqlite3.Error as exc:
            import shutil
            shutil.copyfile(args.source, args.backup)
            report["backup_method"] = f"file copy (backup API falhou: {exc})"
        report["backup_sha256"] = sha256(args.backup)

    integ = [r[0] for r in src.execute("PRAGMA integrity_check")]
    report["source_integrity_head"] = integ[0].splitlines()[:6]

    master = src.execute(
        "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL "
        "AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name"
    ).fetchall()
    out = sqlite3.connect(args.out)
    out.execute("PRAGMA foreign_keys=OFF")

    tables = [m for m in master if m[0] == "table"]
    for _, name, _, sql in tables:
        out.execute(sql)

    for _, name, _, sql in tables:
        cols = [r[1] for r in src.execute(f"PRAGMA table_info({qid(name)})")]
        collist = ",".join(qid(c) for c in cols)
        try:
            n_idx = src.execute(f"SELECT COUNT(*) FROM {qid(name)}").fetchone()[0]
        except sqlite3.Error as exc:
            n_idx = f"erro: {exc}"
        rows = src.execute(f"SELECT {collist} FROM {qid(name)} NOT INDEXED").fetchall()
        inserted = skipped = 0
        skipped_info = []
        ph = ",".join("?" for _ in cols)
        for row in rows:
            try:
                out.execute(f"INSERT INTO {qid(name)} ({collist}) VALUES ({ph})", row)
                inserted += 1
            except sqlite3.IntegrityError as exc:
                skipped += 1
                skipped_info.append(str(exc))
        report["tables"][name] = {
            "count_via_index": n_idx,
            "rows_full_scan": len(rows),
            "inserted": inserted,
            "skipped_constraint": skipped,
            "skipped_reasons": skipped_info[:10],
        }

    for typ, name, _, sql in master:
        if typ != "table":
            try:
                out.execute(sql)
            except sqlite3.Error as exc:
                report.setdefault("schema_warnings", []).append(f"{typ} {name}: {exc}")

    # preserva sqlite_sequence
    try:
        seq = src.execute("SELECT name, seq FROM sqlite_sequence").fetchall()
        for n, s in seq:
            out.execute("UPDATE sqlite_sequence SET seq=? WHERE name=?", (s, n))
    except sqlite3.Error:
        pass
    out.commit()

    report["out_integrity"] = [r[0] for r in out.execute("PRAGMA integrity_check")]
    report["out_fk_check"] = out.execute("PRAGMA foreign_key_check").fetchall()
    report["out_sha256_pre_close"] = None
    out.close()
    report["out_sha256"] = sha256(args.out)
    report["schema_objects"] = {
        "source": len(master),
        "out": len(sqlite3.connect(args.out).execute(
            "SELECT 1 FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'").fetchall()),
    }

    text = json.dumps(report, indent=2, ensure_ascii=False, default=str)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(text)
    print(text)
    ok = report["out_integrity"] == ["ok"] and not report["out_fk_check"]
    sys.exit(0 if ok else 2)


if __name__ == "__main__":
    main()
