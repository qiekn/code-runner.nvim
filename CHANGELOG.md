# Changelog

## [Unreleased]

### Added

- `run_scripts` config: auto-detect project run scripts (`run.sh`, `Makefile`) and execute them with `:Run`
- `run_script_cmds` config: customize commands for each run script
- `term_position` config (`"bottom"` or `"right"`) and `term_width` for right-side splits
- `:RunTogglePosition` command to switch terminal position at runtime

### Changed

- Unified terminal management: toggle and exec now share a single bottom terminal instance
- `:Run` priority: run_scripts > filetype handler (cpp) > filetype_cmds

### Removed

- `use_terminal` option and `ToggleRunMode` command (bang mode dropped)
