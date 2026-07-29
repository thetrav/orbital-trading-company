# Agent instructions

## Validation

After every batch of changes, run `./validate.sh` and verify all 5 checks pass before reporting done. The script runs `luacheck`, `lua-language-server`, `--dump-data`, `--create`, and `--load-game --until-tick 600`.

Do not skip this step. Do not rely only on headless Factorio — also check `luacheck` and `lua-language-server` output for regressions.
