# frozen_string_literal: true

require_relative "base"

module Clacky
  module Tools
    class Shell < Base
      self.tool_name = "shell"
      self.tool_description = "Execute shell commands in the terminal"
      self.tool_category = "system"
      self.tool_parameters = {
        type: "object",
        properties: {
          command: {
            type: "string",
            description: "Shell command to execute"
          },
          soft_timeout: {
            type: "integer",
            description: "Soft timeout in seconds (for interaction detection)"
          },
          hard_timeout: {
            type: "integer",
            description: "Hard timeout in seconds (force kill)"
          }
        },
        required: ["command"]
      }

      INTERACTION_PATTERNS = [
        [/\[Y\/n\]|\[y\/N\]|\(yes\/no\)|\(Y\/n\)|\(y\/N\)/i, 'confirmation'],
        [/[Pp]assword\s*:\s*$|Enter password|enter password/, 'password'],
        [/^\s*>>>\s*$|^\s*>>?\s*$|^irb\(.*\):\d+:\d+[>*]\s*$|^>\s*$/, 'repl'],
        [/^\s*:\s*$|\(END\)|--More--|Press .* to continue|lines \d+-\d+/, 'pager'],
        [/Are you sure|Continue\?|Proceed\?|Confirm|Overwrite/i, 'question'],
        [/Enter\s+\w+:|Input\s+\w+:|Please enter|please provide/i, 'input'],
        [/Select an option|Choose|Which one|select one/i, 'selection']
      ].freeze

      SLOW_COMMANDS = [
        'bundle install',
        'npm install',
        'yarn install',
        'pnpm install',
        'rspec',
        'rake test',
        'npm run build',
        'npm run test',
        'yarn build',
        'cargo build',
        'go build'
      ].freeze

      def execute(command:, soft_timeout: nil, hard_timeout: nil)
        require "open3"
        require "stringio"

        soft_timeout, hard_timeout = determine_timeouts(command, soft_timeout, hard_timeout)

        stdout_buffer = StringIO.new
        stderr_buffer = StringIO.new
        soft_timeout_triggered = false

        begin
          Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
            start_time = Time.now

            stdout.sync = true
            stderr.sync = true

            loop do
              elapsed = Time.now - start_time

              if elapsed > hard_timeout
                Process.kill('TERM', wait_thr.pid) rescue nil
                sleep 0.5
                Process.kill('KILL', wait_thr.pid) if wait_thr.alive? rescue nil

                return format_timeout_result(
                  command,
                  stdout_buffer.string,
                  stderr_buffer.string,
                  elapsed,
                  :hard_timeout,
                  hard_timeout
                )
              end

              if elapsed > soft_timeout && !soft_timeout_triggered
                soft_timeout_triggered = true

                # L1:
                interaction = detect_interaction(stdout_buffer.string)
                if interaction
                  Process.kill('TERM', wait_thr.pid) rescue nil
                  return format_waiting_input_result(
                    command,
                    stdout_buffer.string,
                    stderr_buffer.string,
                    interaction
                  )
                end

                # L2:
                last_size = stdout_buffer.size
                stdin.puts("\n") rescue nil
                sleep 2

                if stdout_buffer.size > last_size
                  next
                else
                  Process.kill('TERM', wait_thr.pid) rescue nil
                  return format_stuck_result(
                    command,
                    stdout_buffer.string,
                    stderr_buffer.string,
                    elapsed
                  )
                end
              end

              break unless wait_thr.alive?

              begin
                ready = IO.select([stdout, stderr], nil, nil, 0.1)
                if ready
                  ready[0].each do |io|
                    begin
                      data = io.read_nonblock(4096)
                      if io == stdout
                        stdout_buffer.write(data)
                      else
                        stderr_buffer.write(data)
                      end
                    rescue IO::WaitReadable, EOFError
                    end
                  end
                end
              rescue StandardError => e
              end

              sleep 0.1
            end

            begin
              stdout_buffer.write(stdout.read)
            rescue StandardError
            end
            begin
              stderr_buffer.write(stderr.read)
            rescue StandardError
            end

            {
              command: command,
              stdout: stdout_buffer.string,
              stderr: stderr_buffer.string,
              exit_code: wait_thr.value.exitstatus,
              success: wait_thr.value.success?,
              elapsed: Time.now - start_time
            }
          end
        rescue StandardError => e
          {
            command: command,
            stdout: stdout_buffer.string,
            stderr: "Error executing command: #{e.message}\n#{e.backtrace.first(3).join("\n")}",
            exit_code: -1,
            success: false
          }
        end
      end

      private

      def determine_timeouts(command, soft_timeout, hard_timeout)
        # 检查是否是慢命令
        is_slow = SLOW_COMMANDS.any? { |slow_cmd| command.include?(slow_cmd) }

        if is_slow
          soft_timeout ||= 30
          hard_timeout ||= 180 # 3分钟
        else
          soft_timeout ||= 7
          hard_timeout ||= 60
        end

        [soft_timeout, hard_timeout]
      end

      # L1: 规则检测
      def detect_interaction(output)
        return nil if output.empty?

        lines = output.split("\n").last(10)

        lines.reverse.each do |line|
          line_stripped = line.strip
          next if line_stripped.empty?

          INTERACTION_PATTERNS.each do |pattern, type|
            if line.match?(pattern)
              return { type: type, line: line_stripped }
            end
          end
        end

        nil
      end

      def format_waiting_input_result(command, stdout, stderr, interaction)
        {
          command: command,
          stdout: stdout,
          stderr: stderr,
          exit_code: -2,
          success: false,
          state: 'WAITING_INPUT',
          interaction_type: interaction[:type],
          message: format_waiting_message(stdout, interaction)
        }
      end

      def format_waiting_message(output, interaction)
        <<~MSG
          #{output}

          #{'=' * 60}
          [Terminal State: WAITING_INPUT]
          #{'=' * 60}

          The terminal is waiting for your input.

          Detected pattern: #{interaction[:type]}
          Last line: #{interaction[:line]}

          Suggested actions:
          • Provide answer: run shell with your response
          • Cancel: send Ctrl+C (\\x03)
        MSG
      end

      def format_stuck_result(command, stdout, stderr, elapsed)
        {
          command: command,
          stdout: stdout,
          stderr: stderr,
          exit_code: -3,
          success: false,
          state: 'STUCK',
          elapsed: elapsed,
          message: format_stuck_message(stdout, elapsed)
        }
      end

      def format_stuck_message(output, elapsed)
        <<~MSG
          #{output}

          #{'=' * 60}
          [Terminal State: STUCK]
          #{'=' * 60}

          The terminal is not responding after #{elapsed.round(1)}s.

          Suggested actions:
          • Try interrupting with Ctrl+C
          • Check if command is frozen
        MSG
      end

      def format_timeout_result(command, stdout, stderr, elapsed, type, timeout)
        {
          command: command,
          stdout: stdout,
          stderr: stderr.empty? ? "Command timed out after #{elapsed.round(1)} seconds (#{type}=#{timeout}s)" : stderr,
          exit_code: -1,
          success: false,
          state: 'TIMEOUT',
          timeout_type: type
        }
      end

      def format_call(args)
        cmd = args[:command] || args['command'] || ''
        cmd_parts = cmd.split
        cmd_short = cmd_parts.first(3).join(' ')
        cmd_short += '...' if cmd_parts.size > 3
        "Shell(#{cmd_short})"
      end

      def format_result(result)
        exit_code = result[:exit_code] || result['exit_code'] || 0
        stdout = result[:stdout] || result['stdout'] || ""
        stderr = result[:stderr] || result['stderr'] || ""

        if exit_code == 0
          lines = stdout.lines.size
          "✓ Completed#{lines > 0 ? " (#{lines} lines)" : ''}"
        else
          error_msg = stderr.lines.first&.strip || "Failed"
          "✗ Exit #{exit_code}: #{error_msg[0..50]}"
        end
      end
    end
  end
end
