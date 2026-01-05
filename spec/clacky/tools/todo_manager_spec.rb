# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Clacky::Tools::TodoManager do
  let(:tool) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }
  let(:todo_file) { File.join(temp_dir, ".clacky_todos.json") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#execute" do
    describe "add action" do
      it "adds a new todo" do
        result = tool.execute(action: "add", task: "Write tests", work_dir: temp_dir)

        expect(result[:message]).to eq("TODO added successfully")
        expect(result[:todos].size).to eq(1)
        expect(result[:todos][0][:id]).to eq(1)
        expect(result[:todos][0][:task]).to eq("Write tests")
        expect(result[:todos][0][:status]).to eq("pending")
        expect(result[:total]).to eq(1)
      end

      it "adds multiple todos at once with tasks array" do
        result = tool.execute(
          action: "add",
          tasks: ["Task 1", "Task 2", "Task 3"],
          work_dir: temp_dir
        )

        expect(result[:message]).to eq("3 TODOs added successfully")
        expect(result[:todos].size).to eq(3)
        expect(result[:todos][0][:id]).to eq(1)
        expect(result[:todos][1][:id]).to eq(2)
        expect(result[:todos][2][:id]).to eq(3)
        expect(result[:total]).to eq(3)
      end

      it "increments todo IDs correctly when adding multiple" do
        tool.execute(action: "add", task: "First task", work_dir: temp_dir)
        result = tool.execute(
          action: "add",
          tasks: ["Second task", "Third task"],
          work_dir: temp_dir
        )

        expect(result[:todos][0][:id]).to eq(2)
        expect(result[:todos][1][:id]).to eq(3)
        expect(result[:total]).to eq(3)
      end

      it "prefers tasks array over task when both provided" do
        result = tool.execute(
          action: "add",
          task: "Single task",
          tasks: ["Batch 1", "Batch 2"],
          work_dir: temp_dir
        )

        expect(result[:todos].size).to eq(2)
        expect(result[:todos][0][:task]).to eq("Batch 1")
      end

      it "returns error when task is empty" do
        result = tool.execute(action: "add", task: "", work_dir: temp_dir)

        expect(result[:error]).to eq("At least one task description is required")
      end

      it "returns error when task is nil and tasks is empty" do
        result = tool.execute(action: "add", work_dir: temp_dir)

        expect(result[:error]).to eq("At least one task description is required")
      end

      it "filters out empty tasks from array" do
        result = tool.execute(
          action: "add",
          tasks: ["Task 1", "", "  ", "Task 2"],
          work_dir: temp_dir
        )

        expect(result[:todos].size).to eq(2)
        expect(result[:todos][0][:task]).to eq("Task 1")
        expect(result[:todos][1][:task]).to eq("Task 2")
      end
    end

    describe "list action" do
      it "returns empty list when no todos" do
        result = tool.execute(action: "list", work_dir: temp_dir)

        expect(result[:message]).to eq("No TODO items")
        expect(result[:todos]).to eq([])
        expect(result[:total]).to eq(0)
      end

      it "lists all todos" do
        tool.execute(action: "add", task: "Task 1", work_dir: temp_dir)
        tool.execute(action: "add", task: "Task 2", work_dir: temp_dir)

        result = tool.execute(action: "list", work_dir: temp_dir)

        expect(result[:message]).to eq("TODO list")
        expect(result[:todos].size).to eq(2)
        expect(result[:total]).to eq(2)
        expect(result[:pending]).to eq(2)
        expect(result[:completed]).to eq(0)
      end

      it "shows pending and completed counts" do
        tool.execute(action: "add", task: "Task 1", work_dir: temp_dir)
        tool.execute(action: "add", task: "Task 2", work_dir: temp_dir)
        tool.execute(action: "complete", id: 1, work_dir: temp_dir)

        result = tool.execute(action: "list", work_dir: temp_dir)

        expect(result[:pending]).to eq(1)
        expect(result[:completed]).to eq(1)
      end
    end

    describe "complete action" do
      it "marks a todo as completed" do
        tool.execute(action: "add", task: "Task to complete", work_dir: temp_dir)
        result = tool.execute(action: "complete", id: 1, work_dir: temp_dir)

        expect(result[:message]).to eq("Task marked as completed")
        expect(result[:todo][:status]).to eq("completed")
        expect(result[:todo][:completed_at]).not_to be_nil
      end

      it "returns message if already completed" do
        tool.execute(action: "add", task: "Task", work_dir: temp_dir)
        tool.execute(action: "complete", id: 1, work_dir: temp_dir)
        result = tool.execute(action: "complete", id: 1, work_dir: temp_dir)

        expect(result[:message]).to eq("Task already completed")
      end

      it "returns error when task not found" do
        result = tool.execute(action: "complete", id: 999, work_dir: temp_dir)

        expect(result[:error]).to eq("Task not found: 999")
      end

      it "returns error when id is nil" do
        result = tool.execute(action: "complete", work_dir: temp_dir)

        expect(result[:error]).to eq("Task ID is required")
      end
    end

    describe "remove action" do
      it "removes a todo" do
        tool.execute(action: "add", task: "Task to remove", work_dir: temp_dir)
        result = tool.execute(action: "remove", id: 1, work_dir: temp_dir)

        expect(result[:message]).to eq("Task removed")
        expect(result[:remaining]).to eq(0)
      end

      it "returns error when task not found" do
        result = tool.execute(action: "remove", id: 999, work_dir: temp_dir)

        expect(result[:error]).to eq("Task not found: 999")
      end

      it "returns error when id is nil" do
        result = tool.execute(action: "remove", work_dir: temp_dir)

        expect(result[:error]).to eq("Task ID is required")
      end
    end

    describe "clear action" do
      it "clears all todos" do
        tool.execute(action: "add", task: "Task 1", work_dir: temp_dir)
        tool.execute(action: "add", task: "Task 2", work_dir: temp_dir)

        result = tool.execute(action: "clear", work_dir: temp_dir)

        expect(result[:message]).to eq("All TODOs cleared")
        expect(result[:cleared_count]).to eq(2)
        expect(File.exist?(todo_file)).to be false
      end

      it "clears empty list" do
        result = tool.execute(action: "clear", work_dir: temp_dir)

        expect(result[:message]).to eq("All TODOs cleared")
        expect(result[:cleared_count]).to eq(0)
      end
    end

    describe "unknown action" do
      it "returns error for unknown action" do
        result = tool.execute(action: "invalid_action", work_dir: temp_dir)

        expect(result[:error]).to eq("Unknown action: invalid_action")
      end
    end
  end

  describe "#to_function_definition" do
    it "returns OpenAI function calling format" do
      definition = tool.to_function_definition

      expect(definition[:type]).to eq("function")
      expect(definition[:function][:name]).to eq("todo_manager")
      expect(definition[:function][:description]).to be_a(String)
      expect(definition[:function][:parameters]).to have_key(:properties)
      expect(definition[:function][:parameters][:required]).to include("action")
    end

    it "includes all action types in enum" do
      definition = tool.to_function_definition
      action_enum = definition[:function][:parameters][:properties][:action][:enum]

      expect(action_enum).to include("add", "list", "complete", "remove", "clear")
    end
  end
end
