import os, re, json, sys
s = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'app', 'src', 'main', 'java', 'fr', 'rochetoirin', 'sim', 'render', 'Shaders.kt')).read()
out = {}
for m in re.finditer(r'(?:private )?const val (\w+) = (.*?)(?="""|"#)("""(.*?)"""|"(.*?)")', s, re.S):
    name, prefix = m.group(1), m.group(2)
    body = m.group(4) if m.group(4) is not None else m.group(5).encode().decode('unicode_escape')
    v = ''.join(out[p.strip()] for p in prefix.split('+') if p.strip())
    out[name] = v + body
json.dump(out, open(os.path.join(sys.argv[1] if len(sys.argv) > 1 else '.', 'shadersrc.json'), 'w'))
print(list(out))
