#!/usr/bin/env crystal

# Version Validation Utility
#
# Validates that versions are consistent between shard.yml and version.cr files
# across all modules in the monorepo.

require "colorize"

struct ValidationResult
  property module_name : String
  property shard_version : String?
  property code_version : String?
  property valid : Bool
  property issues : Array(String)
  
  def initialize(@module_name : String)
    @valid = true
    @issues = [] of String
  end
end

def usage
  puts <<-HELP
  Version Validation Utility

  Usage:
    crystal scripts/validate-versions.cr [options]

  Options:
    --fix         - Attempt to fix version inconsistencies automatically
    --detailed    - Show detailed validation information
    --help        - Show this help message

  This tool validates:
    • shard.yml version matches version.cr VERSION constant
    • All modules have both shard.yml and version.cr files
    • Version formats are valid semantic versions
    • Inter-module dependency versions exist and are valid

  HELP
end

def validate_version_format(version : String) : Bool
  # Basic semantic version validation (X.Y.Z)
  !!/^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$/.match(version)
end

def get_shard_version(module_path : String) : String?
  shard_yml = File.join(module_path, "shard.yml")
  return nil unless File.exists?(shard_yml)
  
  content = File.read(shard_yml)
  if match = content.match(/^version:\s*([^\s]+)/m)
    match[1]
  else
    nil
  end
end

def get_code_version(module_path : String, module_name : String) : String?
  # Try standard path first
  version_cr = File.join(module_path, "src", module_name.sub("term-", ""), "version.cr")
  
  unless File.exists?(version_cr)
    # Try with full term- prefix
    version_cr = File.join(module_path, "src", module_name, "version.cr")
  end
  
  return nil unless File.exists?(version_cr)
  
  content = File.read(version_cr)
  if match = content.match(/VERSION\s*=\s*"([^"]+)"/)
    match[1]
  else
    nil
  end
end

def get_dependencies(module_path : String) : Array(Tuple(String, String?))
  shard_yml = File.join(module_path, "shard.yml")
  return [] of Tuple(String, String?) unless File.exists?(shard_yml)
  
  content = File.read(shard_yml)
  deps = [] of Tuple(String, String?)
  lines = content.lines
  i = 0
  
  while i < lines.size
    line = lines[i]
    if match = line.match(/^\s*(term-\w+):\s*$/)
      dep_name = match[1]
      version = nil
      
      # Look for version in following lines
      j = i + 1
      while j < lines.size && (lines[j].starts_with?("    ") || lines[j].strip.empty?)
        if version_match = lines[j].match(/^\s+version:\s*([^\s]+)/)
          version = version_match[1]
          break
        end
        j += 1
      end
      
      deps << {dep_name, version}
      i = j
    else
      i += 1
    end
  end
  
  deps
end

def fix_version_inconsistency(module_path : String, module_name : String, correct_version : String, fix_target : String)
  case fix_target
  when "shard"
    shard_yml = File.join(module_path, "shard.yml")
    content = File.read(shard_yml)
    updated = content.gsub(/^version:\s*.*$/m, "version: #{correct_version}")
    File.write(shard_yml, updated)
    puts "  🔧 Fixed shard.yml version".colorize(:green)
  when "code"
    version_cr = File.join(module_path, "src", module_name.sub("term-", ""), "version.cr")
    unless File.exists?(version_cr)
      version_cr = File.join(module_path, "src", module_name, "version.cr")
    end
    
    content = File.read(version_cr)
    updated = content.gsub(/VERSION\s*=\s*"[^"]+"/, "VERSION = \"#{correct_version}\"")
    File.write(version_cr, updated)
    puts "  🔧 Fixed version.cr VERSION constant".colorize(:green)
  end
end

def validate_modules(fix_mode : Bool = false, detailed : Bool = false) : Array(ValidationResult)
  results = [] of ValidationResult
  
  %w[color cursor prompt reader screen spinner terminfo].each do |dir|
    module_path = File.join(Dir.current, dir)
    next unless File.directory?(module_path)
    
    module_name = "term-#{dir}"
    result = ValidationResult.new(module_name)
    
    # Get versions
    result.shard_version = get_shard_version(module_path)
    result.code_version = get_code_version(module_path, module_name)
    
    # Validate shard.yml exists and has version
    unless result.shard_version
      result.valid = false
      result.issues << "Missing or invalid version in shard.yml"
    end
    
    # Validate version.cr exists and has VERSION constant
    unless result.code_version
      result.valid = false
      result.issues << "Missing or invalid VERSION constant in version.cr"
    end
    
    # Compare versions if both exist
    if result.shard_version && result.code_version
      if result.shard_version != result.code_version
        result.valid = false
        result.issues << "Version mismatch: shard.yml(#{result.shard_version}) vs version.cr(#{result.code_version})"
        
        if fix_mode
          # Use shard.yml as source of truth
          fix_version_inconsistency(module_path, module_name, result.shard_version.not_nil!, "code")
          result.code_version = result.shard_version
          result.issues.pop # Remove the mismatch issue since we fixed it
          result.valid = true
        end
      end
    end
    
    # Validate version format
    if version = result.shard_version
      unless validate_version_format(version)
        result.valid = false
        result.issues << "Invalid version format: #{version} (should be X.Y.Z)"
      end
    end
    
    # Validate dependencies
    dependencies = get_dependencies(module_path)
    dependencies.each do |dep_name, dep_version|
      unless dep_version
        result.issues << "Dependency #{dep_name} missing version (using branch)"
      else
        unless validate_version_format(dep_version)
          result.valid = false
          result.issues << "Invalid dependency version format: #{dep_name}@#{dep_version}"
        end
      end
    end
    
    results << result
  end
  
  results
end

def print_results(results : Array(ValidationResult), detailed : Bool = false)
  puts "\n📊 Validation Results".colorize(:blue).bold
  puts "═" * 50
  
  valid_count = results.count(&.valid)
  total_count = results.size
  
  results.each do |result|
    status = result.valid ? "✅".colorize(:green) : "❌".colorize(:red)
    puts "\n#{status} #{result.module_name.colorize(:cyan)}"
    
    if detailed || !result.valid
      if shard_ver = result.shard_version
        puts "  📄 shard.yml: #{shard_ver.colorize(:blue)}"
      else
        puts "  📄 shard.yml: #{"MISSING".colorize(:red)}"
      end
      
      if code_ver = result.code_version
        puts "  💎 version.cr: #{code_ver.colorize(:blue)}"
      else
        puts "  💎 version.cr: #{"MISSING".colorize(:red)}"
      end
    end
    
    unless result.issues.empty?
      result.issues.each do |issue|
        puts "  ⚠️  #{issue.colorize(:yellow)}"
      end
    end
  end
  
  puts "\n" + "═" * 50
  if valid_count == total_count
    puts "🎉 All #{total_count} modules passed validation!".colorize(:green).bold
  else
    puts "⚠️  #{valid_count}/#{total_count} modules passed validation".colorize(:yellow).bold
    puts "Run with --fix to automatically resolve version inconsistencies".colorize(:blue)
  end
end

# Main execution
fix_mode = ARGV.includes?("--fix")
detailed = ARGV.includes?("--detailed")

if ARGV.includes?("--help")
  usage
  exit
end

puts "🔍 Validating module versions...".colorize(:yellow)

results = validate_modules(fix_mode, detailed)
print_results(results, detailed)

# Exit with error code if any validation failed
unless results.all?(&.valid)
  exit 1
end