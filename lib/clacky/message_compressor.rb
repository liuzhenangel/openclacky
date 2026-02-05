# frozen_string_literal: true

module Clacky
  # Message compressor using LLM-based compression
  #
  # Strategy: Uses LLM to intelligently compress conversation history while preserving
  # critical information like technical decisions, code changes, error messages, and
  # pending tasks. The compression prompt instructs the LLM to return a JSON array
  # of compressed messages.
  #
  # Usage:
  #   compressor = MessageCompressor.new(client, model: "claude-3-5-sonnet")
  #   compressed = compressor.compress(messages)
  #   # => Array of compressed messages (system message + compressed conversation)
  #
  # The compress method:
  # 1. Preserves the system message
  # 2. Formats all other messages as readable text
  # 3. Sends to LLM with compression instructions
  # 4. Parses the JSON response back into message objects
  # 5. Returns [system_message, *compressed_messages]
  #
  class MessageCompressor
    COMPRESSION_PROMPT = <<~PROMPT.freeze
      You are a message compression assistant. Your task is to compress the conversation history below.

      CRITICAL RULES:
      1. Preserve all key technical decisions and code changes
      2. Keep all error messages and their solutions
      3. Retain current work status and pending tasks
      4. Maintain all file paths and important code snippets (max 200 chars each)
      5. Return format: Pure JSON array of message objects

      COMPRESSION GUIDELINES:
      - Summarize user messages while keeping their intent clear
      - Preserve assistant messages that contain important logic or decisions
      - Keep tool calls and their essential results
      - Remove repetitive or redundant content
      - Keep conversation flow understandable

      Return ONLY a valid JSON array. No markdown, no explanation.
    PROMPT

    def initialize(client, model: nil)
      @client = client
      @model = model
    end

    # Compress messages using Insert-then-Compress strategy with LLM
    # @param messages [Array<Hash>] Original conversation messages
    # @return [Array<Hash>] Compressed messages
    def compress(messages)
      # Use LLM-based compression
      llm_compress_messages(messages)
    end

    private

    # Main LLM compression method
    def llm_compress_messages(messages)
      # Find and preserve system message
      system_msg = messages.find { |m| m[:role] == "system" }
      
      # Get messages to compress (exclude system message)
      messages_to_compress = messages.reject { |m| m[:role] == "system" }
      
      return [system_msg].compact if messages_to_compress.empty?
      
      # Build compression prompt with instruction and conversation
      content = build_compression_content(messages_to_compress)
      full_prompt = "#{COMPRESSION_PROMPT}\n\nConversation to compress:\n\n#{content}"
      
      # Prepare messages array for LLM call
      llm_messages = [{ role: "user", content: full_prompt }]
      
      # Call LLM to compress
      response = @client.send_messages(
        llm_messages,
        model: @model,
        max_tokens: 8192
      )
      
      # Parse the compressed result
      compressed_content = response[:content]
      parsed_messages = parse_compressed_result(compressed_content)
      
      # If parsing fails or returns empty, raise error
      if parsed_messages.nil? || parsed_messages.empty?
        raise "LLM compression failed: unable to parse compressed messages"
      end
      
      # Return system message + compressed messages
      [system_msg, *parsed_messages].compact
    end

    def build_compression_content(messages)
      # Format messages as readable text for compression
      messages.map do |msg|
        role = msg[:role]
        content = format_content(msg[:content])
        "[#{role.upcase}] #{content}"
      end.join("\n\n")
    end

    def format_content(content)
      return content if content.is_a?(String)

      if content.is_a?(Array)
        content.map do |block|
          case block[:type]
          when "text"
            block[:text]
          when "tool_use"
            "TOOL: #{block[:name]}(#{block[:input]})"
          when "tool_result"
            "RESULT: #{block[:content]}"
          else
            block.to_s
          end
        end.join("\n")
      else
        content.to_s
      end
    end

    def parse_compressed_result(result)
      # Try to extract JSON from result
      json_content = extract_json(result)

      if json_content
        JSON.parse(json_content, symbolize_names: true)
      else
        # Return empty if parsing fails
        []
      end
    end

    def extract_json(content)
      # Try to find JSON array in the response
      # Handle cases where LLM might add markdown formatting
      content = content.strip

      # Remove markdown code block if present
      content = content.sub(/^```json\s*/, '').sub(/\s*```$/, '')
      content = content.sub(/^```\s*/, '').sub(/\s*```$/, '')

      # Try to find array pattern
      if content.include?('[') && content.include?(']')
        # Find the first [ and last ]
        first_bracket = content.index('[')
        last_bracket = content.rindex(']')
        if first_bracket && last_bracket && last_bracket > first_bracket
          return content[first_bracket..last_bracket]
        end
      end

      # Return as-is if it looks like JSON
      content if content.start_with?('[') && content.end_with?(']')
    end
  end
end
