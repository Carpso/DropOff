import sys

path = sys.argv[1] if len(sys.argv) > 1 else r'D:\Explorer\MAYUNDO\KEY PROJECTS\DropOff\app\lib\screens\booking_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    s = f.read()

stack = []
for idx, ch in enumerate(s):
    if ch == '[':
        stack.append(idx)
    elif ch == ']':
        if stack:
            stack.pop()
        else:
            line = s.count('\n', 0, idx) + 1
            print('EXTRA ] at', idx, 'line', line)
            sys.exit(0)
print('UNBALANCED_COUNT', len(stack))
if stack:
    idx = stack[-1]
    print('LAST_OPEN_AT', idx, 'line', s.count('\n', 0, idx) + 1)
    # print surrounding
    start = s.rfind('\n', 0, idx) + 1
    end = s.find('\n', idx)
    print(s[start:end])
