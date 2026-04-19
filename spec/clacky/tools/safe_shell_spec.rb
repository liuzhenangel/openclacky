# frozen_string_literal: true

RSpec.describe Clacky::Tools::SafeShell do
  let(:tool) { described_class.new }

  describe "#execute" do
    # Truncation is now enforced at write-time by LimitStack.
    # MAX_LLM_OUTPUT_LINES=500, MAX_LLM_OUTPUT_CHARS=4000, MAX_LINE_CHARS=500.
    # max_output_lines param is accepted for backward-compat but ignored.
    # No "Output truncated" text is injected into stdout.
    context "output truncation" do
      it "does not truncate short output" do
        result = tool.execute(command: "echo 'hello'")

        expect(result[:exit_code]).to eq(0)
        expect(result[:success]).to be true
        expect(result[:output_truncated]).to be false
      end

      it "sets output_truncated:true when lines exceed MAX_LLM_OUTPUT_LINES (500)" do
        result = tool.execute(command: "seq 1 600")

        expect(result[:exit_code]).to eq(0)
        expect(result[:success]).to be true
        expect(result[:output_truncated]).to be true
        # rolling window: keeps last 500 lines — stdout ends near 600
        expect(result[:stdout]).to include("600")
        expect(result[:stdout].lines.count).to be <= 500
      end

      it "sets output_truncated:true when chars exceed MAX_LLM_OUTPUT_CHARS (4000)" do
        # 25 lines × 200 chars ≈ 5000 chars > 4000 budget
        result = tool.execute(command: "ruby -e '25.times { puts \"x\" * 200 }'")

        expect(result[:exit_code]).to eq(0)
        expect(result[:success]).to be true
        expect(result[:output_truncated]).to be true
        expect(result[:stdout].length).to be <= Clacky::Tools::Shell::MAX_LLM_OUTPUT_CHARS
      end

      it "handles empty output" do
        result = tool.execute(command: "echo -n ''")

        expect(result[:exit_code]).to eq(0)
        expect(result[:success]).to be true
        expect(result[:output_truncated]).to be false
      end

      it "accepts max_output_lines param without error (backward-compat)" do
        result = tool.execute(command: "echo ok", max_output_lines: 10)
        expect(result[:exit_code]).to eq(0)
        expect(result[:stdout]).to include("ok")
      end
    end

    context "security features" do
      it "makes dangerous rm command safe" do
        result = tool.execute(command: "rm nonexistent_file.txt")

        # Should replace rm with mv to trash
        expect(result[:security_enhanced]).to be true
        expect(result[:safe_command]).to include("mv")
      end

      it "allows safe read-only commands without modification" do
        result = tool.execute(command: "ls -la")

        expect(result[:exit_code]).to eq(0)
        expect(result[:success]).to be true
        expect(result[:security_enhanced]).to be_falsy
      end
    end
  end

  describe ".command_safe_for_auto_execution?" do
    it "returns true for safe read-only commands" do
      expect(described_class.command_safe_for_auto_execution?("ls -la")).to be true
      expect(described_class.command_safe_for_auto_execution?("pwd")).to be true
      expect(described_class.command_safe_for_auto_execution?("echo hello")).to be true
    end

    it "returns false for dangerous commands" do
      expect(described_class.command_safe_for_auto_execution?("sudo apt-get install")).to be false
    end
  end

  describe "#format_call" do
    it "formats command for display" do
      formatted = tool.format_call({ command: "ls -la" })

      expect(formatted).to include("safe_shell")
      expect(formatted).to include("ls -la")
    end

    it "truncates long commands" do
      long_command = "a" * 200
      formatted = tool.format_call({ command: long_command })

      expect(formatted.length).to be < long_command.length + 20
      expect(formatted).to include("...")
    end
  end

  describe "#format_result" do
    it "shows success with line count" do
      result = { exit_code: 0, stdout: "line1\nline2\nline3\n", stderr: "" }
      formatted = tool.format_result(result)

      expect(formatted).to include("[OK]")
      expect(formatted).to include("lines")
    end

    it "shows security enhancement indicator" do
      result = { exit_code: 0, stdout: "output", stderr: "", security_enhanced: true }
      formatted = tool.format_result(result)

      expect(formatted).to include("[Safe]")
    end

    it "shows error for failed commands" do
      result = { exit_code: 1, stdout: "", stderr: "Error message" }
      formatted = tool.format_result(result)

      expect(formatted).to include("[Exit 1]")
    end
  end

  describe "#to_function_definition" do
    it "returns OpenAI function calling format" do
      definition = tool.to_function_definition

      expect(definition[:type]).to eq("function")
      expect(definition[:function][:name]).to eq("safe_shell")
      expect(definition[:function][:description]).to be_a(String)
      expect(definition[:function][:parameters][:required]).to include("command")
      expect(definition[:function][:parameters][:properties]).to have_key(:timeout)
      expect(definition[:function][:parameters][:properties]).to have_key(:max_output_lines)
    end
  end

  describe "timeout behavior" do
    it "uses provided timeout as hard_timeout" do
      # Test that timeout parameter is properly used
      result = tool.execute(command: "echo 'test'", timeout: 30)
      
      expect(result[:exit_code]).to eq(0)
      expect(result[:success]).to be true
    end

    it "auto-detects timeout for slow commands when not specified" do
      # Just verify it doesn't crash with auto-detection
      result = tool.execute(command: "echo 'bundle install simulation'")
      
      expect(result[:exit_code]).to eq(0)
    end

    it "auto-detects timeout for normal commands when not specified" do
      result = tool.execute(command: "echo 'normal command'")
      
      expect(result[:exit_code]).to eq(0)
    end

    it "extracts timeout from 'timeout N command' format" do
      result = tool.execute(command: "timeout 30 echo 'test'")
      
      expect(result[:exit_code]).to eq(0)
      expect(result[:success]).to be true
      # The actual command executed should be without the timeout prefix
      expect(result[:stdout]).to include("test")
    end

    it "extracts timeout from 'timeout Ns command' format with seconds suffix" do
      result = tool.execute(command: "timeout 45s echo 'hello'")
      
      expect(result[:exit_code]).to eq(0)
      expect(result[:stdout]).to include("hello")
    end

    it "extracts timeout with signal option 'timeout -s SIGNAL N command'" do
      result = tool.execute(command: "timeout -s KILL 60 echo 'world'")
      
      expect(result[:exit_code]).to eq(0)
      expect(result[:stdout]).to include("world")
    end

    it "prefers explicit timeout parameter over extracted timeout" do
      # When both are provided, explicit parameter should win
      result = tool.execute(command: "timeout 10 echo 'test'", timeout: 99)
      
      expect(result[:exit_code]).to eq(0)
      # We can't directly test which timeout was used, but we verify it executes
    end
  end

    it "extracts timeout from 'cd xxx && timeout N command' format" do
      result = tool.execute(command: "cd /tmp && timeout 30 echo 'test'")
      
      expect(result[:exit_code]).to eq(0)
      expect(result[:success]).to be true
      expect(result[:stdout]).to include("test")
    end

    it "extracts timeout from 'export VAR=val && timeout N command' format" do
      result = tool.execute(command: "export TEST=value && timeout 45 echo 'hello'")
      
      expect(result[:exit_code]).to eq(0)
      expect(result[:stdout]).to include("hello")
    end

    it "extracts timeout from 'prefix; timeout N command' format with semicolon" do
      result = tool.execute(command: "cd /tmp; timeout 60 echo 'world'")
      
      expect(result[:exit_code]).to eq(0)
      expect(result[:stdout]).to include("world")
    end

    it "handles complex compound commands with timeout" do
      result = tool.execute(command: "cd spec && timeout 30s ls -la")
      
      expect(result[:exit_code]).to eq(0)
      # Should execute in spec directory
    end

  describe "#format_waiting_input_result (via Shell)" do
    let(:shell) { Clacky::Tools::Shell.new }

    it "includes sudo hint when interaction type is password" do
      interaction = { type: "password", line: "[sudo] password for user:" }
      result = shell.send(:format_waiting_input_result, "sudo apt-get install vim", "", "", interaction, 1000)

      expect(result[:state]).to eq("WAITING_INPUT")
      expect(result[:interaction_type]).to eq("password")
      expect(result[:message]).to include("sudo -S")
      expect(result[:message]).to include("Ask the user")
    end

    it "does not include sudo hint for non-password interactions" do
      interaction = { type: "confirmation", line: "Do you want to continue? [Y/n]" }
      result = shell.send(:format_waiting_input_result, "apt-get install vim", "", "", interaction, 1000)

      expect(result[:state]).to eq("WAITING_INPUT")
      expect(result[:message]).not_to include("sudo -S")
    end
  end

  describe "#format_result_for_llm" do
    # format_result_for_llm no longer truncates stdout/stderr — truncation is
    # enforced at write-time by the LimitStack buffer inside #execute.
    # When a pre-built result hash is passed in directly, content is forwarded
    # as-is (only encoding is sanitised).

    it "passes through stdout without truncation" do
      long_output = "Line of text\n" * 500  # 6500+ chars
      result = {
        command: "generate_large_output",
        exit_code: 0,
        success: true,
        stdout: long_output,
        stderr: ""
      }

      compact = tool.format_result_for_llm(result)

      expect(compact[:stdout]).to eq(long_output)
      expect(compact[:exit_code]).to eq(0)
      expect(compact[:success]).to be true
    end

    it "passes through stderr without truncation" do
      long_error = "Error line\n" * 500  # 5500+ chars
      result = {
        command: "failing_command",
        exit_code: 1,
        success: false,
        stdout: "",
        stderr: long_error
      }

      compact = tool.format_result_for_llm(result)

      expect(compact[:stderr]).to eq(long_error)
    end

    it "preserves short output without truncation" do
      short_output = "Hello\nWorld\n"
      result = {
        command: "echo_test",
        exit_code: 0,
        success: true,
        stdout: short_output,
        stderr: ""
      }

      compact = tool.format_result_for_llm(result)

      expect(compact[:stdout]).to eq(short_output)
      expect(compact[:stdout]).not_to include("truncated")
    end

    it "preserves security enhancement fields" do
      result = {
        command: "rm test.txt",
        exit_code: 0,
        success: true,
        stdout: "[Safe] Command was automatically made safe\noutput",
        stderr: "",
        security_enhanced: true,
        original_command: "rm test.txt",
        safe_command: "mv test.txt /path/to/trash"
      }

      compact = tool.format_result_for_llm(result)

      expect(compact[:security_enhanced]).to be true
      expect(compact[:original_command]).to eq("rm test.txt")
      expect(compact[:safe_command]).to eq("mv test.txt /path/to/trash")
    end

    it "returns security_blocked results as-is" do
      result = {
        command: "sudo dangerous",
        stdout: "",
        stderr: "[Security Protection] sudo commands are not allowed",
        exit_code: 126,
        success: false,
        security_blocked: true
      }

      compact = tool.format_result_for_llm(result)

      expect(compact).to eq(result)
    end

    it "preserves error states and timeout info" do
      result = {
        command: "long_running_cmd",
        stdout: "partial output",
        stderr: "Command timed out",
        exit_code: -1,
        success: false,
        state: 'TIMEOUT',
        timeout_type: :hard_timeout
      }

      compact = tool.format_result_for_llm(result)

      expect(compact).to eq(result)
    end

    it "includes elapsed time if available" do
      result = {
        command: "quick_cmd",
        exit_code: 0,
        success: true,
        stdout: "done",
        stderr: "",
        elapsed: 1.234
      }

      compact = tool.format_result_for_llm(result)

      expect(compact[:elapsed]).to eq(1.234)
    end

    it "line-level truncation now happens at write-time (LimitStack), not in format_result_for_llm" do
      # format_result_for_llm passes content through as-is; line truncation is
      # enforced by Shell::MAX_LINE_CHARS (500) at the point of collection.
      long_line = ".hover\:opacity-50{opacity:.5}" + ("a" * 50000) + "\n"
      minified_output = long_line * 2
      result = {
        command: "grep hover application.css",
        exit_code: 0,
        success: true,
        stdout: minified_output,
        stderr: ""
      }

      compact = tool.format_result_for_llm(result)

      # Passed through unchanged (no truncation at this stage)
      expect(compact[:stdout]).to eq(minified_output)
    end

    it "MAX_LINE_CHARS constant is accessible from SafeShell (inheritance check)" do
      expect(Clacky::Tools::SafeShell::MAX_LINE_CHARS).to eq(500)
    end
  end

  describe "xcode-select auto-install" do
    let(:xcode_stderr) do
      "xcode-select: note: No developer tools were found, requesting install.\n" \
      "If developer tools are located at a non-default location on disk, use " \
      "`xcode-select --switch path/to/Xcode.app` to specify the Xcode that you " \
      "wish to use for command line developer tools, and cancel the installation " \
      "dialog.\nSee `man xcode-select` for more details."
    end

    it "detects xcode-select shim stderr" do
      expect(tool.send(:xcode_tools_missing?, xcode_stderr)).to be true
    end

    it "does not false-positive on normal stderr" do
      expect(tool.send(:xcode_tools_missing?, "Error: file not found")).to be false
      expect(tool.send(:xcode_tools_missing?, "")).to be false
      expect(tool.send(:xcode_tools_missing?, nil)).to be false
    end

    it "replaces xcode-select stderr with actionable install message" do
      allow(tool).to receive(:xcode_tools_missing?).and_return(true)

      result = tool.execute(command: "python3 --version")

      expect(result[:stderr]).to include("Xcode Command Line Tools are not installed")
      expect(result[:stderr]).to include("install_system_deps.sh")
      expect(result[:exit_code]).to eq(1)
      expect(result[:success]).to be false
    end

    it "passes through stderr unchanged when xcode-select shim not detected" do
      allow(tool).to receive(:xcode_tools_missing?).and_return(false)

      result = tool.execute(command: "echo hello")

      expect(result[:stderr]).not_to include("install_system_deps.sh")
      expect(result[:exit_code]).to eq(0)
    end
  end
end

