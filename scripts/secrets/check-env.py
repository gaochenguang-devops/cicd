import re, pathlib

root = pathlib.Path(r'C:\Users\morning\Desktop\cicd')
envtpl = (root / '.env.example').read_text(encoding='utf-8')
keys = set(re.findall(r'^([A-Z0-9_]+)=', envtpl, flags=re.M))

placeholder = re.compile(r'\$\{([A-Z0-9_]+)\}|__([A-Z0-9_]{3,})__')
allowed_shell = {'SSH_HOST'}  # 非凭据变量无需在 .env.example 出现? 实际都在
missing = []
used = set()
for f in root.rglob('*'):
    if f.is_dir() or f.name in ('.env', '.env.example'):
        continue
    if '.git' in f.parts:
        continue
    if f.suffix.lower() not in ('.md', '.sh', '.py', '.yaml', '.yml'):
        continue
    try:
        t = f.read_text(encoding='utf-8')
    except Exception:
        continue
    for m in placeholder.finditer(t):
        name = m.group(1) or m.group(2)
        used.add(name)
        if name not in keys:
            missing.append((str(f.relative_to(root)), name))

print('占位变量总数:', len(used))
print('已定义键数:', len(keys))
print('未定义在 .env.example 的变量:', sorted({n for _, n in missing}))
print('涉及文件:', sorted({p for p, _ in missing})[:6], '共', len({p for p, _ in missing}))
print('模板里未被引用的键:', sorted(keys - used))
