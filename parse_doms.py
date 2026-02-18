
import re

def parse_domstats(filename):
    with open(filename, 'r') as f:
        content = f.read()

    domains = content.split("Domain: '")
    results = []

    for dom_block in domains[1:]:
        name = dom_block.split("'")[0]
        
        # Balloon current (Memory in KiB)
        balloon_match = re.search(r'balloon\.current=(\d+)', dom_block)
        memory_kib = int(balloon_match.group(1)) if balloon_match else 0
        memory_gib = memory_kib / (1024 * 1024)
        
        # VCPU current
        vcpu_match = re.search(r'vcpu\.current=(\d+)', dom_block)
        cpus = int(vcpu_match.group(1)) if vcpu_match else 0
        
        # Storage (sum of block.X.capacity)
        # Capacity is usually the provisioned size
        # Physical is the actual host size used if thin provisioned
        storage_matches = re.findall(r'block\.\d+\.capacity=(\d+)', dom_block)
        storage_bytes = sum(int(size) for size in storage_matches)
        storage_gib = storage_bytes / (1024**3)
        
        results.append({
            'name': name,
            'memory_gib': memory_gib,
            'cpus': cpus,
            'storage_gib': storage_gib
        })
    
    return results

def print_table(data):
    header = f"{'Domain Name':<15} | {'Memory (GiB)':<15} | {'CPU Count':<10} | {'Storage (GiB)':<15}"
    print(header)
    print("-" * len(header))
    for row in data:
        print(f"{row['name']:<15} | {row['memory_gib']:>15.2f} | {row['cpus']:>10} | {row['storage_gib']:>15.2f}")

if __name__ == "__main__":
    data = parse_domstats('doms.dat')
    print_table(data)
