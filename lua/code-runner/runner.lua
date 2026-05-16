local terminal = require("code-runner.terminal")

local M = {}

local exe_ext = vim.fn.has("win32") == 1 and ".exe" or ""

--- Escape Lua pattern metacharacters
---@param s string
---@return string
local function pat_escape(s)
	return (s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"))
end

--- Literal gsub replacement (escape % in replacement string)
---@param s string
---@param pattern string
---@param repl string
---@return string
local function gsub_literal(s, pattern, repl)
	return (s:gsub(pattern, repl:gsub("%%", "%%%%")))
end

--- Resolve CMake project root and build dir from current buffer
---@return table|nil
local function cmake_ctx()
	local root = vim.fs.root(0, "CMakeLists.txt")
	if not root then
		return nil
	end
	return { root = root, build = root .. "/build" }
end

--- Resolve Cargo project root from current buffer
---@return table|nil
local function cargo_ctx()
	local root = vim.fs.root(0, "Cargo.toml")
	if not root then
		return nil
	end
	return { root = vim.fs.normalize(root) }
end

--- Parse the minimal Cargo.toml data needed for selecting a run target
---@param root string
---@return table
local function cargo_manifest_info(root)
	local path = root .. "/Cargo.toml"
	if vim.fn.filereadable(path) ~= 1 then
		return { bins = {} }
	end

	local info = { bins = {} }
	local section = nil
	local current_bin = nil

	local function flush_bin()
		if current_bin and current_bin.name then
			table.insert(info.bins, current_bin)
		end
		current_bin = nil
	end

	for _, line in ipairs(vim.fn.readfile(path)) do
		local trimmed = line:gsub("%s+#.*$", ""):match("^%s*(.-)%s*$")

		if trimmed == "[package]" then
			flush_bin()
			section = "package"
		elseif trimmed == "[[bin]]" then
			flush_bin()
			section = "bin"
			current_bin = {}
		elseif trimmed:match("^%[") then
			flush_bin()
			section = nil
		else
			local key, value = trimmed:match('^([%w%-_]+)%s*=%s*"(.-)"')
			if key and value then
				if section == "package" then
					if key == "name" then
						info.package_name = value
					elseif key == "default-run" then
						info.default_run = value
					end
				elseif section == "bin" then
					if key == "name" then
						current_bin.name = value
					elseif key == "path" then
						current_bin.path = value:gsub("\\", "/")
					end
				end
			end
		end
	end

	flush_bin()
	return info
end

--- Expand placeholders in a command template
---@param template string
---@return string
local function expand(template)
	local values = {
		file = vim.fn.shellescape(vim.fn.expand("%:.")),
		name = vim.fn.shellescape(vim.fn.expand("%:t:r")),
		dir = vim.fn.shellescape(vim.fn.expand("%:.:h")),
	}

	return template:gsub("{(%w+)}", function(key)
		return values[key] or ("{" .. key .. "}")
	end)
end

--- Convert src/ relative path to test/ relative path
--- src/stl/unordered_map.cpp -> test/stl/unordered_map_test.cpp
---@param rel string
---@param config table
---@return string
local function src_to_test(rel, config)
	local src_pat = "^" .. pat_escape(config.cpp.src_dir) .. "/"
	return rel:gsub(src_pat, config.cpp.test_dir .. "/"):gsub("%.cpp$", "_test.cpp")
end

--- Check if string starts with prefix
---@param s string
---@param prefix string
---@return boolean
local function starts_with(s, prefix)
	return s:sub(1, #prefix) == prefix
end

--- Derive a PascalCase test suite name from filename
--- unordered_map -> UnorderedMap
---@param name string
---@return string
local function to_test_suite(name)
	return name:gsub("(%a)([%w]*)", function(first, rest)
		return first:upper() .. rest
	end):gsub("_", "")
end

--- Build and execute a cmake target
---@param root string
---@param build_dir string
---@param target string
---@param config table
local function cmake_run(root, build_dir, target, config)
	local q = vim.fn.shellescape
	terminal.exec(
		"cmake -B "
			.. q(build_dir)
			.. " -S "
			.. q(root)
			.. " && cmake --build "
			.. q(build_dir)
			.. " --target "
			.. q(target)
			.. " -j && "
			.. q(build_dir .. "/" .. target .. exe_ext),
		config
	)
end

--- Run a C++ file: CMake project or single-file fallback
---@param config table
local function run_cpp(config)
	local ctx = cmake_ctx()

	-- single-file fallback: no CMakeLists.txt
	if not ctx then
		terminal.exec(expand(config.cpp.single_file_cmd), config)
		return
	end

	local exe_name = vim.fn.expand("%:t:r")
	local rel = vim.fn.expand("%:.")
	local target = exe_name
	local src_prefix = config.cpp.src_dir .. "/"

	-- if editing a src file and a corresponding test exists, run the test
	if starts_with(rel, src_prefix) then
		local test_file = src_to_test(rel, config)
		if vim.fn.filereadable(ctx.root .. "/" .. test_file) == 1 then
			target = exe_name .. "_test"
		end
	end

	cmake_run(ctx.root, ctx.build, target, config)
end

--- Build a cargo run command from the current Rust file path when possible
---@return string|nil
local function cargo_run_cmd()
	local ctx = cargo_ctx()
	if not ctx then
		return nil
	end

	local buf = vim.api.nvim_buf_get_name(0)
	if buf == "" then
		return nil
	end

	local abs = vim.fs.normalize(buf)
	local root_prefix = ctx.root .. "/"
	if not starts_with(abs, root_prefix) then
		return nil
	end

	local rel = abs:sub(#root_prefix + 1)
	local q = vim.fn.shellescape
	local manifest = cargo_manifest_info(ctx.root)

	local bin = rel:match("^src/bin/([^/]+)%.rs$")
	if bin then
		return "cd " .. q(ctx.root) .. " && cargo run --bin " .. q(bin)
	end

	local example = rel:match("^examples/([^/]+)%.rs$")
	if example then
		return "cd " .. q(ctx.root) .. " && cargo run --example " .. q(example)
	end

	for _, item in ipairs(manifest.bins) do
		if item.path == rel then
			return "cd " .. q(ctx.root) .. " && cargo run --bin " .. q(item.name)
		end
	end

	if manifest.default_run then
		return "cd " .. q(ctx.root) .. " && cargo run --bin " .. q(manifest.default_run)
	end

	if rel == "src/main.rs" and manifest.package_name then
		return "cd " .. q(ctx.root) .. " && cargo run --bin " .. q(manifest.package_name)
	end

	return nil
end

--- Run a Rust file in a Cargo project when the target can be inferred
---@param config table
---@return boolean
local function run_rust(config)
	local cargo_cmd = cargo_run_cmd()
	if cargo_cmd then
		terminal.exec(cargo_cmd, config)
		return true
	end

	local cmd_template = config.filetype_cmds.rust
	if cmd_template then
		terminal.exec(expand(cmd_template), config)
		return true
	end

	return false
end

--- Check for run_scripts in project root and return the command if found
---@param config table
---@return string|nil cmd
local function detect_run_script(config)
	if not config.run_scripts or #config.run_scripts == 0 then
		return nil
	end

	local root = vim.fs.root(0, config.run_scripts)
	if not root then
		return nil
	end

	for _, script in ipairs(config.run_scripts) do
		if vim.fn.filereadable(root .. "/" .. script) == 1 then
			local cmd = (config.run_script_cmds or {})[script] or ("./" .. script)
			return "cd " .. vim.fn.shellescape(root) .. " && " .. cmd
		end
	end
	return nil
end

--- :Run command handler
---@param config table
function M.run(config)
	if vim.bo.buftype ~= "" then
		vim.notify("Run: not a file buffer", vim.log.levels.WARN)
		return
	end

	-- 1. run_scripts (highest priority)
	local script_cmd = detect_run_script(config)
	if script_cmd then
		terminal.exec(script_cmd, config)
		return
	end

	local ft = vim.bo.filetype

	-- 2. filetype special handling (cpp)
	if ft == "cpp" then
		run_cpp(config)
		return
	end

	-- 2b. filetype special handling (rust)
	if ft == "rust" and run_rust(config) then
		return
	end

	-- 3. filetype_cmds
	local cmd_template = config.filetype_cmds[ft]
	if cmd_template then
		terminal.exec(expand(cmd_template), config)
		return
	end

	vim.notify("Run: unsupported filetype: " .. ft, vim.log.levels.WARN)
end

--- :Test command handler (C++ only)
---@param config table
function M.test(config)
	if vim.bo.filetype ~= "cpp" then
		vim.notify("Test: only works for C++ files.", vim.log.levels.WARN)
		return
	end

	local ctx = cmake_ctx()
	if not ctx then
		vim.notify("Test: CMakeLists.txt not found.", vim.log.levels.WARN)
		return
	end

	local rel = vim.fn.expand("%:.")
	local test_prefix = config.cpp.test_dir .. "/"
	local src_prefix = config.cpp.src_dir .. "/"

	-- already editing a test file -> just run it
	if starts_with(rel, test_prefix) then
		cmake_run(ctx.root, ctx.build, vim.fn.expand("%:t:r"), config)
		return
	end

	if not starts_with(rel, src_prefix) then
		vim.notify(
			"Test: file must be under " .. config.cpp.src_dir .. "/ or " .. config.cpp.test_dir .. "/.",
			vim.log.levels.WARN
		)
		return
	end

	local test_rel = src_to_test(rel, config)
	local test_path = ctx.root .. "/" .. test_rel

	-- test file exists -> open it
	if vim.fn.filereadable(test_path) == 1 then
		vim.cmd("edit " .. vim.fn.fnameescape(test_path))
		return
	end

	-- scaffold new test file
	local test_pat = "^" .. pat_escape(config.cpp.test_dir) .. "/"
	local include_path = test_rel:gsub(test_pat, ""):gsub("_test%.cpp$", ".cpp")
	local suite = to_test_suite(vim.fn.expand("%:t:r"))

	local lines = {
		'#include "' .. include_path .. '"  // NOLINT: include .cpp directly for testing',
		"",
		"#include <gtest/gtest.h>",
		"",
		"TEST(" .. suite .. "Test, BasicUsage) {",
		"  // TODO: write test",
		"  EXPECT_TRUE(true);",
		"}",
	}

	vim.fn.mkdir(vim.fn.fnamemodify(test_path, ":h"), "p")
	vim.cmd("edit " .. vim.fn.fnameescape(test_path))
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.cmd("write")
end

return M
