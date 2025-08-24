#!/bin/bash

# Crystal-Term Version Propagation Script
# 
# This script reads the version from the root shard.yml and propagates it to all
# submodule shard.yml files, version.cr files, and inter-module dependencies.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}🚀 Crystal-Term Version Propagation${NC}"
echo "========================================"

# Read version from root shard.yml
if [[ ! -f "$ROOT_DIR/shard.yml" ]]; then
    echo -e "${RED}❌ Error: Root shard.yml not found at $ROOT_DIR/shard.yml${NC}"
    exit 1
fi

VERSION=$(awk '/^version:/ {print $2}' "$ROOT_DIR/shard.yml")
if [[ -z "$VERSION" ]]; then
    echo -e "${RED}❌ Error: Could not extract version from root shard.yml${NC}"
    exit 1
fi

echo -e "${GREEN}📦 Propagating version: $VERSION${NC}"

# Define modules
MODULES=("color" "cursor" "prompt" "reader" "screen" "spinner" "terminfo")

# Function to update shard.yml version
update_shard_version() {
    local module_dir="$1"
    local shard_file="$module_dir/shard.yml"
    
    if [[ ! -f "$shard_file" ]]; then
        echo -e "${YELLOW}⚠️  Warning: $shard_file not found${NC}"
        return 1
    fi
    
    # Create a temporary file to ensure atomic updates
    local temp_file="$shard_file.tmp"
    
    # Use awk to update only the version line, preserving everything else
    awk -v version="$VERSION" '
        /^version:/ { print "version: " version; next }
        { print }
    ' "$shard_file" > "$temp_file"
    
    # Only replace if the temp file was created successfully
    if [[ -s "$temp_file" ]]; then
        mv "$temp_file" "$shard_file"
        echo -e "${GREEN}  ✅ Updated $shard_file${NC}"
    else
        echo -e "${RED}  ❌ Failed to update $shard_file${NC}"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to update version.cr file
update_version_cr() {
    local module_dir="$1"
    local module_name="$2"
    local version_file="$module_dir/src/$module_name/version.cr"
    
    if [[ ! -f "$version_file" ]]; then
        echo -e "${YELLOW}⚠️  Warning: $version_file not found${NC}"
        return 1
    fi
    
    # Create a temporary file
    local temp_file="$version_file.tmp"
    
    # Use awk to update the VERSION constant, preserving everything else
    awk -v version="$VERSION" '
        /VERSION = "/ { 
            gsub(/VERSION = "[^"]*"/, "VERSION = \"" version "\"")
            print
            next
        }
        { print }
    ' "$version_file" > "$temp_file"
    
    # Only replace if the temp file was created successfully
    if [[ -s "$temp_file" ]]; then
        mv "$temp_file" "$version_file"
        echo -e "${GREEN}  ✅ Updated $version_file${NC}"
    else
        echo -e "${RED}  ❌ Failed to update $version_file${NC}"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to update inter-module dependencies
update_dependencies() {
    local module_dir="$1"
    local shard_file="$module_dir/shard.yml"
    
    if [[ ! -f "$shard_file" ]]; then
        return 1
    fi
    
    # Check if this shard has crystal-term dependencies
    local has_dependencies=false
    
    for dep_module in "${MODULES[@]}"; do
        local dep_name="term-$dep_module"
        
        # Check if this dependency exists in the shard.yml
        if grep -q "^  $dep_name:" "$shard_file"; then
            has_dependencies=true
            
            # Update the dependency to use version instead of branch
            # This is a multi-step process:
            # 1. Find the dependency block
            # 2. Replace branch: master with version: $VERSION
            # 3. Or update existing version: line
            
            # Use awk to handle the complex YAML structure
            awk -v dep="$dep_name" -v version="$VERSION" '
            BEGIN { in_dep = 0; in_dep_block = 0 }
            
            # Detect dependency start
            $0 ~ "^  " dep ":" {
                in_dep = 1
                in_dep_block = 1
                print $0
                next
            }
            
            # Inside dependency block
            in_dep_block && /^    / {
                if (/^    branch:/) {
                    # Replace branch with version
                    print "    version: " version
                    next
                } else if (/^    version:/) {
                    # Update existing version
                    print "    version: " version
                    next
                } else {
                    print $0
                    next
                }
            }
            
            # End of dependency block (non-indented line or different dependency)
            in_dep_block && !/^    / && !/^$/ {
                in_dep = 0
                in_dep_block = 0
                print $0
                next
            }
            
            # Default: print line as-is
            { print $0 }
            ' "$shard_file" > "$shard_file.tmp" && mv "$shard_file.tmp" "$shard_file"
            
            echo -e "${GREEN}  ✅ Updated dependency $dep_name to version $VERSION${NC}"
        fi
    done
    
    if [[ "$has_dependencies" == "true" ]]; then
        echo -e "${BLUE}  🔗 Updated inter-module dependencies${NC}"
    fi
}

# Process each module
for module in "${MODULES[@]}"; do
    module_dir="$ROOT_DIR/$module"
    
    if [[ ! -d "$module_dir" ]]; then
        echo -e "${YELLOW}⚠️  Warning: Module directory $module_dir not found${NC}"
        continue
    fi
    
    echo -e "\n${YELLOW}📁 Processing module: term-$module${NC}"
    
    # Update shard.yml version
    update_shard_version "$module_dir"
    
    # Update version.cr file
    update_version_cr "$module_dir" "$module"
    
    # Update inter-module dependencies
    update_dependencies "$module_dir"
done

echo -e "\n${GREEN}🎉 Version propagation completed successfully!${NC}"
echo -e "${BLUE}📋 Summary:${NC}"
echo -e "  Version: ${GREEN}$VERSION${NC}"
echo -e "  Modules updated: ${GREEN}${#MODULES[@]}${NC}"

echo -e "\n${YELLOW}📝 Next steps:${NC}"
echo "  1. Review the changes: git diff"
echo "  2. Test the modules with the new version"
echo "  3. Commit changes: git add . && git commit -m \"Release v$VERSION\""
echo "  4. Push to trigger GitHub Actions: git push"