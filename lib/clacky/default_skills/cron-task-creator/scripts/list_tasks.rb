#!/usr/bin/env ruby
# list_tasks.rb — List all tasks with schedule and recent log status
# Usage: ruby list_tasks.rb

require 'yaml'
require 'date'

TASKS_DIR      = File.expand_path("~/.clacky/tasks")
SCHEDULES_FILE = File.expand_path("~/.clacky/schedules.yml")
LOGGER_DIR     = File.expand_path("~/.clacky/logger")

def load_schedules
  return [] unless File.exist?(SCHEDULES_FILE)
  data = YAML.load_file(SCHEDULES_FILE)
  Array(data)
rescue
  []
end

def list_task_files
  return [] unless Dir.exist?(TASKS_DIR)
  Dir.glob(File.join(TASKS_DIR, "*.md")).map { |p| File.basename(p, ".md") }.sort
end

def task_preview(name)
  path = File.join(TASKS_DIR, "#{name}.md")
  return "(empty)" unless File.exist?(path)
  lines = File.readlines(path).map(&:strip).reject(&:empty?)
  preview = lines.first || "(empty)"
  preview.length > 80 ? preview[0, 80] + "…" : preview
end

def recent_run_status(task_name)
  return { status: :unknown, detail: "no logs" } unless Dir.exist?(LOGGER_DIR)

  log_files = Dir.glob(File.join(LOGGER_DIR, "clacky-*.log"))
    .sort
    .last(7)  # check last 7 days

  last_fired = nil
  last_error = nil
  last_completed = nil

  log_files.each do |f|
    File.readlines(f).each do |line|
      next unless line.include?("task=\"#{task_name}\"")
      ts_match = line.match(/\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/)
      ts = ts_match ? ts_match[1] : nil

      if line.include?("scheduler_task_fired")
        last_fired = ts
      elsif line.include?("scheduler_task_failed")
        err_match = line.match(/error="([^"]+)"/)
        last_error = { ts: ts, msg: err_match ? err_match[1][0, 60] : "unknown error" }
      elsif line.include?("scheduler_task_completed")
        last_completed = ts
      end
    end
  end

  if last_error && (!last_completed || last_error[:ts] >= last_completed)
    { status: :failed, detail: "#{last_error[:ts]} ❌ #{last_error[:msg]}" }
  elsif last_completed
    { status: :success, detail: "#{last_completed} ✅ success" }
  elsif last_fired
    { status: :running, detail: "#{last_fired} ⏳ running or failed" }
  else
    { status: :never, detail: "从未运行" }
  end
end

# ── Main ──────────────────────────────────────────────────────────────────────

schedules = load_schedules
task_names = list_task_files

if task_names.empty?
  puts "📋 No tasks found."
  puts ""
  puts "Create your first scheduled task, e.g.:"
  puts "  \"Create a task that sends a weather report every morning at 9am\""
  puts "  \"Auto-generate a weekly work summary every Monday\""
  exit 0
end

puts "📋 Your Scheduled Tasks (#{task_names.size} total)"
puts ""

task_names.each_with_index do |name, i|
  # Find matching schedules
  task_schedules = schedules.select { |s| s["task"] == name }
  
  if task_schedules.any?
    sched = task_schedules.first
    enabled = sched["enabled"] != false
    cron_str = sched["cron"]
    status_icon = enabled ? "✅" : "❌"
    sched_label = "⏰ #{cron_str}  #{status_icon} #{enabled ? "enabled" : "disabled"}"
  else
    sched_label = "📌 Manual task (no schedule)"
  end

  run_info = recent_run_status(name)
  run_label = case run_info[:status]
              when :success then "Last run: #{run_info[:detail]}"
              when :failed  then "Last run: #{run_info[:detail]}"
              when :running then "#{run_info[:detail]}"
              when :never   then "Never run"
              else "No record"
              end

  preview = task_preview(name)

  puts "#{i + 1}. #{name}"
  puts "   #{sched_label}"
  puts "   └─ #{run_label}"
  puts "   └─ #{preview}"
  puts ""
end

puts "💡 Tip: Open the Clacky WebUI → Tasks panel to view and manage all tasks. Click ▶ Run to execute immediately."
