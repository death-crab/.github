#!/bin/bash

# Fail on any error and propagate errors through pipelines
set -e
set -o pipefail

# Use the environment variable GITHUB_API_TOKEN for the token
token="${GITHUB_API_TOKEN:-}"
echo "Token length: ${#GITHUB_API_TOKEN}"
ORG_NAME="death-crab"
BASE_URL="https://api.github.com/orgs/$ORG_NAME"

if [[ -z "$token" ]]; then
    echo "Error: GITHUB_API_TOKEN environment variable is not set" >&2
    exit 1
fi

# Function: api_call
api_call() {
    local path="$1"
    local response http_code response_body

    response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.github+json" \
        "$BASE_URL/$path")
    
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        echo "$response_body"
    else
        echo "Error: HTTP $http_code - $(echo "$response_body" | jq -r '.message // "Unknown error')" >&2
        echo "Full Response: $response_body" >&2 # Add this line for debugging
        exit 1
    fi
}

# Function: pick_latest_version
pick_latest_version() {
    local versions="$1"
    local latest_release=""
    local latest_prerelease=""
    local latest_dev=""

    for version in $versions; do
        if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            latest_release=$version
        elif [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[a-zA-Z0-9]+$ ]]; then
            latest_prerelease=$version
        elif [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-g[a-f0-9]+$ || $version =~ ^.+$ ]]; then
            latest_dev=$version
        fi
    done

    [[ -n $latest_release ]] && echo "$latest_release" && return
    [[ -n $latest_prerelease ]] && echo "$latest_prerelease" && return
    echo "$latest_dev"
}

# Function: process_packages
process_packages() {
    local packages
    packages=$(api_call "packages?package_type=nuget" | jq -r '.[].name')

    for package in $packages; do
        local versions
        versions=$(api_call "packages/nuget/$package/versions" | jq -r '.[].name')

        local latest_version
        latest_version=$(pick_latest_version "$versions")

        # Append to packages array
        output=$(echo "$output" | jq --arg id "$package" --arg version "$latest_version" \
            '.searchResult[0].packages += [{"id": $id, "latestVersion": $version}]')
    done
}

# Function: process_containers
process_containers() {
    local containers
    containers=$(api_call "packages?package_type=container" | jq -r '.[].name')

    for container in $containers; do
        local tags
        tags=$(api_call "packages/container/$container/versions" | jq -r '.[0].metadata.container.tags[]')

        if [[ -z "$tags" ]]; then
            echo "Warning: No tags found for container $container" >&2
            latest_tag="unknown"
        else
            latest_tag=$(pick_latest_version "$tags")
            # Skip invalid or "unknown" tags
            if [[ "$latest_tag" == "unknown" ]]; then
                echo "Warning: No valid tags found for container $container" >&2
                continue
            fi
        fi

        # Append to containers array
        output=$(echo "$output" | jq --arg id "$container" --arg version "$latest_tag" \
            '.searchResult[0].containers += [{"id": $id, "latestVersion": $version}]')
    done
}

# Main Script
output='{"searchResult":[{"sourceName":"'"$ORG_NAME"'","packages":[],"containers":[]}]}'

process_packages
process_containers

# Final Output
echo "$output" | jq
