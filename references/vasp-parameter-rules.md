# VASP Parameter Rule Management

This skill keeps VASP parameter experience in data files so the rules can be reviewed, extended, and overridden without rewriting workflow scripts.

## Files

- `config/rules/input-rules.psd1`: hard preflight checks for file completeness, POSCAR geometry, POTCAR order, and calculation-type consistency.
- `config/rules/parameters/incar-rules.psd1`: reusable INCAR defaults, task-specific parameter sets, element-group rules such as `LMAXMIX`, and review notes.
- `config/rules/parameters/kpoints-rules.psd1`: KPOINTS mesh policies, including Gamma-centered meshes and the lattice-length product rule.
- `config/rules/parameters/profiles.psd1`: task profiles such as `Relax`, `Scf`, `Dos`, `Band`, and `Phonon`; each profile connects an INCAR profile with a KPOINTS profile.
- `scripts/resolve_vasp_parameters.ps1`: loads the rule files, reads POSCAR when supplied, and prints the resolved recommendation.

## Scope

The parameter rules are recommendations, not hidden authority. They help Codex draft or review inputs consistently, while user choices and system-specific convergence tests remain decisive.

The current default KPOINTS policy uses a Gamma-centered mesh and chooses each component so that `component * lattice_length >= 25 Angstrom` for routine calculations. SCF and DOS use a denser default target of 35 Angstrom.

## Common Exceptions

- Slabs and molecules can need a small mesh component along a vacuum direction.
- Metallic, magnetic, correlated, or very small-cell systems often require explicit convergence tests.
- `MAGMOM`, DFT+U, SOC, hybrid functionals, van der Waals corrections, and pseudopotential variants must be selected deliberately for the material.
- `ISIF`, `IBRION`, `POTIM`, and `ADDGRID` may need adjustment when relaxation is unstable or when forces are the main observable.
