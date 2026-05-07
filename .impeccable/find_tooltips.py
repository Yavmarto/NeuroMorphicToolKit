import os
import re

def find_icon_buttons_without_tooltip(directory):
    # Use word boundary to avoid matching _FileActionIconButton
    icon_button_pattern = re.compile(r'\bIconButton\s*\(')
    
    results = []
    
    for root, dirs, files in os.walk(directory):
        if any(d in root for d in ['node_modules', '.git', 'build', '.dart_tool']):
            continue
            
        for file in files:
            if file.endswith('.dart'):
                path = os.path.join(root, file)
                with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    
                    # Find all occurrences of IconButton(
                    for match in icon_button_pattern.finditer(content):
                        start_pos = match.start()
                        
                        # Find the end of the constructor
                        paren_count = 0
                        constructor_end = -1
                        for i in range(start_pos + match.group().find('('), len(content)):
                            if content[i] == '(':
                                paren_count += 1
                            elif content[i] == ')':
                                paren_count -= 1
                                if paren_count == 0:
                                    constructor_end = i + 1
                                    break
                        
                        if constructor_end != -1:
                            constructor_text = content[start_pos:constructor_end]
                            if 'tooltip:' not in constructor_text:
                                line_number = content.count('\n', 0, start_pos) + 1
                                results.append(f"{path}:{line_number}")
                                
    return results

if __name__ == "__main__":
    workspace = "/Users/yoshimartodihardjo/NeuroMorphicToolKit"
    findings = find_icon_buttons_without_tooltip(workspace)
    for finding in findings:
        print(finding)
