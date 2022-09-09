local assert = require("luassert")
local runners = require("neotest-gtest.runner")

local Runner = runners.Runner
-- TODO something more reliable and cross-platform?
local some_executable = "/bin/sh"

local function reset()
  runners._runners = {}
  runners._runners_executable2idx = {}
  runners._last_chosen = nil
end

describe("runners library", function()
  before_each(function()
    reset()
  end)

  it("constructor correctly initializes attributes", function()
    local runner, err = Runner:new(some_executable, { "/foo/bar" })
    assert(runner ~= nil) -- type checker doesn't understand assert.is_not_nil
    assert.is_nil(err)
    assert.are.equal(some_executable, runner:executable())
    assert.is_true(runner:owns("/foo/bar"))
  end)

  it("constructor throws if executable doesn't exist", function()
    local runner, err = Runner:new("/noshotthisexistsright", {})
    assert.is_nil(runner)
    assert.is_not_nil(err)
  end)

  it("constructor throws if executable is a directory", function()
    local runner, err = Runner:new("/", {})
    assert.is_nil(runner)
    assert.is_not_nil(err)
  end)

  it("to_json/from_json reconstruct the object", function()
    local runner, _ = Runner:new(some_executable, { "/foo/bar" })
    assert(runner ~= nil)
    local json = runner:to_json()
    local runner2, _ = Runner:from_json(json)
    assert.are_equal(runner2:executable(), runner:executable())
    assert(runner2:owns("/foo/bar"))
  end)

  describe("adding paths", function()
    it("adds paths", function()
      local runner, _ = Runner:new(some_executable, {})
      assert(runner ~= nil)
      runner:add_path("/foo/baz")
      assert(runner:owns("/foo/baz"))
    end)

    it("owning a directory implies owning children", function()
      local runner, _ = Runner:new(some_executable, { "/foo/bar" })
      assert(runner ~= nil)
      assert(runner:owns("/foo/bar/baz"))
    end)

    it("doesn't add duplicate paths", function()
      local runner, _ = Runner:new(some_executable, { "/foo/bar" })
      assert(runner ~= nil)
      runner:add_path("/foo/bar/baz")
      assert(runner:owns("/foo/bar/baz"))
      assert(runner:owns("/foo/bar"))
      assert.are_equal(1, #runner:paths())
    end)

    it("adding a parent removes redundant entries", function()
      local runner, _ = Runner:new(some_executable, { "/foo/bar", "/foo/baz", "/foo/bar/baz" })
      assert(runner ~= nil)
      runner:add_path("/foo")
      assert(runner:owns("/foo"))
      assert(runner:owns("/foo/something"))
      assert.are_equal(1, #runner:paths())
    end)
  end)

  describe("runner API", function()
    it("add_runner adds runners", function()
      local runner, _ = Runner:new(some_executable, { "/foo/bar" })
      assert(runner ~= nil)

      local added, err = runners.add_runner(runner)
      assert(err == nil)
      assert.are.equal(added, runner)
      local all_runners = runners.find_runners({})
      assert.are.equal(#all_runners, 1)
      assert.are.equal(all_runners[1], runner)
    end)

    it("add_runner throws on duplicates", function()
      local runner, _ = Runner:new(some_executable, { "/foo/bar" })
      local _, err = runners.add_runner(runner)
      assert.is_nil(err)
      assert.are.equal(#runners.find_runners({}), 1)
      _, err = runners.add_runner(runner)
      assert.is_not_nil(err)
      assert.are.equal(#runners.find_runners({}), 1)
    end)
  end)
end)

describe("find_runners", function()
  local runner1, runner2, runner3
  before_each(function()
    reset()
    runner1, _ = Runner:new(some_executable, { "/foo/bar", "/foo/baz" })
    assert(runner1 ~= nil)
    -- TODO same as above
    runner2, _ = Runner:new("/bin/head", { "/foo/bar", "/foo/baz/baz" })
    runner3, _ = Runner:new("/bin/tail", { "/foo/baz/quiz" })
    runners.add_runner(runner1)
    runners.add_runner(runner2)
    runners.add_runner(runner3)
  end)

  it("search by executable", function()
    local rs = runners.find_runners({ executable_path = some_executable })
    assert.are.equal(#rs, 1)
    assert.are.equal(rs[1], runner1)
  end)

  it("search by single path", function()
    local rs = runners.find_runners({ owned_paths = { "/foo/baz/baz" } })
    assert.are.equal(#rs, 2)
    -- order shouldn't matter but it is consistent with the add order
    -- don't care enough to write tests that ignore order sorry
    assert.are.equal(rs[1], runner1)
    assert.are.equal(rs[2], runner2)
  end)

  it("search by multiple paths", function()
    local rs = runners.find_runners({ owned_paths = { "/foo/bar/baz", "/foo/baz/quiz" } })
    assert.are.equal(#rs, 1)
    -- order shouldn't matter but it is consistent with the add order
    -- don't care enough to write tests that ignore order sorry
    assert.are.equal(rs[1], runner1)
  end)
end)
