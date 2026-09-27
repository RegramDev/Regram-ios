"""Syntax-only check; does not invoke swiftc, Xcode or Bazel. Requires tree-sitter-swift."""
import json
import pathlib
import subprocess
from tree_sitter import Language, Parser
import tree_sitter_swift

root = pathlib.Path.cwd()
parser = Parser(Language(tree_sitter_swift.language()))
names = subprocess.check_output(['git', 'diff', '--name-only', '-z']).split(b'\0')
names += subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z']).split(b'\0')

def errors(data):
    tree = parser.parse(data)
    found = []
    nodes = [tree.root_node]
    while nodes:
        node = nodes.pop()
        if node.type == 'ERROR' or node.is_missing:
            found.append({'line': node.start_point.row + 1, 'text': data[node.start_byte:node.end_byte].decode(errors='replace')[:140]})
        nodes.extend(reversed(node.children))
    return found

result = []
for name in sorted(set(names)):
    if not name.endswith(b'.swift'):
        continue
    filename = name.decode()
    current = errors((root / filename).read_bytes())
    previous = subprocess.run(['git', 'show', 'HEAD:' + filename], capture_output=True)
    baseline = errors(previous.stdout) if previous.returncode == 0 else []
    new = [item for item in current if item['text'] not in {old['text'] for old in baseline}]
    result.append({'file': filename, 'existing_parser_issues': len(baseline), 'new_parser_issues': new})
output = {'files': len(result), 'new_errors': sum(len(item['new_parser_issues']) for item in result), 'details': result}
pathlib.Path(__file__).with_name('syntax-results.json').write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(output, ensure_ascii=False, indent=2))
raise SystemExit(output['new_errors'] > 0)
