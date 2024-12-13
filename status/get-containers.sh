#!/bin/bash

TOKEN="${GITHUB_API_TOKEN:-}"
ORG_NAME="death-crab"

# Initialise the output structure
output='{"searchResult":[{"sourceName":"'"$ORG_NAME"'","packages":[],"containers":[]}]}'

# Step 1: Get all NuGet packages
packages=$(curl -s -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$ORG_NAME/packages?package_type=nuget" | jq -r '.[].name')

# Step 2: Process NuGet packages
for package in $packages; do
    versions=$(curl -s -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/orgs/$ORG_NAME/packages/nuget/$package/versions" | jq -r '.[].name')

    latest_release=""
    latest_prerelease=""
    latest_dev=""
    for version in $versions; do
        if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            latest_release=$version
        elif [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[a-zA-Z0-9]+$ ]]; then
            latest_prerelease=$version
        elif [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-g[a-f0-9]+$ ]]; then
            latest_dev=$version
        fi
    done
    latest_version=$latest_release
    [[ -z $latest_version ]] && latest_version=$latest_prerelease
    [[ -z $latest_version ]] && latest_version=$latest_dev

    output=$(echo $output | jq --arg id "$package" --arg version "$latest_version" \
        '.searchResult[0].packages += [{"id": $id, "latestVersion": $version}]')
done

# Step 3: Get all containers
containers=$(curl -s -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$ORG_NAME/packages?package_type=container" | jq -r '.[].name')

# Step 4: Process containers
for container in $containers; do
    tags=$(curl -s -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/orgs/$ORG_NAME/packages/container/$container/versions" | jq -r '.[0].metadata.container.tags[]')

    if [[ -z "$tags" ]]; then
        echo "Warning: No tags found for container $container"
        latest_tag="unknown"
    else
        latest_tag=$(echo "$tags" | head -n 1)
    fi

    # Append to containers array
    output=$(echo $output | jq --arg id "$container" --arg version "$latest_tag" \
        '.searchResult[0].containers += [{"id": $id, "latestVersion": $version}]')
done

echo $output | jq
