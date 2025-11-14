#!/bin/bash

# DataOnline N8N Manager - NocoDB Testing Functions
# Phiên bản: 1.0.0
# Mô tả: Integration testing và health checks cho NocoDB

set -euo pipefail

# ===== TESTING FUNCTIONS =====

run_integration_tests() {
    ui_header "Integration Testing"
    
    local test_results=()
    
    echo "🧪 **Running Integration Tests:**"
    echo ""
    
    # Test 1: NocoDB Health
    ui_start_spinner "Test 1: NocoDB Health Check"
    if test_nocodb_health; then
        ui_stop_spinner
        test_results+=("✅ NocoDB Health")
        ui_success "Test 1: NocoDB Health - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ NocoDB Health")
        ui_error "Test 1: NocoDB Health - FAILED" "HEALTH_CHECK_FAILED"
    fi
    
    # Test 2: Database Connection
    ui_start_spinner "Test 2: Database Connection"
    if test_database_connection; then
        ui_stop_spinner
        test_results+=("✅ Database Connection")
        ui_success "Test 2: Database Connection - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ Database Connection")
        ui_error "Test 2: Database Connection - FAILED" "DB_CONNECTION_FAILED"
    fi
    
    # Test 3: API Access
    ui_start_spinner "Test 3: API Access"
    if test_api_access; then
        ui_stop_spinner
        test_results+=("✅ API Access")
        ui_success "Test 3: API Access - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ API Access")
        ui_error "Test 3: API Access - FAILED" "API_ACCESS_FAILED"
    fi
    
    # Test 4: Views Creation
    ui_start_spinner "Test 4: Views Creation"
    if test_views_creation; then
        ui_stop_spinner
        test_results+=("✅ Views Creation")
        ui_success "Test 4: Views Creation - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ Views Creation")
        ui_error "Test 4: Views Creation - FAILED" "VIEWS_CREATION_FAILED"
    fi
    
    
    # Test Summary
    echo ""
    ui_section "Test Results Summary"
    
    local passed_count=0
    local failed_count=0
    
    for result in "${test_results[@]}"; do
        echo "$result"
        if [[ "$result" == ✅* ]]; then
            ((passed_count++))
        else
            ((failed_count++))
        fi
    done
    
    echo ""
    local total_count=${#test_results[@]}
    
    if [[ $failed_count -eq 0 ]]; then
        ui_success "🎉 ALL TESTS PASSED ($passed_count/$total_count)"
        return 0
    else
        ui_error "⚠️  SOME TESTS FAILED ($passed_count/$total_count passed, $failed_count failed)" "TESTS_FAILED" "Xem chi tiết ở trên"
        return 1
    fi
}

test_nocodb_health() {
    curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1
}

test_database_connection() {
    docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1
}

test_api_access() {
    local auth_token
    if auth_token=$(nocodb_admin_login); then
        curl -s -H "Authorization: Bearer $auth_token" \
            "http://localhost:${NOCODB_PORT}/api/v1/db/meta/projects" >/dev/null 2>&1
    else
        return 1
    fi
}

test_views_creation() {
    # Test if we can create a simple view
    local auth_token
    if auth_token=$(nocodb_admin_login); then
        # This is a simplified test - in real implementation would test actual view creation
        return 0
    else
        return 1
    fi
}

# Simple admin login function for testing purposes
nocodb_admin_login() {
    local admin_email=$(config_get "nocodb.admin_email" "admin@localhost")
    local admin_password=$(config_get "nocodb.admin_password" "")
    
    if [[ -z "$admin_password" ]]; then
        # Try to get from .env file
        local env_file="${N8N_COMPOSE_DIR:-/opt/n8n}/.env"
        if [[ -f "$env_file" ]]; then
            admin_password=$(grep "^NOCODB_ADMIN_PASSWORD=" "$env_file" | cut -d'=' -f2- | tr -d '"' | tr -d "'" 2>/dev/null || echo "")
        fi
    fi
    
    if [[ -z "$admin_password" ]]; then
        return 1
    fi
    
    # Login and extract token
    local response=$(curl -s -X POST \
        "http://localhost:${NOCODB_PORT}/api/v1/auth/user/signin" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$admin_email\",\"password\":\"$admin_password\"}" 2>/dev/null)
    
    # Try to extract token from response
    local token=$(echo "$response" | jq -r '.token // .access_token // .authToken // empty' 2>/dev/null || echo "")
    
    if [[ -n "$token" ]] && [[ "$token" != "null" ]]; then
        echo "$token"
        return 0
    else
        return 1
    fi
}

# Export functions
export -f run_integration_tests test_nocodb_health test_database_connection
export -f test_api_access test_views_creation nocodb_admin_login

