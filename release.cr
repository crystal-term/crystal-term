#!/usr/bin/env crystal

# Crystal-Term Release Manager
#
# An interactive tool for managing releases across the crystal-term monorepo.
# Handles dependency-aware version bumping and ensures consistency across modules.

require "colorize"
require "json"

# Represents a module in the monorepo
struct Module
  property name : String
  property path : String
  property current_version : String
  property new_version : String?
  property dependencies : Array(String)
  property shard_yml_path : String
  property version_cr_path : String

  def initialize(@name : String, @path : String)
    @shard_yml_path = File.join(@path, "shard.yml")
    @version_cr_path = File.join(@path, "src", @name.split('-').last, "version.cr")
    @current_version = load_version
    @dependencies = load_dependencies
  end

  private def load_version
    if File.exists?(@shard_yml_path)
      content = File.read(@shard_yml_path)
      if match = content.match(/^version:\s*([^\s]+)/m)
        return match[1]
      end
    end
    "0.0.0"
  end

  private def load_dependencies : Array(String)
    deps = [] of String
    if File.exists?(@shard_yml_path)
      content = File.read(@shard_yml_path)
      # Look for crystal-term dependencies
      content.scan(/^\s*(term-\w+):\s*$/) do |match|
        deps << match[1]
      end
    end
    deps
  end

  def bump_version(bump_type : String) : String
    parts = @current_version.split('.').map(&.to_i)
    
    case bump_type
    when "major"
      @new_version = "#{parts[0] + 1}.0.0"
    when "minor"
      @new_version = "#{parts[0]}.#{parts[1] + 1}.0"
    when "patch"
      @new_version = "#{parts[0]}.#{parts[1]}.#{parts[2] + 1}"
    else
      @new_version = bump_type # Custom version
    end
    
    @new_version.not_nil!
  end

  def write_versions
    return false unless new_ver = @new_version
    
    # Update shard.yml
    if File.exists?(@shard_yml_path)
      content = File.read(@shard_yml_path)
      updated = content.gsub(/^version:\s*.*$/, "version: #{new_ver}")
      File.write(@shard_yml_path, updated)
    end
    
    # Update version.cr
    if File.exists?(@version_cr_path)
      content = File.read(@version_cr_path)
      updated = content.gsub(/VERSION\s*=\s*"[^"]+"/, "VERSION = \"#{new_ver}\"")
      File.write(@version_cr_path, updated)
    end
    
    true
  end

  def update_dependency_version(dep_name : String, new_version : String)
    return unless File.exists?(@shard_yml_path)
    
    content = File.read(@shard_yml_path)
    # Find the dependency block and update version
    lines = content.lines
    updated_lines = [] of String
    i = 0
    
    while i < lines.size
      line = lines[i]
      if line.strip.starts_with?("#{dep_name}:")
        updated_lines << line
        # Look for version line in the next few lines
        j = i + 1
        while j < lines.size && (lines[j].starts_with?("    ") || lines[j].strip.empty?)
          if lines[j].strip.starts_with?("version:")
            updated_lines << "    version: #{new_version}"
            j += 1
            break
          elsif lines[j].strip.starts_with?("branch:")
            # Remove branch and add version
            updated_lines << "    version: #{new_version}"
            j += 1
            break
          else
            updated_lines << lines[j]
            j += 1
          end
        end
        i = j
      else
        updated_lines << line
        i += 1
      end
    end
    
    File.write(@shard_yml_path, updated_lines.join('\n'))
  end
end

class ReleaseManager
  @modules = {} of String => Module
  @dependency_graph = {} of String => Array(String)

  def initialize
    validate_git_environment
    discover_modules
    build_dependency_graph
  end

  private def validate_git_environment
    # Check if we're in a git repository
    unless system("git rev-parse --git-dir > /dev/null 2>&1")
      puts "Error: Not in a git repository".colorize(:red)
      exit 1
    end

    # Check for uncommitted changes
    if system("git diff-index --quiet HEAD --")
      # No uncommitted changes
    else
      puts "⚠️  Warning: You have uncommitted changes".colorize(:yellow)
      puts "The following files have changes:"
      system("git status --porcelain")
      
      unless confirm("Continue with uncommitted changes?")
        puts "Please commit or stash your changes before releasing".colorize(:yellow)
        exit 1
      end
    end

    # Check current branch
    current_branch = `git branch --show-current`.strip
    puts "Current branch: #{current_branch.colorize(:cyan)}"
    
    if current_branch != "main" && current_branch != "master"
      unless confirm("You're not on main/master branch. Continue anyway?")
        puts "Switch to main/master branch for releases".colorize(:yellow)
        exit 1
      end
    end
  end

  private def discover_modules
    # Known module directories
    module_dirs = %w[color cursor prompt reader screen spinner terminfo]
    
    module_dirs.each do |dir|
      path = File.join(Dir.current, dir)
      next unless File.directory?(path)
      
      name = "term-#{dir}"
      @modules[name] = Module.new(name, path)
      puts "Discovered module: #{name.colorize(:cyan)} (#{@modules[name].current_version})"
    end
  end

  private def build_dependency_graph
    @modules.each do |name, mod|
      @dependency_graph[name] = mod.dependencies
      unless mod.dependencies.empty?
        puts "#{name.colorize(:yellow)} depends on: #{mod.dependencies.join(", ").colorize(:green)}"
      end
    end
  end

  def interactive_release
    puts "\n🚀 Crystal-Term Release Manager".colorize(:blue).bold
    puts "═" * 50

    # Show current state
    show_current_versions

    puts "\nSelect release type:"
    puts "1. #{("Major").colorize(:red)} - Breaking changes (x.0.0)"
    puts "2. #{("Minor").colorize(:yellow)} - New features (0.x.0)"
    puts "3. #{("Patch").colorize(:green)} - Bug fixes (0.0.x)"
    puts "4. #{("Custom").colorize(:cyan)} - Specify versions manually"
    puts "5. #{("Exit").colorize(:magenta)}"

    print "\nEnter choice (1-5): "
    choice = gets.try(&.strip) || "5"

    case choice
    when "1"
      release_all("major")
    when "2"
      release_all("minor")
    when "3"
      release_all("patch")
    when "4"
      custom_release
    when "5"
      puts "Goodbye! 👋".colorize(:magenta)
      exit
    else
      puts "Invalid choice. Please try again.".colorize(:red)
      interactive_release
    end
  end

  private def show_current_versions
    puts "\n📦 Current Module Versions:".colorize(:blue)
    @modules.each do |name, mod|
      deps_info = mod.dependencies.empty? ? "" : " (depends on: #{mod.dependencies.join(", ")})"
      puts "  #{name.colorize(:cyan)}: #{mod.current_version.colorize(:green)}#{deps_info}"
    end
  end

  private def release_all(bump_type : String)
    puts "\n🔄 Planning #{bump_type} release for all modules...".colorize(:yellow)
    
    # First, bump all versions
    @modules.each do |name, mod|
      new_version = mod.bump_version(bump_type)
      puts "  #{name}: #{mod.current_version} → #{new_version.colorize(:green)}"
    end

    if confirm_release
      # Get release order based on dependencies
      release_order = calculate_release_order
      
      puts "\n📋 Release order: #{release_order.join(" → ").colorize(:cyan)}"
      
      # Update inter-dependencies first
      update_inter_dependencies
      
      # Write all version files
      release_order.each do |module_name|
        if mod = @modules[module_name]?
          if mod.write_versions
            puts "✅ Updated #{module_name}".colorize(:green)
          else
            puts "❌ Failed to update #{module_name}".colorize(:red)
            exit 1
          end
        end
      end
      
      # Create git tags and commits
      if confirm("Create git tags and commit changes?")
        create_git_releases(release_order)
      end
      
      puts "\n🎉 Release completed successfully!".colorize(:green).bold
    else
      puts "Release cancelled.".colorize(:yellow)
    end
  end

  private def custom_release
    puts "\n🎯 Custom Release Mode".colorize(:cyan)
    
    @modules.each do |name, mod|
      puts "\nCurrent version of #{name.colorize(:cyan)}: #{mod.current_version.colorize(:green)}"
      print "New version (or press Enter to keep current): "
      input = gets.try(&.strip)
      
      if input && !input.empty?
        mod.bump_version(input)
        puts "  #{name}: #{mod.current_version} → #{mod.new_version.colorize(:green)}"
      end
    end
    
    if confirm_release
      release_order = calculate_release_order
      update_inter_dependencies
      
      release_order.each do |module_name|
        if mod = @modules[module_name]?
          next unless mod.new_version
          
          if mod.write_versions
            puts "✅ Updated #{module_name}".colorize(:green)
          else
            puts "❌ Failed to update #{module_name}".colorize(:red)
            exit 1
          end
        end
      end
      
      if confirm("Create git tags and commit changes?")
        create_git_releases(release_order.select { |name| @modules[name].new_version })
      end
      
      puts "\n🎉 Custom release completed!".colorize(:green).bold
    else
      puts "Release cancelled.".colorize(:yellow)
    end
  end

  private def calculate_release_order : Array(String)
    # Topological sort of dependency graph
    visited = Set(String).new
    temp_visited = Set(String).new
    result = [] of String

    visit_node = nil
    visit_node = ->(node : String) {
      return if visited.includes?(node)
      
      if temp_visited.includes?(node)
        puts "Warning: Circular dependency detected involving #{node}".colorize(:red)
        return
      end
      
      temp_visited.add(node)
      
      # Visit dependencies first
      if deps = @dependency_graph[node]?
        deps.each do |dep|
          visit_node.not_nil!.call(dep) if @modules.has_key?(dep)
        end
      end
      
      temp_visited.delete(node)
      visited.add(node)
      result << node
    }

    @modules.keys.each do |module_name|
      visit_node.not_nil!.call(module_name)
    end

    result
  end

  private def update_inter_dependencies
    puts "\n🔗 Updating inter-module dependencies...".colorize(:yellow)
    
    @modules.each do |name, mod|
      mod.dependencies.each do |dep_name|
        if dep_mod = @modules[dep_name]?
          if dep_new_version = dep_mod.new_version
            puts "  Updating #{name} dependency on #{dep_name} to #{dep_new_version}".colorize(:cyan)
            mod.update_dependency_version(dep_name, dep_new_version)
          end
        end
      end
    end
  end

  private def create_git_releases(modules : Array(String))
    # Get the current branch for pushing
    current_branch = `git branch --show-current`.strip
    
    puts "\n🏷️  Creating Git releases...".colorize(:blue)
    
    # First, stage and commit all changes together
    puts "📝 Staging all release changes...".colorize(:yellow)
    
    changed_modules = [] of String
    modules.each do |module_name|
      if mod = @modules[module_name]?
        if new_version = mod.new_version
          changed_modules << module_name
          system("git add #{mod.path}/shard.yml #{mod.version_cr_path}")
        end
      end
    end
    
    if changed_modules.empty?
      puts "No changes to commit".colorize(:yellow)
      return
    end
    
    # Create a single commit for all version updates
    commit_msg = if changed_modules.size == 1
      "Release #{changed_modules.first} v#{@modules[changed_modules.first].new_version}"
    else
      version_list = changed_modules.map { |name| 
        "#{name} v#{@modules[name].new_version}" 
      }.join(", ")
      "Release multiple modules: #{version_list}"
    end
    
    puts "💾 Committing: #{commit_msg.colorize(:cyan)}"
    unless system("git commit -m \"#{commit_msg}\"")
      puts "❌ Failed to create commit".colorize(:red)
      return
    end
    
    # Create individual tags for each module
    puts "🏷️  Creating tags...".colorize(:yellow)
    changed_modules.each do |module_name|
      if mod = @modules[module_name]?
        if new_version = mod.new_version
          tag_name = "#{module_name}-v#{new_version}"
          
          if system("git tag -a #{tag_name} -m \"Release #{module_name} v#{new_version}\"")
            puts "  ✅ Created tag: #{tag_name.colorize(:green)}"
          else
            puts "  ❌ Failed to create tag: #{tag_name.colorize(:red)}"
          end
        end
      end
    end
    
    # Show what was created
    puts "\n📋 Release Summary:".colorize(:blue)
    puts "  Commit: #{commit_msg.colorize(:cyan)}"
    changed_modules.each do |module_name|
      if mod = @modules[module_name]?
        if new_version = mod.new_version
          tag_name = "#{module_name}-v#{new_version}"
          puts "  Tag: #{tag_name.colorize(:green)}"
        end
      end
    end
    
    # Offer to push immediately
    if confirm("\n🚀 Push release to origin now?")
      push_release(current_branch, changed_modules)
    else
      puts "\n📤 To push manually later, run:".colorize(:blue)
      puts "git push origin #{current_branch} --tags"
    end
  end

  private def push_release(branch : String, modules : Array(String))
    puts "🚀 Pushing to origin...".colorize(:yellow)
    
    # Push the commit first
    if system("git push origin #{branch}")
      puts "  ✅ Pushed commits to #{branch}".colorize(:green)
    else
      puts "  ❌ Failed to push commits".colorize(:red)
      return
    end
    
    # Push all tags
    if system("git push origin --tags")
      puts "  ✅ Pushed all tags".colorize(:green)
    else
      puts "  ❌ Failed to push tags".colorize(:red)
      puts "  You may need to push tags manually: git push origin --tags".colorize(:yellow)
      return
    end
    
    puts "\n🎉 Release successfully pushed to origin!".colorize(:green).bold
    
    # Show GitHub release URLs if this looks like a GitHub repo
    origin_url = `git remote get-url origin 2>/dev/null`.strip
    if origin_url.includes?("github.com")
      puts "\n🔗 GitHub Release URLs:".colorize(:blue)
      modules.each do |module_name|
        if mod = @modules[module_name]?
          if new_version = mod.new_version
            # Extract repo info from git URL
            if match = origin_url.match(/github\.com[\/:]([^\/]+)\/([^\/\.]+)/)
              owner = match[1]
              repo = match[2]
              tag_name = "#{module_name}-v#{new_version}"
              url = "https://github.com/#{owner}/#{repo}/releases/tag/#{tag_name}"
              puts "  #{module_name}: #{url.colorize(:cyan)}"
            end
          end
        end
      end
    end
  end

  private def confirm_release : Bool
    puts "\n🤔 Review the planned changes above."
    confirm("Proceed with the release?")
  end

  private def confirm(message : String) : Bool
    print "#{message} (y/N): "
    response = gets.try(&.strip.downcase) || "n"
    response.starts_with?("y")
  end
end

# Main execution
if ARGV.size > 0 && ARGV[0] == "--help"
  puts <<-HELP
  Crystal-Term Release Manager

  Usage:
    crystal release.cr           # Interactive release mode
    crystal release.cr --help    # Show this help

  Features:
    • Interactive release planning with dependency awareness
    • Automatic version bumping (major/minor/patch/custom)
    • Inter-module dependency updates
    • Git tag creation and commits
    • Dependency graph validation

  HELP
  exit
end

begin
  manager = ReleaseManager.new
  manager.interactive_release
rescue ex
  puts "Error: #{ex.message}".colorize(:red)
  exit 1
end