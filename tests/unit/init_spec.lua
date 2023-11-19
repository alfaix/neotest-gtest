local Report = require("neotest-gtest.report")
local assert = require("luassert")
local config_module = require("neotest-gtest.config")
local init_module = require("neotest-gtest")
local stub = require("luassert.stub")
local neotest_adapter = require("neotest-gtest.neotest_adapter")

describe("config is properly used", function()
  after_each(function()
    config_module.reset()
  end)

  it("user-supplied is_test_file is used", function()
    init_module.setup({
      is_test_file = function(path)
        return path == "abcd"
      end,
    })
    assert.is_true(init_module.is_test_file("abcd"))
    assert.is_false(init_module.is_test_file("abc"))
  end)

  it("user-supplied filter_dir is used", function()
    init_module.setup({
      filter_dir = function(name, relpath, root)
        return name == "abcd"
      end,
    })
    assert.is_true(init_module.filter_dir("abcd", nil, nil))
    assert.is_false(init_module.filter_dir("abc", nil, nil))
  end)
end)

describe("test GTestNeotestAdapter.build_spec", function()
  local mock_adapter
  before_each(function()
    mock_adapter = {
      _args = nil,
      assert_called_with_args = function(self, args)
        assert.are.same(args, self._args)
      end,
      build_specs = function(self)
        return self.specs_result
      end,
      specs_result = {},
    }
    stub(neotest_adapter, "new", function(cls, args)
      mock_adapter._args = args
      return mock_adapter
    end)
  end)

  after_each(function()
    neotest_adapter.new:revert()
    config_module.reset()
  end)

  it("build_spec forwards the call to adapter", function()
    local args = {}
    local specs = init_module.build_spec(args)
    assert.are.equal(args, mock_adapter._args)
    assert.are.equal(mock_adapter.specs_result, specs)
  end)

  it("build_spec forwards extra args from config to adapter", function()
    config_module.setup({
      extra_args = { "--gtest_repeat=2" },
    })
    local args = {}
    init_module.build_spec(args)
    assert.are.same(mock_adapter._args, { extra_args = { "--gtest_repeat=2" } })
  end)

  it("build_spec prefers args from the call over args from config", function()
    config_module.setup({
      extra_args = { "--gtest_repeat=2" },
    })
    local args = { extra_args = { "--gtest_repeat=3" } }
    init_module.build_spec(args)
    assert.are.same(mock_adapter._args, { extra_args = { "--gtest_repeat=3" } })
  end)
end)

describe("test GTestNeotestAdapter.root", function()
  local report_mock
  before_each(function()
    report_mock = {
      _args = nil,
      assert_called_with_args = function(self, args)
        assert.are.same(args, self._args)
      end,
      make_neotest_results = function(self)
        return self.specs_result
      end,
      specs_result = {},
    }
    local converter = Report.converter
    stub(converter, "new", function(cls, spec, result, tree)
      report_mock._args = { spec = spec, result = result, tree = tree }
      return report_mock
    end)
  end)

  after_each(function()
    Report.converter.new:revert()
    config_module.reset()
  end)

  it("build_spec forwards the call to adapter", function()
    -- exact values are irrelevant, just checking forwarding
    local args = { spec = { 1 }, result = { 2 }, tree = { 3 } }
    local specs = init_module.results(args.spec, args.result, args.tree)
    assert.are.same(args, report_mock._args)
    assert.are.equal(report_mock.specs_result, specs)
  end)
end)
