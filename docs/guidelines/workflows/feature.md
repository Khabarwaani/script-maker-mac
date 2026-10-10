# Feature

New capability, UI, model, emotion, format, or prompt. Need an approved spec (`docs/REQUIREMENTS_vX.Y.md` or GitHub issue) and a plan before code. Output: `feature/` branch, fail-loud code, old payloads still load, PR (UT runs on git pipeline).

1. No feature commits without that spec + plan.
2. Missing data raises. No silent fallback or invented default.
3. Enums/constants → `src/core/constants/` (package). Models → `src/core/models.py`. Prompts → `src/core/prompt_matrix.py` and `src/script_maker/prompts/`. UI → `src/script_maker/ui/`.
4. Saved stories and old schemas must still load.

```bash
./create_branch feature/<name>
git add <files> && git commit -m "feat: (#<issue>) <desc>"
./open_pr -t "feat: (#<issue>) <desc>"
# verify server CI: gh pr checks
# if green -> gh pr ready; if red -> ./runut, fix, push
./merge_pr <num>  # only after user approval
```
