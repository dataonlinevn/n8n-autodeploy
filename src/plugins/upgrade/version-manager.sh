#!/bin/bash

# DataOnline N8N Manager - Version Manager Module
# Phiên bản: 1.0.0
# Quản lý phiên bản N8N, kiểm tra nâng cấp, và thông tin phát hành

set -euo pipefail

# ===== VERSION DETECTION =====

get_current_n8n_version() {
    local version=""

    # Method 1: From running container (most accurate)
    if docker ps --format '{{.Names}}' | grep -q "n8n"; then
        local container_name=$(docker ps --format '{{.Names}}' | grep "n8n" | head -1)
        version=$(docker exec "$container_name" n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    # Method 2: From N8N API
    local n8n_port=$(config_get "n8n.port" "5678")
    if curl -s "http://localhost:$n8n_port/rest/settings" >/dev/null 2>&1; then
        version=$(curl -s "http://localhost:$n8n_port/rest/settings" | jq -r '.n8nMetadata.version' 2>/dev/null)
        if [[ -n "$version" && "$version" != "null" ]]; then
            echo "$version"
            return 0
        fi
    fi

    # Method 3: From image tag
    if docker ps --format '{{.Names}}' | grep -q "n8n"; then
        version=$(docker inspect n8n --format '{{.Config.Image}}' 2>/dev/null | cut -d':' -f2)
        if [[ -n "$version" && "$version" != "latest" ]]; then
            echo "$version"
            return 0
        fi
    fi

    echo "unknown"
    return 1
}

# ===== DOCKERHUB API INTEGRATION =====

get_available_versions() {
    local limit="${1:-5}"

    # Use provided command to get versions
    if command_exists curl && command_exists jq; then
        curl -s "https://hub.docker.com/v2/repositories/n8nio/n8n/tags/?page_size=100" |
            jq -r '.results[].name' |
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
            sort -V -r |
            head -"$limit"
    else
        # Fallback versions
        echo "1.99.1"
        echo "1.99.0"
        echo "1.98.2"
        echo "1.98.1"
        echo "1.98.0"
    fi
}

show_available_versions() {
    ui_section "Các phiên bản N8N có sẵn"

    ui_start_spinner "Lấy danh sách phiên bản từ DockerHub"
    local versions=($(get_available_versions 15))
    ui_stop_spinner

    if [[ ${#versions[@]} -eq 0 ]]; then
        ui_status "error" "Không thể lấy danh sách phiên bản"

        # Show fallback versions
        echo "📋 Một số phiên bản phổ biến:"
        echo "   1. 1.99.1"
        echo "   2. 1.99.0"
        echo "   3. 1.98.2"
        echo "   4. latest"
        return 1
    fi

    echo "📋 ${#versions[@]} phiên bản mới nhất:"
    for i in "${!versions[@]}"; do
        local version="${versions[$i]}"
        local status=""

        if [[ "$version" == "$CURRENT_VERSION" ]]; then
            status=" ${UI_GREEN}(hiện tại)${UI_NC}"
        fi

        echo "   $((i + 1)). $version$status"
    done
    echo ""
}

# ===== VERSION COMPARISON =====

compare_versions() {
    local version1="$1"
    local version2="$2"

    # Simple semantic version comparison
    local IFS='.'
    local ver1=($version1) ver2=($version2)

    # Compare major version
    if [[ ${ver1[0]} -gt ${ver2[0]} ]]; then
        echo "newer"
    elif [[ ${ver1[0]} -lt ${ver2[0]} ]]; then
        echo "older"
    else
        # Compare minor version
        if [[ ${ver1[1]} -gt ${ver2[1]} ]]; then
            echo "newer"
        elif [[ ${ver1[1]} -lt ${ver2[1]} ]]; then
            echo "older"
        else
            # Compare patch version
            if [[ ${ver1[2]} -gt ${ver2[2]} ]]; then
                echo "newer"
            elif [[ ${ver1[2]} -lt ${ver2[2]} ]]; then
                echo "older"
            else
                echo "same"
            fi
        fi
    fi
}

is_version_newer() {
    local current="$1"
    local target="$2"

    local comparison=$(compare_versions "$target" "$current")
    [[ "$comparison" == "newer" ]]
}

# ===== BREAKING CHANGES DETECTION =====

check_breaking_changes() {
    local from_version="$1"
    local to_version="$2"

    ui_section "Kiểm tra breaking changes"

    # Known breaking changes (can be expanded)
    local breaking_versions=("1.0.0" "0.200.0" "0.190.0")
    local has_breaking=false

    for breaking_ver in "${breaking_versions[@]}"; do
        if is_version_in_range "$from_version" "$to_version" "$breaking_ver"; then
            ui_status "warning" "⚠️  Breaking change ở v$breaking_ver"
            has_breaking=true
        fi
    done

    if [[ "$has_breaking" == "true" ]]; then
        ui_warning_box "Cảnh báo Breaking Changes" \
            "Phiên bản này có thể không tương thích ngược" \
            "Khuyến nghị backup đầy đủ trước khi nâng cấp" \
            "Kiểm tra workflows sau khi upgrade"

        return $(ui_confirm "Tiếp tục với rủi ro breaking changes?")
    else
        ui_status "success" "Không có breaking changes đã biết"
        return 0
    fi
}

is_version_in_range() {
    local from="$1"
    local to="$2"
    local check="$3"

    local from_check=$(compare_versions "$check" "$from")
    local to_check=$(compare_versions "$to" "$check")

    # Check if version is between from and to
    [[ ("$from_check" == "newer" || "$from_check" == "same") && ("$to_check" == "newer" || "$to_check" == "same") ]]
}

# ===== RELEASE INFORMATION =====

get_release_info() {
    local version="$1"
    local temp_file="/tmp/n8n_release_$version.json"

    # Try GitHub API for release notes
    if curl -s "https://api.github.com/repos/n8n-io/n8n/releases/tags/n8n@$version" >"$temp_file" 2>/dev/null; then
        if command_exists jq && jq -e '.body' "$temp_file" >/dev/null 2>&1; then
            local release_date=$(jq -r '.published_at' "$temp_file" | cut -d'T' -f1)
            local release_notes=$(jq -r '.body' "$temp_file" | head -n 5)

            echo "📅 Ngày phát hành: $release_date"
            echo "📝 Release notes (5 dòng đầu):"
            echo "$release_notes" | sed 's/^/   /'

            rm -f "$temp_file"
            return 0
        fi
    fi

    rm -f "$temp_file"
    echo "ℹ️  Không có thông tin release cho v$version"
    return 1
}

# ===== VERSION VALIDATION =====

validate_version_exists() {
    local version="$1"

    if [[ "$version" == "latest" ]]; then
        return 0
    fi

    ui_start_spinner "Kiểm tra phiên bản $version"

    # Check if version exists on DockerHub
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags/$version/")

    ui_stop_spinner

    if [[ "$status_code" == "200" ]]; then
        ui_status "success" "Phiên bản $version tồn tại"
        return 0
    else
        ui_status "error" "Phiên bản $version không tồn tại"
        return 1
    fi
}

# ===== UPGRADE TYPE DETECTION =====

get_upgrade_type() {
    local from="$1"
    local to="$2"

    # Skip if either version is unknown
    if [[ "$from" == "unknown" || "$to" == "unknown" ]]; then
        echo "unknown"
        return
    fi

    local comparison=$(compare_versions "$to" "$from")

    case "$comparison" in
    "newer")
        local IFS='.'
        local from_parts=($from) to_parts=($to)

        # Major version change
        if [[ ${to_parts[0]} -gt ${from_parts[0]} ]]; then
            echo "major"
        # Minor version change
        elif [[ ${to_parts[1]} -gt ${from_parts[1]} ]]; then
            echo "minor"
        # Patch version change
        else
            echo "patch"
        fi
        ;;
    "older")
        echo "downgrade"
        ;;
    "same")
        echo "reinstall"
        ;;
    esac
}

# ===== VERSION DISPLAY HELPERS =====

format_version_info() {
    local version="$1"
    local is_current="${2:-false}"

    local info="$version"

    if [[ "$is_current" == "true" ]]; then
        info="$info ${UI_GREEN}(hiện tại)${UI_NC}"
    fi

    # Add release date if available
    local release_date=$(get_version_release_date "$version")
    if [[ -n "$release_date" ]]; then
        info="$info - $release_date"
    fi

    echo "$info"
}

get_version_release_date() {
    local version="$1"

    # Try to get from GitHub API
    local release_data=$(curl -s "https://api.github.com/repos/n8n-io/n8n/releases/tags/n8n@$version" 2>/dev/null)

    if [[ -n "$release_data" ]] && command_exists jq; then
        echo "$release_data" | jq -r '.published_at' 2>/dev/null | cut -d'T' -f1
    fi
}

# ===== VERSION FILTERING =====

filter_stable_versions() {
    local versions=("$@")
    local stable_versions=()

    for version in "${versions[@]}"; do
        # Skip pre-release versions (those with alpha, beta, rc, etc.)
        if [[ ! "$version" =~ (alpha|beta|rc|pre|dev) ]]; then
            stable_versions+=("$version")
        fi
    done

    printf '%s\n' "${stable_versions[@]}"
}

get_lts_versions() {
    # N8N doesn't have official LTS, but we can consider stable major versions
    local versions=($(get_available_versions 20))
    local lts_versions=()
    local seen_major=()

    for version in "${versions[@]}"; do
        local major=$(echo "$version" | cut -d'.' -f1)

        # Take first (latest) version of each major release
        if [[ ! " ${seen_major[*]} " =~ " $major " ]]; then
            lts_versions+=("$version")
            seen_major+=("$major")
        fi

        # Limit to 5 LTS versions
        if [[ ${#lts_versions[@]} -ge 5 ]]; then
            break
        fi
    done

    printf '%s\n' "${lts_versions[@]}"
}

# ===== EXPORT FUNCTIONS =====

export -f get_current_n8n_version get_available_versions show_available_versions
export -f compare_versions is_version_newer check_breaking_changes
export -f get_release_info validate_version_exists get_upgrade_type
export -f format_version_info filter_stable_versions get_lts_versions
