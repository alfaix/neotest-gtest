local neotest_config = require("neotest.config")
local assert = require("luassert")
local config_module = require("neotest-gtest.config")

describe("config library", function()
  after_each(function()
    config_module.reset()
  end)

  it("config exists without setup", function()
    assert.are.equal(3, config_module.history_size)
  end)

  it("setting values on get_config() updates module values", function()
    config_module.get_config().a = 1
    assert.are.equal(1, config_module.a)
  end)

  it("setting values on module updates get_config()) values", function()
    config_module.a = 1
    assert.are.equal(1, config_module.get_config().a)
  end)

  it("can override module-level functions", function()
    local old_get_config = config_module.get_config
    ---@diagnostic disable-next-line: duplicate-set-field
    config_module.get_config = function()
      return 1
    end
    assert.are.equal(1, config_module.get_config())
    config_module.get_config = old_get_config
  end)

  it("config setup is idempotent", function()
    config_module.setup({ history_size = 5 })
    assert.are.equal(5, config_module.history_size)
    config_module.setup({ history_size = 5 })
    assert.are.equal(5, config_module.history_size)
  end)

  it("setup() overrides defaults", function()
    require("neotest-gtest.config").setup({ history_size = 5 })
    assert.are.equal(5, config_module.history_size)
  end)

  it("check default is_test_file", function()
    assert.is_true(config_module.is_test_file("foo/bar/test_foo.cpp"))
    assert.is_true(config_module.is_test_file("foo/bar/test_foo.cppm"))
    assert.is_true(config_module.is_test_file("foo/bar/foo_test.cc"))
    assert.is_false(config_module.is_test_file("foo/bar/no.cc"))
    assert.is_false(config_module.is_test_file("foo/bar/test_stuff"))
  end)

  it("filter_dir falls back to neotest config", function()
    local old_projects = neotest_config.projects
    neotest_config.projects = {
      ["/mycoolproject"] = {
        discovery = {
          filter_dir = function(name, rel_path, root)
            return name ~= "bar"
          end,
        },
      },
    }

    assert.is_true(config_module.filter_dir("foo", "foo", "/mycoolproject"))
    assert.is_true(config_module.filter_dir("bar", "foo", "/otherproject"))
    assert.is_false(config_module.filter_dir("bar", "foo", "/mycoolproject"))
    neotest_config.projects = old_projects
  end)
end)
