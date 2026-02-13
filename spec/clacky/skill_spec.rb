# frozen_string_literal: true

require "tempfile"
require "tmpdir"

RSpec.describe Clacky::Skill do
  let(:temp_dir) { Dir.mktmpdir }
  let(:skill_content) do
    <<~CONTENT
      ---
      name: test-skill
      description: A test skill for testing purposes
      user_invocable: true
      ---

      This is the skill content.
      It should be processed by the skill.
    CONTENT
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe ".new" do
    context "with valid SKILL.md" do
      it "creates a skill instance" do
        skill_dir = File.join(temp_dir, "test-skill")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), skill_content)

        skill = described_class.new(skill_dir)

        expect(skill.identifier).to eq("test-skill")
        expect(skill.context_description).to eq("A test skill for testing purposes")
        expect(skill.user_invocable?).to be true
        expect(skill.model_invocation_allowed?).to be true
        expect(skill.fork_agent?).to be false
      end
    end

    context "with minimal frontmatter" do
      it "creates a skill with defaults" do
        skill_dir = File.join(temp_dir, "minimal-skill")
        FileUtils.mkdir_p(skill_dir)
        minimal_content = <<~CONTENT
          ---
          name: minimal-skill
          ---

          Minimal skill content.
        CONTENT
        File.write(File.join(skill_dir, "SKILL.md"), minimal_content)

        skill = described_class.new(skill_dir)

        expect(skill.identifier).to eq("minimal-skill")
        # Default: user_invocable is true by default (unless explicitly set to false)
        expect(skill.user_invocable?).to be true
        expect(skill.model_invocation_allowed?).to be true
        expect(skill.fork_agent?).to be false
      end
    end

    context "with empty content" do
      it "creates skill with empty content gracefully" do
        skill_dir = File.join(temp_dir, "empty-skill")
        FileUtils.mkdir_p(skill_dir)
        empty_content = <<~CONTENT
          ---
          name: empty-skill
          ---
        CONTENT
        File.write(File.join(skill_dir, "SKILL.md"), empty_content)

        skill = described_class.new(skill_dir)
        expect(skill.identifier).to eq("empty-skill")
        expect(skill.content).to eq("")
      end
    end

    # Note: Ruby's YAML library is very permissive, so truly invalid YAML
    # is rare. Most malformed YAML still parses successfully.
  end

  describe "#slash_command" do
    it "returns the slash command format" do
      skill_dir = File.join(temp_dir, "my-skill")
      FileUtils.mkdir_p(skill_dir)
      # Use different name to test that slash_command uses name from frontmatter
      File.write(File.join(skill_dir, "SKILL.md"), <<~CONTENT)
        ---
        name: my-skill
        description: Skill with custom name
        ---
        Content here.
      CONTENT

      skill = described_class.new(skill_dir)

      expect(skill.slash_command).to eq("/my-skill")
    end
  end

  describe "#content" do
    it "returns the content after frontmatter" do
      skill_dir = File.join(temp_dir, "content-skill")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), skill_content)

      skill = described_class.new(skill_dir)

      expect(skill.content).to include("This is the skill content.")
      expect(skill.content).not_to include("name:")
      expect(skill.content).not_to include("description:")
    end
  end

  describe "#process_content" do
    it "replaces $ARGUMENTS placeholder with arguments" do
      skill_dir = File.join(temp_dir, "arg-skill")
      FileUtils.mkdir_p(skill_dir)
      arg_content = <<~CONTENT
        ---
        name: arg-skill
        description: Skill with arguments
        ---
        Please process: $ARGUMENTS
        End of skill.
      CONTENT
      File.write(File.join(skill_dir, "SKILL.md"), arg_content)

      skill = described_class.new(skill_dir)
      result = skill.process_content("hello world")

      expect(result).to include("Please process: hello world")
      expect(result).to include("End of skill.")
    end

    it "replaces $N shorthand with individual arguments" do
      skill_dir = File.join(temp_dir, "n-skill")
      FileUtils.mkdir_p(skill_dir)
      n_content = <<~CONTENT
        ---
        name: n-skill
        description: Skill with $N placeholders
        ---
        First: $0, Second: $1
      CONTENT
      File.write(File.join(skill_dir, "SKILL.md"), n_content)

      skill = described_class.new(skill_dir)
      result = skill.process_content("one two three")

      expect(result).to include("First: one, Second: two")
    end

    it "handles no arguments gracefully" do
      skill_dir = File.join(temp_dir, "noarg-skill")
      FileUtils.mkdir_p(skill_dir)
      noarg_content = <<~CONTENT
        ---
        name: noarg-skill
        description: Skill without args
        ---
        No arguments here: $0
      CONTENT
      File.write(File.join(skill_dir, "SKILL.md"), noarg_content)

      skill = described_class.new(skill_dir)
      result = skill.process_content("")

      expect(result).to include("No arguments here: ")
    end
  end

  describe "#allowed_tools" do
    it "returns allowed tools list" do
      skill_dir = File.join(temp_dir, "tools-skill")
      FileUtils.mkdir_p(skill_dir)
      tools_content = <<~CONTENT
        ---
        name: tools-skill
        description: Skill with allowed tools
        allowed-tools:
          - file_reader
          - grep
        ---
        Content here.
      CONTENT
      File.write(File.join(skill_dir, "SKILL.md"), tools_content)

      skill = described_class.new(skill_dir)

      expect(skill.allowed_tools).to eq(["file_reader", "grep"])
    end
  end

  describe "#directory" do
    it "returns the skill directory path" do
      skill_dir = File.join(temp_dir, "dir-skill")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), skill_content)

      skill = described_class.new(skill_dir)

      expect(skill.directory).to eq(Pathname.new(skill_dir))
    end
  end

  describe "#source_path" do
    it "returns the source path for the skill" do
      skill_dir = File.join(temp_dir, "source-skill")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), <<~CONTENT)
        ---
        name: source-skill
        description: Skill with source path
        ---
        Content here.
      CONTENT

      skill = described_class.new(skill_dir, source_path: "/some/project")

      expect(skill.source_path).to be_a(Pathname)
      expect(skill.source_path.to_s).to eq("/some/project")
    end
  end

  describe "subagent configuration" do
    context "with fork_agent enabled" do
      it "parses fork_agent configuration" do
        skill_dir = File.join(temp_dir, "subagent-skill")
        FileUtils.mkdir_p(skill_dir)
        subagent_content = <<~CONTENT
          ---
          name: subagent-skill
          description: A skill that forks a subagent
          fork_agent: true
          model: claude-haiku-3-5
          forbidden_tools:
            - write
            - edit
            - safe_shell
          auto_summarize: true
          ---

          You are a code explorer subagent.
        CONTENT
        File.write(File.join(skill_dir, "SKILL.md"), subagent_content)

        skill = described_class.new(skill_dir)

        expect(skill.fork_agent?).to be true
        expect(skill.subagent_model).to eq("claude-haiku-3-5")
        expect(skill.forbidden_tools_list).to contain_exactly("write", "edit", "safe_shell")
        expect(skill.auto_summarize?).to be true
      end
    end

    context "without fork_agent" do
      it "returns defaults" do
        skill_dir = File.join(temp_dir, "normal-skill")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), skill_content)

        skill = described_class.new(skill_dir)

        expect(skill.fork_agent?).to be false
        expect(skill.subagent_model).to be_nil
        expect(skill.forbidden_tools_list).to eq([])
        expect(skill.auto_summarize?).to be true  # Default is true
      end
    end

    context "with auto_summarize disabled" do
      it "returns false for auto_summarize?" do
        skill_dir = File.join(temp_dir, "no-summary-skill")
        FileUtils.mkdir_p(skill_dir)
        no_summary_content = <<~CONTENT
          ---
          name: no-summary
          fork_agent: true
          auto_summarize: false
          ---

          Content
        CONTENT
        File.write(File.join(skill_dir, "SKILL.md"), no_summary_content)

        skill = described_class.new(skill_dir)

        expect(skill.auto_summarize?).to be false
      end
    end
  end
end
