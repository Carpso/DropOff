import glob, re
for p in glob.glob(r'D:\Explorer\MAYUNDO\KEY PROJECTS\DropOff\app\lib\**\*.dart', recursive=True):
    src = open(p, encoding='utf-8').read()
    for m in re.finditer(r'Row\(children: \[\s*(?:const )?Icon\(Icons\.([a-z_]+)', src):
        line = src[:m.start()].count('\n') + 1
        print(f'{p.split(chr(92) + "lib" + chr(92))[-1]}:{line}  {m.group(1)}')
