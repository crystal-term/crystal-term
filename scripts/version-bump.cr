#!/usr/bin/env crystal

# Version Bump Utility
#
# Updates version numbers in both shard.yml and version.cr files for a specific module.

require "colorize"

def usage
  puts <<-HELP
  Version Bump Utility

  Usage:
    crystal scripts/version-bump.cr <module-name> <new-version>
    crystal scripts/version-bump.cr <module-name> <bump-type>

  Arguments:
    module-name   - Name of the module (e.g., color, cursor, prompt)
    new-version   - Specific version number (e.g., 1.2.3)
    bump-type     - major, minor, or patch

  Examples:
    crystal scripts/version-bump.cr cursor 1.0.0
    crystal scripts/version-bump.cr cursor major
    crystal scripts/version-bump.cr prompt minor

  HELP
end

def get_current_version(shard_yml_path : String) : String?
  return nil unless File.exists?(shard_yml_path)
  
  content = File.read(shard_yml_path)
  if match = content.match(/^version:\s*([^\s]+)/m)
    match[1]
  else
    nil
  end
end

def calculate_new_version(current : String, bump_type : String) : String
  parts = current.split('.').map(&.to_i)
  
  case bump_type
  when "major"
    "#{parts[0] + 1}.0.0"
  when "minor"
    "#{parts[0]}.#{parts[1] + 1}.0"
  when "patch"
    "#{parts[0]}.#{parts[1]}.#{parts[2] + 1}"
  else
    bump_type # Assume it's a specific version
  end
end

def update_shard_yml(path : String, new_version : String) : Bool
  return false unless File.exists?(path)
  
  content = File.read(path)
  updated = content.gsub(/^version:\s*.*$/m, "version: #{new_version}")
  
  if content != updated
    File.write(path, updated)
    true
  else
    false
  end
end

def update_version_cr(path : String, new_version : String) : Bool
  return false unless File.exists?(path)
  
  content = File.read(path)
  updated = content.gsub(/VERSION\s*=\s*"[^"]+"/, "VERSION = \"#{new_version}\"")
  
  if content != updated
    File.write(path, updated)
    true
  else
    false
  end
end

# Main execution
if ARGV.size < 2
  usage
  exit 1
end

module_name = ARGV[0]
version_input = ARGV[1]

# Validate module exists
module_dir = File.join(Dir.current, module_name)
unless File.directory?(module_dir)
  puts "Error: Module '#{module_name}' not found in current directory".colorize(:red)
  exit 1
end

shard_yml_path = File.join(module_dir, "shard.yml")
version_cr_path = File.join(module_dir, "src", module_name, "version.cr")

# Check if this might be a term-* module
if !File.exists?(version_cr_path)
  version_cr_path = File.join(module_dir, "src", "#{module_name}", "version.cr")
end

unless File.exists?(shard_yml_path)
  puts "Error: shard.yml not found at #{shard_yml_path}".colorize(:red)
  exit 1
end

unless File.exists?(version_cr_path)
  puts "Error: version.cr not found at #{version_cr_path}".colorize(:red)
  exit 1
end

# Get current version
current_version = get_current_version(shard_yml_path)
unless current_version
  puts "Error: Could not determine current version from shard.yml".colorize(:red)
  exit 1
end

# Calculate new version
new_version = if %w[major minor patch].includes?(version_input)
  calculate_new_version(current_version, version_input)
else
  version_input
end

puts "Updating #{module_name.colorize(:cyan)}: #{current_version} → #{new_version.colorize(:green)}"

# Update files
shard_updated = update_shard_yml(shard_yml_path, new_version)
version_updated = update_version_cr(version_cr_path, new_version)

if shard_updated || version_updated
  puts "✅ Version bump completed successfully!".colorize(:green)
  
  if shard_updated
    puts "  📄 Updated #{shard_yml_path}".colorize(:blue)
  end
  
  if version_updated
    puts "  📄 Updated #{version_cr_path}".colorize(:blue)
  end
else
  puts "⚠️  No changes made (version already #{new_version})".colorize(:yellow)
end