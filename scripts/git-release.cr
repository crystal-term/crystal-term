#!/usr/bin/env crystal

# Git Release Utilities
#
# Specialized git operations for crystal-term releases including tag management,
# release validation, and GitHub integration.

require "colorize"

def usage
  puts <<-HELP
  Git Release Utilities

  Usage:
    crystal scripts/git-release.cr <command> [options]

  Commands:
    list-tags              - List all release tags
    check-tag <tag>        - Check if a tag exists
    create-tag <module> <version> - Create a release tag
    delete-tag <tag>       - Delete a release tag (use with caution!)
    validate-repo          - Validate repository state for releases
    sync-tags              - Sync local tags with remote
    release-info           - Show release information and statistics

  Examples:
    crystal scripts/git-release.cr list-tags
    crystal scripts/git-release.cr create-tag term-cursor 1.0.0
    crystal scripts/git-release.cr check-tag term-cursor-v1.0.0
    crystal scripts/git-release.cr validate-repo

  HELP
end

def validate_git_repo
  unless system("git rev-parse --git-dir > /dev/null 2>&1")
    puts "Error: Not in a git repository".colorize(:red)
    exit 1
  end
end

def list_tags
  validate_git_repo
  
  puts "🏷️  Crystal-Term Release Tags".colorize(:blue).bold
  puts "═" * 50
  
  # Get all tags, filter for our modules, and sort by version
  output = `git tag -l`.strip
  if output.empty?
    puts "No tags found".colorize(:yellow)
    return
  end
  
  # Group tags by module
  module_tags = {} of String => Array(String)
  
  output.lines.each do |tag|
    tag = tag.strip
    if match = tag.match(/^(term-\w+)-v(.+)$/)
      module_name = match[1]
      version = match[2]
      module_tags[module_name] ||= [] of String
      module_tags[module_name] << version
    end
  end
  
  if module_tags.empty?
    puts "No crystal-term module tags found".colorize(:yellow)
    puts "Expected format: term-module-vX.Y.Z"
    return
  end
  
  # Sort and display
  module_tags.keys.sort.each do |module_name|
    versions = module_tags[module_name].sort_by { |v| v.split('.').map(&.to_i) }
    puts "\n#{module_name.colorize(:cyan)}:"
    versions.each do |version|
      tag_name = "#{module_name}-v#{version}"
      
      # Get tag info
      tag_info = `git log -1 --format="%ci %s" #{tag_name} 2>/dev/null`.strip
      if tag_info.empty?
        puts "  #{version.colorize(:green)} (no commit info)"
      else
        date = tag_info.split(" ")[0]
        puts "  #{version.colorize(:green)} (#{date.colorize(:blue)})"
      end
    end
  end
  
  puts "\n📊 Summary: #{module_tags.values.map(&.size).sum} total tags across #{module_tags.size} modules"
end

def check_tag(tag_name : String)
  validate_git_repo
  
  # Ensure proper format if just module and version given
  if !tag_name.includes?("-v") && ARGV.size > 2
    module_name = tag_name
    version = ARGV[2]
    tag_name = "#{module_name}-v#{version}"
  end
  
  if system("git rev-parse #{tag_name} > /dev/null 2>&1")
    puts "✅ Tag #{tag_name.colorize(:green)} exists"
    
    # Show tag details
    tag_info = `git log -1 --format="%H %ci %s" #{tag_name}`.strip
    if !tag_info.empty?
      parts = tag_info.split(" ", 4)
      commit = parts[0][0..7]
      date = "#{parts[1]} #{parts[2]}"
      message = parts[3]? || ""
      
      puts "  Commit: #{commit.colorize(:blue)}"
      puts "  Date: #{date.colorize(:cyan)}"
      puts "  Message: #{message.colorize(:yellow)}" unless message.empty?
    end
    
    # Check if pushed to origin
    if system("git ls-remote --exit-code origin refs/tags/#{tag_name} > /dev/null 2>&1")
      puts "  📤 Pushed to origin: ✅"
    else
      puts "  📤 Pushed to origin: ❌ (local only)"
    end
  else
    puts "❌ Tag #{tag_name.colorize(:red)} does not exist"
    exit 1
  end
end

def create_tag(module_name : String, version : String)
  validate_git_repo
  
  # Ensure version starts with 'v' if not already
  version = "v#{version}" unless version.starts_with?("v")
  tag_name = "#{module_name}-#{version}"
  
  # Check if tag already exists
  if system("git rev-parse #{tag_name} > /dev/null 2>&1")
    puts "Error: Tag #{tag_name.colorize(:red)} already exists"
    exit 1
  end
  
  # Validate module exists
  module_dir = File.join(Dir.current, module_name.sub("term-", ""))
  unless File.directory?(module_dir)
    puts "Error: Module directory not found: #{module_dir}".colorize(:red)
    exit 1
  end
  
  message = "Release #{module_name} #{version}"
  
  puts "Creating tag: #{tag_name.colorize(:green)}"
  puts "Message: #{message.colorize(:cyan)}"
  
  if system("git tag -a #{tag_name} -m \"#{message}\"")
    puts "✅ Tag created successfully!"
    puts "📤 Push with: git push origin #{tag_name}"
  else
    puts "❌ Failed to create tag"
    exit 1
  end
end

def delete_tag(tag_name : String)
  validate_git_repo
  
  unless system("git rev-parse #{tag_name} > /dev/null 2>&1")
    puts "Error: Tag #{tag_name.colorize(:red)} does not exist"
    exit 1
  end
  
  puts "⚠️  WARNING: You are about to delete tag #{tag_name.colorize(:red)}".colorize(:yellow)
  
  # Show what will be deleted
  tag_info = `git log -1 --format="%ci %s" #{tag_name}`.strip
  puts "Tag info: #{tag_info}" unless tag_info.empty?
  
  print "Type the tag name to confirm deletion: "
  confirmation = gets.try(&.strip) || ""
  
  unless confirmation == tag_name
    puts "Confirmation failed. Tag not deleted.".colorize(:yellow)
    exit 1
  end
  
  # Delete local tag
  if system("git tag -d #{tag_name}")
    puts "✅ Local tag deleted"
    
    # Check if it exists on remote
    if system("git ls-remote --exit-code origin refs/tags/#{tag_name} > /dev/null 2>&1")
      puts "⚠️  Tag still exists on origin".colorize(:yellow)
      if system("echo 'Type YES to delete from origin: ' && read -r confirm && [ \"$confirm\" = \"YES\" ]")
        if system("git push origin :refs/tags/#{tag_name}")
          puts "✅ Remote tag deleted"
        else
          puts "❌ Failed to delete remote tag"
        end
      end
    end
  else
    puts "❌ Failed to delete local tag"
    exit 1
  end
end

def validate_repo
  puts "🔍 Validating repository for releases...".colorize(:blue)
  
  validate_git_repo
  issues = [] of String
  
  # Check if we're in the right directory
  unless File.exists?("release.cr")
    issues << "Not in crystal-term root directory (no release.cr found)"
  end
  
  # Check current branch
  current_branch = `git branch --show-current`.strip
  if current_branch != "main" && current_branch != "master"
    issues << "Not on main/master branch (currently on #{current_branch})"
  end
  
  # Check for uncommitted changes
  unless system("git diff-index --quiet HEAD --")
    issues << "Repository has uncommitted changes"
  end
  
  # Check if origin is set
  unless system("git remote get-url origin > /dev/null 2>&1")
    issues << "No origin remote configured"
  end
  
  # Check if we can push
  unless system("git ls-remote origin > /dev/null 2>&1")
    issues << "Cannot connect to origin remote"
  end
  
  # Check for required files
  required_files = ["release.cr", "scripts/version-bump.cr", "scripts/validate-versions.cr"]
  required_files.each do |file|
    unless File.exists?(file)
      issues << "Missing required file: #{file}"
    end
  end
  
  # Display results
  if issues.empty?
    puts "✅ Repository is ready for releases!".colorize(:green)
    
    # Show additional info
    origin_url = `git remote get-url origin 2>/dev/null`.strip
    puts "Remote origin: #{origin_url.colorize(:cyan)}" unless origin_url.empty?
    puts "Current branch: #{current_branch.colorize(:cyan)}"
    
    # Show last few commits
    puts "\nRecent commits:".colorize(:blue)
    system("git log --oneline -5")
    
  else
    puts "❌ Repository validation failed:".colorize(:red)
    issues.each do |issue|
      puts "  • #{issue.colorize(:yellow)}"
    end
    exit 1
  end
end

def sync_tags
  validate_git_repo
  
  puts "🔄 Syncing tags with origin...".colorize(:blue)
  
  # Fetch tags from origin
  if system("git fetch origin --tags")
    puts "✅ Fetched latest tags from origin"
  else
    puts "❌ Failed to fetch tags from origin"
    exit 1
  end
  
  # Show any new tags
  puts "\n📋 All tags after sync:".colorize(:blue)
  list_tags
end

def release_info
  validate_git_repo
  
  puts "📊 Crystal-Term Release Information".colorize(:blue).bold
  puts "═" * 50
  
  # Module information
  modules = %w[color cursor prompt reader screen spinner terminfo]
  puts "\n📦 Modules: #{modules.size}"
  modules.each { |mod| puts "  • term-#{mod}" }
  
  # Tag statistics
  all_tags = `git tag -l`.strip.lines.select { |t| t.strip.match(/^term-\w+-v/) }
  puts "\n🏷️  Tags: #{all_tags.size} total release tags"
  
  # Latest releases
  puts "\n🆕 Latest Releases:".colorize(:blue)
  modules.each do |mod|
    module_name = "term-#{mod}"
    latest_tag = `git tag -l "#{module_name}-v*" | sort -V | tail -1`.strip
    
    if latest_tag.empty?
      puts "  #{module_name.colorize(:cyan)}: No releases"
    else
      version = latest_tag.sub("#{module_name}-v", "")
      date = `git log -1 --format="%ci" #{latest_tag} 2>/dev/null`.strip.split(" ")[0]
      puts "  #{module_name.colorize(:cyan)}: #{version.colorize(:green)} (#{date.colorize(:blue)})"
    end
  end
  
  # Repository info
  origin_url = `git remote get-url origin 2>/dev/null`.strip
  unless origin_url.empty?
    puts "\n🔗 Repository: #{origin_url.colorize(:cyan)}"
    
    if origin_url.includes?("github.com")
      # Extract GitHub info
      if match = origin_url.match(/github\.com[\/:]([^\/]+)\/([^\/\.]+)/)
        owner = match[1]
        repo = match[2]
        puts "📍 GitHub: https://github.com/#{owner}/#{repo}/releases".colorize(:cyan)
      end
    end
  end
end

# Main execution
if ARGV.empty?
  usage
  exit 1
end

command = ARGV[0]

case command
when "list-tags"
  list_tags
when "check-tag"
  if ARGV.size < 2
    puts "Error: Please specify a tag name".colorize(:red)
    puts "Usage: crystal scripts/git-release.cr check-tag <tag-name>"
    exit 1
  end
  check_tag(ARGV[1])
when "create-tag"
  if ARGV.size < 3
    puts "Error: Please specify module and version".colorize(:red)
    puts "Usage: crystal scripts/git-release.cr create-tag <module> <version>"
    exit 1
  end
  create_tag(ARGV[1], ARGV[2])
when "delete-tag"
  if ARGV.size < 2
    puts "Error: Please specify a tag name".colorize(:red)
    puts "Usage: crystal scripts/git-release.cr delete-tag <tag-name>"
    exit 1
  end
  delete_tag(ARGV[1])
when "validate-repo"
  validate_repo
when "sync-tags"
  sync_tags
when "release-info"
  release_info
else
  puts "Unknown command: #{command}".colorize(:red)
  usage
  exit 1
end