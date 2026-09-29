local function check()
  local source = {
    "function SumTo(n: int) -> int {",
    "  let total = 0;",
    "  let values: int[] = [];",
    "  let i = 0;",
    "  while (i < n) {",
    "    values.push(i);",
    "    i += 1;",
    "  }",
    "  for (let value in values) { total += value; }",
    "  return total;",
    "}",
    "function Main() -> int {",
    "  return SumTo(3);",
    "}",
  }
  local base = vim.fn.tempname()
  vim.fn.mkdir(base, "p")
  vim.env.BAML_HOME = base .. "/home"
  vim.env.BAML_CACHE_DIR = base .. "/cache"

  for _, layout in ipairs { "standalone", "baml_src", "manifest" } do
    local root = base .. "/" .. layout
    local dir = layout == "baml_src" and root .. "/baml_src" or root
    vim.fn.mkdir(dir, "p")
    if layout == "manifest" then vim.fn.writefile({}, root .. "/baml.toml") end
    local path = dir .. "/main.baml"
    vim.fn.writefile(source, path)
    vim.cmd.edit(vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    assert(vim.bo.filetype == "baml", "BAML filetype missing")
    local parser = vim.treesitter.get_parser(buf)
    assert(not parser:parse()[1]:root():has_error(), "BAML expression syntax did not parse")
    assert(vim.treesitter.highlighter.active[buf], "BAML highlighting did not start")
    local captures = {}
    local highlights = vim.treesitter.query.get("baml", "highlights")
    for id in highlights:iter_captures(parser:parse()[1]:root(), buf) do
      captures[highlights.captures[id]] = true
    end
    assert(captures["function"] and captures["keyword"] and captures["number"], "BAML highlight captures missing")

    local client
    assert(
      vim.wait(15000, function()
        client = vim.lsp.get_clients({ bufnr = buf, name = "baml" })[1]
        return client and client.initialized
      end, 20),
      "BAML LSP did not attach: " .. layout
    )
    if layout ~= "standalone" then assert(client.root_dir == root, "wrong BAML project root") end
    local position = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 12, character = 11 } }
    local hover = assert(client:request_sync("textDocument/hover", position, 10000, buf))
    assert(not hover.err and hover.result and hover.result.contents, "BAML hover missing")
    local definition = assert(client:request_sync("textDocument/definition", position, 10000, buf))
    assert(not definition.err and definition.result, "BAML definition missing: " .. vim.inspect(definition))
    local target = definition.result[1] or definition.result
    assert((target.range or target.targetSelectionRange).start.line == 0, "wrong BAML definition")
    local completion = assert(client:request_sync("textDocument/completion", position, 10000, buf))
    assert(not completion.err and completion.result, "BAML completion failed")
    local items = completion.result.items or completion.result
    assert(vim.iter(items):any(function(item) return item.label == "SumTo" end), "BAML function completion missing")

    vim.api.nvim_buf_set_lines(buf, 12, 13, false, { "  return MissingFunction(3);" })
    assert(
      vim.wait(10000, function()
        return vim.iter(vim.diagnostic.get(buf)):any(
          function(d) return d.severity == vim.diagnostic.severity.ERROR and d.message:find("MissingFunction", 1, true) end
        )
      end, 20),
      "BAML diagnostics did not update"
    )
    vim.api.nvim_buf_set_lines(buf, 12, 13, false, { source[13] })
    assert(
      vim.wait(
        10000,
        function() return #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR }) == 0 end,
        20
      ),
      "BAML diagnostics did not clear after fixing the error"
    )
    client:stop(true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  local prompt = 'function Greet(name: string) -> string { client "openai/gpt-4o" prompt #"Hello {{ name }}"# }'
  local parser = vim.treesitter.get_string_parser(prompt, "baml")
  assert(not parser:parse(true)[1]:root():has_error(), "BAML prompt did not parse")
  assert(parser:children().jinja, "BAML prompt did not inject Jinja")
  vim.fn.delete(base, "rf")
  print "BAML smoke passed: syntax, highlights, Jinja, LSP roots, hover, definition, completion, diagnostics"
end

vim.defer_fn(function()
  local ok, err = xpcall(check, debug.traceback)
  if not ok then
    print(err)
    vim.cmd.cquit()
  else
    vim.cmd.qa()
  end
end, 100)
