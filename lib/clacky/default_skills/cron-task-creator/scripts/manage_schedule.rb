#!/usr/bin/env ruby
# manage_schedule.rb — Add, update, toggle, delete schedule entries in schedules.yml
# Usage:
#   ruby manage_schedule.rb add    <schedule_name> <task_name> <cron_expr>
#   ruby manage_schedule.rb update <schedule_name> <new_cron>
#   ruby manage_schedule.rb toggle <schedule_name> true|false
#   ruby manage_schedule.rb delete <schedule_name>
#   ruby manage_schedule.rb list

require 'yaml'
require 'fileutils'

SCHEDULES_FILE = File.expand_path("~/.clacky/schedules.yml")

def load_schedules
  return [] unless File.exist?(SCHEDULES_FILE)
  data = YAML.load_file(SCHEDULES_FILE)
  Array(data)
rescue => e
  warn "⚠️ 读取 schedules.yml 失败: #{e.message}"
  []
end

def save_schedules(list)
  FileUtils.mkdir_p(File.dirname(SCHEDULES_FILE))
  File.write(SCHEDULES_FILE, YAML.dump(list))
end

def validate_cron(expr)
  fields = expr.strip.split(/\s+/)
  unless fields.size == 5
    warn "❌ cron 表达式格式错误（应为 5 个字段：分 时 日 月 周）：#{expr}"
    exit 1
  end
end

action = ARGV[0]

unless %w[add update toggle delete list].include?(action)
  warn "Usage: ruby manage_schedule.rb add|update|toggle|delete|list [args...]"
  exit 1
end

case action
when "list"
  schedules = load_schedules
  if schedules.empty?
    puts "📋 暂无计划"
  else
    schedules.each do |s|
      enabled = s["enabled"] != false
      puts "#{enabled ? "✅" : "❌"} #{s["name"]} → task: #{s["task"]}  cron: #{s["cron"]}"
    end
  end

when "add"
  sched_name, task_name, cron_expr = ARGV[1], ARGV[2], ARGV[3..]&.join(" ")
  
  unless sched_name && task_name && cron_expr
    warn "Usage: ruby manage_schedule.rb add <schedule_name> <task_name> <cron_expr>"
    exit 1
  end
  
  validate_cron(cron_expr)
  
  list = load_schedules
  list.reject! { |s| s["name"] == sched_name }
  list << {
    "name"    => sched_name,
    "task"    => task_name,
    "cron"    => cron_expr,
    "enabled" => true
  }
  save_schedules(list)
  puts "✅ 计划已添加：#{sched_name} (#{cron_expr})"

when "update"
  sched_name, new_cron = ARGV[1], ARGV[2..]&.join(" ")
  
  unless sched_name && new_cron
    warn "Usage: ruby manage_schedule.rb update <schedule_name> <new_cron>"
    exit 1
  end
  
  validate_cron(new_cron)
  
  list = load_schedules
  entry = list.find { |s| s["name"] == sched_name }
  unless entry
    warn "❌ 计划不存在：#{sched_name}"
    exit 1
  end
  
  old_cron = entry["cron"]
  entry["cron"] = new_cron.strip
  save_schedules(list)
  puts "✅ 计划已更新：#{sched_name}"
  puts "   #{old_cron} → #{new_cron.strip}"

when "toggle"
  sched_name, enabled_str = ARGV[1], ARGV[2]
  
  unless sched_name && enabled_str
    warn "Usage: ruby manage_schedule.rb toggle <schedule_name> true|false"
    exit 1
  end
  
  enabled = enabled_str.downcase == "true"
  
  list = load_schedules
  entry = list.find { |s| s["name"] == sched_name }
  unless entry
    warn "❌ 计划不存在：#{sched_name}"
    exit 1
  end
  
  entry["enabled"] = enabled
  save_schedules(list)
  status = enabled ? "✅ 已启用" : "❌ 已禁用"
  puts "#{status}：#{sched_name}"

when "delete"
  sched_name = ARGV[1]
  
  unless sched_name
    warn "Usage: ruby manage_schedule.rb delete <schedule_name>"
    exit 1
  end
  
  list = load_schedules
  entry = list.find { |s| s["name"] == sched_name }

  unless entry
    warn "❌ Schedule not found: #{sched_name}"
    exit 1
  end

  task_name = entry["task"]
  list.reject! { |s| s["name"] == sched_name }
  save_schedules(list)
  puts "🗑 Schedule deleted: #{sched_name}"

  # Also delete the task prompt file if it exists
  task_file = File.expand_path("~/.clacky/tasks/#{task_name}.md")
  if File.exist?(task_file)
    File.delete(task_file)
    puts "🗑 Task file deleted: #{task_file}"
  end
end
