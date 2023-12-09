local mock_project = require("tests.utils.mock_project")
local nio = require("nio")
local it = nio.tests.it

local executables_ui = require("neotest-gtest.executables.ui")
local ui_mock = require("tests.utils.ui_mock")
local function configure_executable()
  executables_ui.configure_executable().wait()
end

describe("test executables_ui with single root dir", function()
  ---@type neotest-gtest.MockProject
  local project
  ---@type neotest-gtest.tests.MockUi
  local ui = ui_mock.mock_ui()

  after_each(function()
    ui:reset()
  end)

  local function with_marked_items(items)
    local marked_state = {
      ["some-other-adapter:/some/path"] = { "should", "be", "ignored" },
      ["neotest-gtest:" .. project:root()] = items,
    }
    ui.marks:set_marked(marked_state)
  end

  local function setup(node2executable)
    project = mock_project:new()
    project:set_contents({
      ["test_one.cpp"] = "TEST(TestOne, F) {}",
      ["test_two.cpp"] = "TEST(TestTwo, F) {}",
    })
  end

  it("empty configure executable automatically asks for path", function()
    setup()
    with_marked_items({ "test_one.cpp::TestOne" })
    ui.input:return_value("/path/to/some/executable")

    configure_executable()

    ui.input:assert_path_requested()
    project:assert_configured("test_one.cpp::TestOne", "/path/to/some/executable")
    ui.marks:assert_marks_cleared()
  end)

  it("executable offers a choice of already configured executables", function()
    setup()
    project:set_executables({ ["test_one.cpp::TestOne"] = "/path/to/exe1" })
    ui.select:return_option("/path/to/exe1")
    with_marked_items({ "test_one.cpp::TestOne" })

    configure_executable()

    ui.select:assert_called_with_choices({ "/path/to/exe1", "Enter path..." })
    project:assert_configured("test_one.cpp::TestOne", "/path/to/exe1")
  end)

  it("Selecting Enter path... offers to input the path", function()
    setup()
    project:set_executables({ ["test_one.cpp::TestOne"] = "/path/to/exe1" })

    ui.select:return_option("Enter path...")
    ui.input:return_value("/path/to/exe2")
    with_marked_items({ "test_two.cpp::TestTwo" })

    configure_executable()

    ui.select:assert_called_with_choices({ "/path/to/exe1", "Enter path..." })
    ui.input:assert_path_requested()
    project:assert_configured("test_two.cpp::TestTwo", "/path/to/exe2")
  end)

  it("Rejecting the selection keeps the state as-is", function()
    setup()
    project:set_executables({ ["test_one.cpp::TestOne"] = "/path/to/exe1" })
    ui.select:return_option(nil)
    with_marked_items({ "test_two.cpp::TestTwo" })

    configure_executable()

    ui.select:assert_called_with_choices({ "/path/to/exe1", "Enter path..." })
    project:assert_not_configured("test_two.cpp::TestTwo")
    ui.marks:assert_marks_not_cleared()
  end)

  it("Rejecting the input keeps the state as-is", function()
    setup()
    ui.input:return_value(nil)
    with_marked_items({ "test_one.cpp::TestOne" })

    configure_executable()

    ui.input:assert_path_requested()
    project:assert_not_configured("test_one.cpp::TestOne")
    ui.marks:assert_marks_not_cleared()
  end)

  it("Rejecting the input after selection keeps the state as-is", function()
    setup()
    project:set_executables({ ["test_one.cpp::TestOne"] = "/path/to/exe1" })
    ui.select:return_option("Enter path...")
    ui.input:return_value(nil)
    with_marked_items({ "test_two.cpp::TestTwo" })

    configure_executable()

    ui.select:assert_called_with_choices({ "/path/to/exe1", "Enter path..." })
    ui.input:assert_path_requested()
    project:assert_not_configured("test_two.cpp::TestTwo")
    ui.marks:assert_marks_not_cleared()
  end)

  it("Reconfiguring nodes with the same executable fills default on input", function()
    setup()
    project:set_executables({ ["test_one.cpp"] = "/path/to/exe1" })
    ui.select:return_option("Enter path...")
    ui.input:return_value("/path/to/exe2")
    with_marked_items({ "test_one.cpp::TestOne", "test_one.cpp::TestOne::TestFoo" })

    configure_executable()

    ui.input:assert_path_requested_with_default("/path/to/exe1")
  end)

  it("Configuring nodes with deifferent executables does not fill default", function()
    setup()
    project:set_executables({
      ["test_one.cpp::TestOne"] = "/path/to/exe1",
      ["test_two.cpp::TestTwo"] = "/path/to/exe2",
    })
    ui.select:return_option("Enter path...")
    ui.input:return_value("/path/to/exe3")
    with_marked_items({ "test_one.cpp::TestOne", "test_two.cpp::TestTwo" })

    configure_executable()

    ui.input:assert_path_requested()
  end)
end)

describe("test executables_ui with single root dir", function()
  ---@type neotest-gtest.MockProject
  local project1, project2
  ---@type neotest-gtest.tests.MockUi
  local ui

  local function with_marked_items(p1_items, p2_items)
    local marked_state = {
      ["some-other-adapter:/some/path"] = { "should", "be", "ignored" },
      ["neotest-gtest:" .. project1:root()] = p1_items,
      ["neotest-gtest:" .. project2:root()] = p2_items,
    }
    ui.marks:set_marked(marked_state)
  end

  local function setup()
    ui = ui_mock.mock_ui()
    project1 = mock_project:new()
    project1:set_contents({
      ["test_one.cpp"] = "TEST(TestOne, F) {}",
      ["test_two.cpp"] = "TEST(TestTwo, F) {}",
    })

    project2 = mock_project:new()
    project2:set_contents({
      ["test_one.cpp"] = "TEST(TestOne, F) {}",
      ["test_two.cpp"] = "TEST(TestTwo, F) {}",
    })
  end

  it("multiple projects prompt configures both projects", function()
    setup()
    ui.input:return_value("/path/to/exe1")
    with_marked_items({ "test_one.cpp::TestOne" }, { "test_two.cpp::TestTwo" })

    configure_executable()

    project1:assert_configured("test_one.cpp::TestOne", "/path/to/exe1")
    project2:assert_configured("test_two.cpp::TestTwo", "/path/to/exe1")
  end)
end)
