#!/usr/bin/env python3
"""Fail closed when implementation or docs changed since their manual review."""
import hashlib,json,pathlib,plistlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
TRACKED=['Sources/App.swift','Sources/Controls.swift','Sources/ResourceCalendarUI.swift','Sources/Help.swift','Sources/Core.swift','Info.plist','docs/Help.json']
def digest(): return {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in TRACKED}
def validate():
    d=json.loads((ROOT/'docs/Help.json').read_text())
    v=plistlib.loads((ROOT/'Info.plist').read_bytes())['CFBundleShortVersionString']
    assert d['version']==v,'Help version differs from application'
    assert d.get('reviewedRevision'),'Missing reviewedRevision'
    rows=d['sections'];assert len(rows)>=3,'Missing sections'
    assert len({r['id'] for r in rows})==len(rows),'Duplicate topic IDs'
    assert {r['group'] for r in rows}=={'Пользователь','Администратор','Разработчик'},'Missing manual group'
    for r in rows:
        assert r['id'] and r['title'] and r['paragraphs'],'Empty topic'
        assert all(isinstance(p,str) and p.strip() for p in r['paragraphs']),'Empty paragraph'
    b=(ROOT/'build.command').read_text()
    assert 'Sources/Help.swift' in b and 'cp docs/Help.json' in b and 'python3 scripts/check_help.py' in b,'Missing build integration'
    return d
if __name__=='__main__':
    try:
        validate(); manifest=ROOT/'docs/help-sync.json'
        if sys.argv[1:]==['--record']:
            manifest.write_text(json.dumps(digest(),indent=2)+'\n'); print('Recorded manual review. Review text and UI before using this command.')
        else:
            assert not sys.argv[1:],'Usage: check_help.py [--record]'
            old=json.loads(manifest.read_text());new=digest()
            assert old==new,'Справка требует проверки: обновите docs/Help.json и выполните python3 scripts/check_help.py --record после ручной сверки.'
            print('Help structure, version, resource integration and review fingerprints OK')
    except (AssertionError,ValueError,KeyError,OSError) as e:
        print(str(e),file=sys.stderr);sys.exit(1)
