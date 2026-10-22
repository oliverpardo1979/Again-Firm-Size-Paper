"""Refresh empirical outputs in dependency order using the corrected local input."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--rscript', default=shutil.which('Rscript') or r'C:\Program Files\R\R-4.5.2\bin\Rscript.exe')
parser.add_argument('--start', default='reconcile_regressions.R')
args = parser.parse_args()
steps = [
    'reconcile_regressions.R', 'update_regression_tables.py',
    'preferred_extensions.R', 'build_preferred_tables.py',
    'salaried_robustness.R', 'build_salaried_table.py',
    'income_counterfactuals.R', 'build_counterfactual_tables.py',
    'salaried_extensions.R', 'build_salaried_extensions_tables.py',
    'quadratic_preferred.R', 'build_quadratic_tables.py',
    'inference_audit_prepare.py', 'build_inference_tables.py',
    'plot_reconciled_regressions.R', 'plot_preferred_extensions.R',
    'plot_salaried_robustness.R', 'plot_quadratic_preferred.R',
    'descriptive_statistics.R', 'minimum_wage_distributions.R',
    'update_descriptive_assets.py', 'plot_sector_income.R',
]
logs = ROOT / 'build/primary_revision_logs'
logs.mkdir(parents=True, exist_ok=True)
for step in steps[steps.index(args.start):]:
    command = ([args.rscript, '--vanilla'] if step.endswith('.R') else [sys.executable])
    command.append(str(ROOT / 'replication' / step))
    print('Running ' + step, flush=True)
    with (logs / (step + '.log')).open('w', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((logs / (step + '.log')).read_text(encoding='utf-8', errors='replace')[-12000:])
        raise SystemExit(result.returncode)
    print('Completed ' + step, flush=True)
