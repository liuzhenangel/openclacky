#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'uri'
require 'find'

# Install skills from a GitHub repository or a specific skill subdirectory.
#
# Supported URL formats:
#   https://github.com/user/repo                   — install all skills found under any skills/ dir
#   https://github.com/user/repo.git               — same, with .git suffix
#   https://github.com/user/repo/tree/main/path    — install all skills under a specific path
#   https://github.com/user/repo/skills/my-skill   — install a single specific skill
#
# Usage: ruby install_from_github.rb <github_url> [target_dir]
class SkillInstaller
  # Match bare repo URLs (with optional .git)
  REPO_URL_PATTERN     = %r{^https?://github\.com/([\w-]+/[\w.-]+?)(?:\.git)?$}
  # Match subpath URLs: github.com/user/repo/anything/after
  SUBPATH_URL_PATTERN  = %r{^https?://github\.com/([\w-]+)/([\w.-]+)/(.+)$}
  GIT_SSH_PATTERN      = %r{^git@github\.com:([\w-]+/[\w.-]+)\.git$}

  def initialize(input_url, target_dir: nil)
    @input_url  = input_url.strip
    @target_dir = target_dir || File.expand_path("~/.clacky/skills")
    @installed_skills = []
    @errors = []

    parse_url!
  end

  def install
    Dir.mktmpdir("clacky-skills-") do |tmpdir|
      clone_repository(tmpdir)
      discover_and_install_skills(tmpdir)
    end
    report_results
  rescue ArgumentError => e
    puts "❌ #{e.message}"
    exit 1
  rescue StandardError => e
    puts "❌ Installation failed: #{e.message}"
    exit 1
  end

  private

  # Parse the input URL into repo clone URL + optional subpath.
  # Sets @clone_url and @subpath (nil means "search whole repo").
  private def parse_url!
    # git SSH
    if GIT_SSH_PATTERN.match(@input_url)
      @clone_url = @input_url
      @subpath   = nil
      return
    end

    # Bare repo URL
    if REPO_URL_PATTERN.match(@input_url)
      @clone_url = "https://github.com/#{$1}.git"
      @subpath   = nil
      return
    end

    # Subpath URL — github.com/user/repo/path/to/skill
    if SUBPATH_URL_PATTERN.match(@input_url)
      user, repo, rest = $1, $2, $3

      # Strip leading tree/<branch>/ if present (GitHub UI URLs)
      rest = rest.sub(%r{^tree/[^/]+/}, "")

      @clone_url = "https://github.com/#{user}/#{repo}.git"
      @subpath   = rest.empty? ? nil : rest
      return
    end

    raise ArgumentError, "Unrecognized GitHub URL: #{@input_url}\n" \
      "Expected formats:\n" \
      "  https://github.com/user/repo\n" \
      "  https://github.com/user/repo/skills/my-skill"
  end

  private def clone_repository(tmpdir)
    puts "📦 Cloning repository..."
    puts "   #{@clone_url}"

    @repo_path = File.join(tmpdir, "repo")

    success = system("git", "clone", "--depth", "1", @clone_url, @repo_path,
                     out: File::NULL, err: File::NULL)

    unless success && $?.success?
      raise "Failed to clone repository. Please check the URL and your network connection."
    end
  end

  private def discover_and_install_skills(tmpdir)
    if @subpath
      install_from_subpath
    else
      install_from_whole_repo
    end
  end

  # Install from a specific subpath within the repo.
  # If the subpath itself contains a SKILL.md → it's a single skill.
  # Otherwise, treat it as a skills container directory and look for skill subdirs.
  private def install_from_subpath
    target_path = File.join(@repo_path, @subpath)

    unless File.exist?(target_path)
      raise "Path '#{@subpath}' not found in repository."
    end

    # Single skill directory
    if File.exist?(File.join(target_path, "SKILL.md"))
      install_single_skill(target_path)
      return
    end

    # Skills container directory
    skill_dirs = Dir.glob(File.join(target_path, "*/SKILL.md")).map { |f| File.dirname(f) }

    if skill_dirs.empty?
      raise "No skills found under '#{@subpath}'. " \
            "Expected either a SKILL.md directly in that path, " \
            "or subdirectories each containing a SKILL.md."
    end

    skill_dirs.each { |d| install_single_skill(d) }
  end

  # Search the entire cloned repo for any skills/ directories containing skills.
  private def install_from_whole_repo
    skills_found = false

    Find.find(@repo_path) do |path|
      next unless File.directory?(path)
      next unless File.basename(path) == "skills"

      skill_dirs = Dir.glob(File.join(path, "*/SKILL.md")).map { |f| File.dirname(f) }
      next if skill_dirs.empty?

      skills_found = true
      skill_dirs.each { |d| install_single_skill(d) }
    end

    unless skills_found
      raise "No skills found in repository. " \
            "Looking for directories named 'skills/' containing SKILL.md files."
    end
  end

  private def install_single_skill(skill_dir)
    skill_name  = File.basename(skill_dir)
    dest        = File.join(@target_dir, skill_name)

    if File.exist?(dest)
      puts "⚠️  Skill '#{skill_name}' already exists, skipping..."
      @errors << "Skill '#{skill_name}' already exists at #{dest}"
      return
    end

    FileUtils.mkdir_p(@target_dir)
    FileUtils.cp_r(skill_dir, dest)

    description = extract_description(File.join(dest, "SKILL.md"))
    @installed_skills << { name: skill_name, path: dest, description: description }
  rescue StandardError => e
    @errors << "Failed to install '#{skill_name}': #{e.message}"
  end

  private def extract_description(skill_file)
    return "No description" unless File.exist?(skill_file)

    content = File.read(skill_file)
    if content =~ /\A---\s*\n(.*?)\n---/m
      fm = $1
      return $1.strip if fm =~ /^description:\s*(.+)$/
    end
    "No description"
  rescue StandardError
    "No description"
  end

  private def report_results
    puts "\n" + "=" * 60

    if @installed_skills.empty?
      puts "❌ No skills were installed."
      if @errors.any?
        puts "\nErrors encountered:"
        @errors.each { |err| puts "   • #{err}" }
      end
      exit 1
    end

    puts "✅ Installation complete!"
    puts "\nInstalled #{@installed_skills.size} skill(s) to #{@target_dir}:\n\n"

    @installed_skills.each do |skill|
      puts "   ✓ #{skill[:name]}"
      puts "     #{skill[:description]}"
      puts "     → #{skill[:path]}"
      puts
    end

    if @errors.any?
      puts "⚠️  Warnings:"
      @errors.each { |err| puts "   • #{err}" }
      puts
    end

    puts "You can now use these skills with /skill-name"
    puts "=" * 60
  end
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby install_from_github.rb <github_url>"
    puts "\nExamples:"
    puts "  ruby install_from_github.rb https://github.com/user/repo"
    puts "  ruby install_from_github.rb https://github.com/user/repo/skills/my-skill"
    puts "  ruby install_from_github.rb https://github.com/user/repo/skills"
    exit 1
  end

  installer = SkillInstaller.new(ARGV[0])
  installer.install
end
