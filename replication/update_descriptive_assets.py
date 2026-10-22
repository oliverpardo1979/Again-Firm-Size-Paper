"""Refresh descriptive assets while preserving the edited table structure and notes."""
from pathlib import Path
from collections import defaultdict
import csv
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / 'build/descriptive_refresh/Paper'
PAPER = ROOT / 'Paper'


def fields(line):
    return [x.strip() for x in line.strip().removesuffix(r'\\').split('&')]


def key(cells):
    # Dimension tables use the second column as the group label.
    label = cells[1] if len(cells) == 6 and cells[1] and not re.search(r'\d', cells[1]) else cells[0]
    return label.replace('--', '-').replace(' (2025 pesos)', '')


def numeric_row(line):
    return '&' in line and re.search(r'&\s*-?[\d,]+(?:\.\d+)?(?:\\%)?\s*(?:&|\\\\)', line)


names = [
    'descriptive_core_size_2008_2025_table', 'descriptive_wage_gaps_2025_table',
    'descriptive_worker_characteristics_2025_table', 'descriptive_formal_worker_profile_2025_table',
    'minimum_wage_bunching_2025_table', 'minimum_wage_monthly_bunching_2025_table',
]
for name in names:
    new = (STAGE / 'sections' / (name + '.tex')).read_text(encoding='utf-8-sig')
    target = PAPER / 'sections' / (name + '.tex')
    old = target.read_text(encoding='utf-8-sig')
    replacements = defaultdict(list)
    for line in new.splitlines():
        if numeric_row(line):
            cells = fields(line)
            replacements[key(cells)].append(cells)
    result, checked = [], 0
    for line in old.splitlines():
        if numeric_row(line):
            cells = fields(line)
            candidates = replacements[key(cells)]
            assert candidates, (name, cells)
            replacement = candidates.pop(0)
            assert len(cells) == len(replacement), (name, cells, replacement)
            # Keep user-edited row labels, indentation, and dimension headings.
            first_number = next(i for i, c in enumerate(cells) if i and re.match(r'-?[\d,]', c))
            result.append('    ' + ' & '.join(cells[:first_number] + replacement[first_number:]) + r' \\')
            checked += 1
        else:
            result.append(line)
    assert checked > 0, name
    target.write_text('\n'.join(result) + '\n', encoding='utf-8')
    print(name, checked)

for source in (STAGE / 'tables').glob('*.csv'):
    target = PAPER / 'tables' / source.name
    shutil.copyfile(source, target)
for base in ('fig69', 'fig70', 'fig72', 'fig77'):
    for lang in ('en', 'es'):
        shutil.copyfile(STAGE / 'figures' / f'{base}_{lang}.png', PAPER / 'figures' / f'{base}_{lang}.png')
print('Updated active descriptive figures and aggregate tables.')
