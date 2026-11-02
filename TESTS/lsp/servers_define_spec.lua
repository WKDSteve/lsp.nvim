--- Covers `lsp.servers.define`, the registration skeleton shared by the plain
--- server modules: shared hooks filled in, a server's own key winning, and
--- `enable = false` meaning "register, do not enable".

describe("lsp.servers.define", function()
  local define = require("lsp.servers.define")
  local real_config, real_enable
  ---@type table<string, table>
  local configs
  ---@type string[]
  local enabled

  before_each(function()
    configs, enabled = {}, {}
    real_config, real_enable = vim.lsp.config, vim.lsp.enable
    vim.lsp.config = setmetatable({}, {
      __call = function(_, name, cfg)
        configs[name] = cfg
      end,
    })
    vim.lsp.enable = function(name)
      enabled[#enabled + 1] = name
    end
  end)

  after_each(function()
    vim.lsp.config, vim.lsp.enable = real_config, real_enable
  end)

  it("registers the spec with the shared hooks and enables the server", function()
    local function on_attach() end
    define("demo", { capabilities = { x = 1 }, on_attach = on_attach }, nil, { cmd = { "demo" } })
    assert.are.same({ "demo" }, configs.demo.cmd)
    assert.are.same({ x = 1 }, configs.demo.capabilities)
    assert.are.equal(on_attach, configs.demo.on_attach)
    assert.are.same({ "demo" }, enabled)
  end)

  it("lets the server's own key win over the shared one", function()
    local function mine() end
    define("demo", { on_attach = function() end }, {}, { on_attach = mine })
    assert.are.equal(mine, configs.demo.on_attach)
  end)

  it("registers but does not enable with enable = false", function()
    define("demo", nil, { enable = false }, { cmd = { "demo" } })
    assert.is_not_nil(configs.demo)
    assert.are.same({}, enabled)
  end)

  it("does nothing when vim.lsp.config is not a table", function()
    vim.lsp.config = nil
    define("demo", nil, nil, { cmd = { "demo" } })
    assert.are.same({}, configs)
    assert.are.same({}, enabled)
  end)
end)
