# code-runner.nvim

A lightweight Neovim plugin for building and running code. Specialized for C++ CMake projects with single-file fallback, plus extensible multi-language support.

## Features

- **C++ CMake projects**: auto-detect `CMakeLists.txt`, build with `cmake`, run targets
- **C++ single file**: no CMake? compile directly with configurable command
- **Test integration**: `:Test` opens/scaffolds GoogleTest files, `:Run` prefers test if it exists
- **Multi-language**: extensible `filetype_cmds` for any language
- **Toggle terminal**: persistent bottom split terminal

## Install

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "qiekn/code-runner.nvim",
  config = function()
    require("code-runner").setup()
  end,
}
```

## Configuration

All options with defaults:

```lua
require("code-runner").setup({
  use_terminal = true,       -- true: split terminal, false: :! mode
  term_height = 15,
  cpp = {
    single_file_cmd = "clang++ -std=c++23 -stdlib=libc++ -o /tmp/{name} {file} && /tmp/{name}",
    test_dir = "test",       -- test directory name
    src_dir = "src",         -- source directory name
  },
  filetype_cmds = {
    javascript = "node {file}",
    -- python = "python3 {file}",
    -- go = "go run {file}",
  },
  keymaps = {
    toggle_term = "<leader>j",  -- set to false to disable
  },
})
```

### Placeholders

| Placeholder | Expands to |
|-------------|------------|
| `{file}` | Relative path from cwd (`src/foo/bar.cpp`) |
| `{name}` | Filename without extension (`bar`) |
| `{dir}` | File's directory relative to cwd (`src/foo`) |

## Commands

| Command | Description |
|---------|-------------|
| `:Run` | Build and run current file. C++ uses CMake if available, otherwise single-file compile. Prefers test target if one exists. Other languages use `filetype_cmds`. |
| `:Test` | C++ only. Opens matching test file, or scaffolds a new GoogleTest file. If already in a test file, builds and runs it. |
| `:RunToggle` | Switch between terminal and `:!` output mode. |

## C++ Run Strategy

`:Run` on a C++ file follows this logic:

1. **CMake project** (finds `CMakeLists.txt` upward):
   - If editing `src/foo.cpp` and `test/foo_test.cpp` exists → run `foo_test` target
   - Otherwise → run `foo` target
   - Command: `cmake -B build -S <root> && cmake --build build --target <name> -j && build/<name>`

2. **Single file** (no `CMakeLists.txt`):
   - Uses `cpp.single_file_cmd` with placeholder expansion
   - Default: `clang++ -std=c++23 -stdlib=libc++ -o /tmp/{name} {file} && /tmp/{name}`

## Test Scaffolding

`:Test` on `src/stl/unordered_map.cpp` creates `test/stl/unordered_map_test.cpp`:

```cpp
#include "stl/unordered_map.cpp"  // NOLINT: include .cpp directly for testing

#include <gtest/gtest.h>

TEST(UnorderedMapTest, BasicUsage) {
  // TODO: write test
  EXPECT_TRUE(true);
}
```

## License

MIT
