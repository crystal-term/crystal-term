#!/usr/bin/env crystal

# Dependency Update Utility
#
# Updates inter-module dependency versions in shard.yml files.
# Useful for ensuring dependencies point to the latest released versions.

require "colorize"

def usage
  puts <<-HELP
  Dependency Update Utility

  Usage:
    crystal scripts/dependency-update.cr <module-name> <dependency> <version>
    crystal scripts/dependency-update.cr --all-latest

  Arguments:
    module-name   - Target module to update (e.g., prompt, reader)
    dependency    - Dependency name (e.g., term-cursor, term-screen)
    version       - New version for the dependency

  Options:
    --all-latest  - Update all inter-module dependencies to latest versions

  Examples:
    crystal scripts/dependency-update.cr prompt term-cursor 1.0.0
    crystal scripts/dependency-update.cr reader term-screen 0.3.0
    crystal scripts/dependency-update.cr --all-latest

  HELP
end

struct ModuleInfo
  property name : String
  property path : String
  property version : String
  
  def initialize(@name : String, @path : String)
    @version = get_version
  end
  
  private def get_version : String
    shard_yml = File.join(@path, "shard.yml")
    return "0.0.0" unless File.exists?(shard_yml)
    
    content = File.read(shard_yml)
    if match = content.match(/^version:\s*([^\s]+)/m)
      match[1]
    else
      "0.0.0"
    end
  end
end

def discover_modules : Hash(String, ModuleInfo)
  modules = {} of String => ModuleInfo
  
  %w[color cursor prompt reader screen spinner terminfo].each do |dir|
    path = File.join(Dir.current, dir)
    next unless File.directory?(path)
    
    name = "term-#{dir}"
    modules[name] = ModuleInfo.new(name, path)
  end
  
  modules
end

def update_dependency(module_path : String, dep_name : String, new_version : String) : Bool
  shard_yml_path = File.join(module_path, "shard.yml")
  return false unless File.exists?(shard_yml_path)
  
  content = File.read(shard_yml_path)
  lines = content.lines
  updated_lines = [] of String
  i = 0
  updated = false
  
  while i < lines.size
    line = lines[i]
    if line.strip.starts_with?("#{dep_name}:")
      updated_lines << line
      # Look for version or branch in the following lines
      j = i + 1
      found_version = false
      
      while j < lines.size && (lines[j].starts_with?("    ") || lines[j].strip.empty?)
        current_line = lines[j]
        
        if current_line.strip.starts_with?("version:")
          updated_lines << "    version: #{new_version}"
          found_version = true
          updated = true
          j += 1
          break
        elsif current_line.strip.starts_with?("branch:")
          # Replace branch with version
          updated_lines << "    version: #{new_version}"
          found_version = true
          updated = true
          j += 1
          break
        else
          updated_lines << current_line
          j += 1
        end
      end
      
      # If no version found, add it
      unless found_version
        updated_lines << "    version: #{new_version}"
        updated = true
      end
      
      i = j
    else
      updated_lines << line
      i += 1
    end
  end
  
  if updated
    File.write(shard_yml_path, updated_lines.join('\n'))
    true
  else
    false
  end
end

def get_dependencies(module_path : String) : Array(String)
  shard_yml_path = File.join(module_path, "shard.yml")
  return [] of String unless File.exists?(shard_yml_path)
  
  content = File.read(shard_yml_path)
  deps = [] of String
  
  # Look for term-* dependencies
  content.scan(/^\s*(term-\w+):\s*$/) do |match|
    deps << match[1]
  end
  
  deps
end

def update_all_latest
  puts "🔍 Discovering modules and their current versions...".colorize(:yellow)
  
  modules = discover_modules
  
  if modules.empty?
    puts "No modules found in current directory".colorize(:red)
    exit 1
  end
  
  puts "\n📦 Found modules:".colorize(:blue)
  modules.each do |name, info|
    puts "  #{name.colorize(:cyan)}: #{info.version.colorize(:green)}"
  end
  
  puts "\n🔗 Updating inter-module dependencies...".colorize(:yellow)
  
  modules.each do |module_name, module_info|
    dependencies = get_dependencies(module_info.path)
    next if dependencies.empty?
    
    puts "\nProcessing #{module_name.colorize(:cyan)}:"
    
    dependencies.each do |dep_name|
      if dep_info = modules[dep_name]?
        puts "  Updating #{dep_name} to #{dep_info.version}".colorize(:blue)
        
        if update_dependency(module_info.path, dep_name, dep_info.version)
          puts "  ✅ Updated #{dep_name} dependency".colorize(:green)
        else
          puts "  ⚠️  No update needed for #{dep_name}".colorize(:yellow)
        end
      else
        puts "  ❌ Dependency #{dep_name} not found in local modules".colorize(:red)
      end
    end
  end
  
  puts "\n🎉 All dependencies updated to latest versions!".colorize(:green).bold
end

# Main execution
if ARGV.size == 1 && ARGV[0] == "--all-latest"
  update_all_latest
  exit
end

if ARGV.size < 3
  usage
  exit 1
end

module_name = ARGV[0]
dep_name = ARGV[1]
new_version = ARGV[2]

# Validate module exists
module_dir = File.join(Dir.current, module_name)
unless File.directory?(module_dir)
  puts "Error: Module '#{module_name}' not found in current directory".colorize(:red)
  exit 1
end

# Update the dependency
puts "Updating #{module_name.colorize(:cyan)} dependency #{dep_name.colorize(:blue)} to #{new_version.colorize(:green)}"

if update_dependency(module_dir, dep_name, new_version)
  puts "✅ Dependency updated successfully!".colorize(:green)
else
  puts "⚠️  No changes made (dependency not found or already at specified version)".colorize(:yellow)
end