#!/usr/bin/env ruby
# task_history.rb — Show recent run history for a task from logs
# Usage: ruby task_history.rb <task_name> [--days=7]

require 'date'

LOGGER_DIR = File.expand_path("~/.clacky/logger")

task_name = ARGV[0]
days      = (ARGV.find { |a| a.start_with?("--days=") }&.split("=")&.last || "7").to_i

unless task_name
  warn "Usage: ruby task_history.rb <task_name> [--days=7]"
  exit 1
end

unless Dir.exist?(LOGGER_DIR)
  puts "📂 Log directory not found: #{LOGGER_DIR}"
  puts "   Clacky server has never run, or logs have not been generated yet."
  exit 0
end

log_files = Dir.glob(File.join(LOGGER_DIR, "clacky-*.log")).sort.last(days)

if log_files.empty?
  puts "📊 Run History: #{task_name}"
  puts ""
  puts "   No log records found (past #{days} days)"
  exit 0
end

# Parse events: fired, completed, failed
events = []

log_files.each do |f|
  File.readlines(f).each do |line|
    next unless line.include?("task=\"#{task_name}\"")
    
    ts_match = line.match(/\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/)
    ts = ts_match ? ts_match[1] : "unknown"
    
    if line.include?("scheduler_task_fired")
      events << { ts: ts, type: :fired }
    elsif line.include?("scheduler_task_completed")
      events << { ts: ts, type: :completed }
    elsif line.include?("scheduler_task_failed")
      err_match = line.match(/error="([^"]+)"/)
      error_msg = err_match ? err_match[1] : "unknown error"
      events << { ts: ts, type: :failed, error: error_msg }
    elsif line.include?("scheduler_task_skipped")
      events << { ts: ts, type: :skipped }
    end
  end
end

puts "📊 Run History: #{task_name} (past #{days} days)"
puts ""

if events.empty?
  puts "   No run records found"
  puts ""
  puts "   Possible reasons:"
  puts "   - Task has never been triggered (cron time not yet reached)"
  puts "   - Task is disabled"
  puts "   - Clacky server is not running"
  exit 0
end

# Group fired events with their outcome
runs = []
fired_events = events.select { |e| e[:type] == :fired }

fired_events_sorted = fired_events.sort_by { |e| e[:ts] }

fired_events_sorted.each_with_index do |fired, idx|
  fired_ts = fired[:ts]

  # The window ends at the next fired event (or end of all events)
  next_fired_ts = fired_events_sorted[idx + 1]&.fetch(:ts)

  # Look for completed / failed / skipped within this window
  window_events = events.select do |e|
    e[:ts] >= fired_ts &&
      (next_fired_ts.nil? || e[:ts] < next_fired_ts) &&
      %i[completed failed skipped].include?(e[:type])
  end

  outcome = window_events.min_by { |e| e[:ts] }

  if outcome
    runs << { fired_ts: fired_ts, outcome: outcome }
  elsif next_fired_ts
    # No explicit completion marker, but a subsequent fired event exists —
    # infer success (task finished before the next run started)
    runs << { fired_ts: fired_ts, outcome: { type: :inferred_success } }
  else
    runs << { fired_ts: fired_ts, outcome: { type: :unknown } }
  end
end

# Display most recent first
runs.sort_by { |r| r[:fired_ts] }.reverse.first(20).each do |run|
  ts_display = run[:fired_ts].gsub("T", " ")
  
  case run[:outcome][:type]
  when :completed
    puts "#{ts_display}  ✅ Success"
  when :inferred_success
    puts "#{ts_display}  ✅ Success (inferred)"
  when :failed
    error_short = run[:outcome][:error].to_s[0, 80]
    puts "#{ts_display}  ❌ Failed  — #{error_short}"
  when :skipped
    puts "#{ts_display}  ⚠️  Skipped"
  when :unknown
    puts "#{ts_display}  ⏳ Unknown (may still be running or log is incomplete)"
  end
end

puts ""

# Show error detail for most recent failure
last_failure = runs
  .sort_by { |r| r[:fired_ts] }
  .reverse
  .find { |r| r[:outcome][:type] == :failed }

if last_failure
  puts "Most recent error:"
  puts "  Time:  #{last_failure[:fired_ts]}"
  puts "  Error: #{last_failure[:outcome][:error]}"
  puts ""
  puts "  Common causes:"
  puts "  - API response timeout or unexpected format"
  puts "  - Network unreachable"
  puts "  - File path referenced in task prompt does not exist"
end
