#!/usr/bin/env ruby
# manage_task.rb — Create, update, delete task prompt files
# Usage:
#   ruby manage_task.rb create <name> <content>
#   ruby manage_task.rb update <name> <content>
#   ruby manage_task.rb delete <name>
#   ruby manage_task.rb read   <name>

require 'fileutils'

TASKS_DIR = File.expand_path("~/.clacky/tasks")

def validate_name(name)
  unless name.match?(/\A[a-z0-9_-]+\z/)
    warn "❌ 任务名无效：只允许小写字母、数字、下划线、短横线（[a-z0-9_-]）"
    exit 1
  end
end

def task_path(name)
  File.join(TASKS_DIR, "#{name}.md")
end

action = ARGV[0]
name   = ARGV[1]
content = ARGV[2..]&.join(" ")

unless %w[create update delete read].include?(action)
  warn "Usage: ruby manage_task.rb create|update|delete|read <name> [content]"
  exit 1
end

unless name && !name.strip.empty?
  warn "❌ 请提供任务名"
  exit 1
end

name = name.strip
validate_name(name)
FileUtils.mkdir_p(TASKS_DIR)

case action
when "create"
  if File.exist?(task_path(name))
    warn "⚠️  任务 #{name} 已存在，如要修改请使用 update 命令"
    exit 1
  end
  if content.nil? || content.strip.empty?
    warn "❌ 请提供任务内容"
    exit 1
  end
  File.write(task_path(name), content.strip + "\n")
  puts "✅ 任务已创建：#{task_path(name)}"

when "update"
  unless File.exist?(task_path(name))
    warn "❌ 任务不存在：#{name}"
    exit 1
  end
  if content.nil? || content.strip.empty?
    warn "❌ 请提供新的任务内容"
    exit 1
  end
  File.write(task_path(name), content.strip + "\n")
  puts "✅ 任务已更新：#{task_path(name)}"

when "delete"
  unless File.exist?(task_path(name))
    warn "❌ 任务不存在：#{name}"
    exit 1
  end
  File.delete(task_path(name))
  puts "🗑 任务文件已删除：#{task_path(name)}"

when "read"
  unless File.exist?(task_path(name))
    warn "❌ 任务不存在：#{name}"
    exit 1
  end
  puts File.read(task_path(name))
end
