import os
import re

def process_file(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    content = "".join(lines)
    
    # Check if logging is needed
    if 'logging.' in content:
        # Add import if missing
        has_logging_import = re.search(r'"app-builds/common/logging"', content)
        if not has_logging_import:
            # Find import block
            import_match = re.search(r'import \((.*?)\)', content, re.DOTALL)
            if import_match:
                imports = import_match.group(1)
                new_imports = imports + '\t"app-builds/common/logging"\n'
                content = content.replace(imports, new_imports)
            else:
                # Handle single line import or no import
                content = re.sub(r'package \w+', lambda m: m.group(0) + '\n\nimport "app-builds/common/logging"', content, count=1)

    # Remove unused log import
    if not re.search(r'\blog\.\w+', content):
        content = re.sub(r'^\t"log"\n', '', content, flags=re.MULTILINE)
        content = re.sub(r'^import "log"\n', '', content, flags=re.MULTILINE)
        content = re.sub(r'^\s*"log"\s*$', '', content, flags=re.MULTILINE) # Handle multiline import without tab

    with open(filepath, 'w') as f:
        f.write(content)

for root, dirs, files in os.walk('rag-stack/services'):
    for file in files:
        if file.endswith('.go'):
            process_file(os.path.join(root, file))
