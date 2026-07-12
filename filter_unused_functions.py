import json
import re
import sys
from pathlib import Path

def is_abstract_or_stub(code: str) -> bool:
    """Check if the function body contains only stubs like pass or raise NotImplementedError."""
    # Remove docstrings
    code = re.sub(r'\"\"\"[\s\S]*?\"\"\"', '', code)
    code = re.sub(r"\'\'\'[\s\S]*?\'\'\'", '', code)
    
    # Get lines of code, ignoring def/class lines, decorators, and empty lines
    lines = [line.strip() for line in code.split('\n') if line.strip()]
    
    body_lines = []
    for line in lines:
        if line.startswith('def ') or line.startswith('class ') or line.startswith('@') or line.startswith('async def '):
            continue
        body_lines.append(line)
        
    if not body_lines:
        return True
    
    # If the body is just pass, ..., or raise NotImplementedError
    if len(body_lines) == 1:
        line = body_lines[0]
        if line == 'pass' or line == '...' or line.startswith('raise NotImplementedError'):
            return True
            
    return False

def main():
    report_path = Path('codeflow-report.json')
    if not report_path.exists():
        print("Error: codeflow-report.json not found.")
        sys.exit(1)
        
    print("Loading codeflow-report.json...")
    with open(report_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    filtered_functions = []
    total_unused_in_report = data.get('summary', {}).get('unusedFunctions', 0)
    processed_unused = 0
    
    print("Filtering functions...")
    for file_info in data.get('files', []):
        path = file_info.get('path', '')
        
        # Skip test files entirely
        if path.startswith('tests/') or '/tests/' in path or path.startswith('test_') or path.endswith('_test.py') or path.endswith('_test.dart'):
            continue
            
        for func in file_info.get('functions', []):
            if not func.get('isUnused', False):
                continue
                
            processed_unused += 1
            name = func.get('name', '')
            
            # Skip magic methods
            if name.startswith('__') and name.endswith('__'):
                continue
                
            # Skip exported API
            if func.get('isExported', False):
                continue
                
            # Skip abstract interfaces or stubs
            code = func.get('code', '')
            if is_abstract_or_stub(code):
                continue
                
            # Keep the function
            filtered_functions.append({
                'file': path,
                'name': name,
                'line': func.get('line'),
                'type': func.get('type'),
                'code_snippet': code.strip()[:100] + '...' if len(code) > 100 else code.strip()
            })
            
    print("-" * 40)
    print(f"Original unused functions in summary: {total_unused_in_report}")
    print(f"Unused functions processed (excluding test files): {processed_unused}")
    print(f"Functions remaining after applying strict filters: {len(filtered_functions)}")
    print("-" * 40)
    
    output_path = Path('filtered-unused-functions.json')
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(filtered_functions, f, indent=2)
        
    print(f"Saved filtered list to: {output_path}")

if __name__ == '__main__':
    main()
