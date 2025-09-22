#!/bin/bash

# Default values
site_name=""
count=5
all_sites=false
site_type=""
sites=("Sa" "Ay" "Li" "St" "Ig" "Skuast" "Test" "Shey" "Shey2" "Office" "Larjes")

# Add test site and Skuast site
site_type_override=false

# Site name mappings
declare -A site_names=(
  ["Sa"]="Sakti"
  ["Ay"]="Ayee"
  ["Li"]="Likir"
  ["Stakmo"]="Stakmo"
  ["Ig"]="Igoo"
  ["Skuast"]="Skuast"
  ["Test"]="Test"
  ["Office"]="Office"
  ["Shey"]="Shey"
  ["Shey_2"]="Shey2"
  ["Surya"]="Surya"
  ["Nidhin"]="Nidhin"
)

# Default site types
declare -A site_types=(
  ["Ay"]="air"
  ["Li"]="air"
  ["Stakmo"]="air"
  ["Sakti"]="air"
  ["Surya"]="air"
  ["Nidhin"]="air"
  ["Ig"]="air"
  ["Shey"]="air"
  ["Shey_2"]="air"
  ["Skuast"]="drip"
  ["Test"]="drip"
  ["Office"]="drip"
  ["Larjes"]="drip"
)

# Parse command line arguments
while getopts "s:n:at:" opt; do
  case $opt in
  s) site_name="$OPTARG" ;;
  n) count="$OPTARG" ;;
  a) all_sites=true ;;
  t)
    site_type="$OPTARG"
    site_type_override=true
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    exit 1
    ;;
  esac
done

# Function to handle null values
handle_null() {
  local value="$1"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "null"
  else
    echo "$value"
  fi
}

# Function to query a single AIR site
query_air_site() {
  local site=$1
  aws dynamodb query \
    \
    --table-name AIRTable \
    --key-condition-expression "site_name = :s" \
    --expression-attribute-values "{\":s\": {\"S\": \"$site\"}}" \
    --limit $count \
    --no-scan-index-forward | # --table-name AIRDynamoTable \
    jq -r '.Items | map([
        .timestamp.S // "null",
        .temperature.N // "null",
        .water_temp.N // "null",
        .discharge.N // "null",
        .pressure.N // "null",
        .counter.N // "null"
    ]) | .[] | @tsv'
}

# Function to query a single drip irrigation site
query_drip_site() {
  local site=$1
  aws dynamodb query \
    --table-name DripTable \
    --key-condition-expression "site_name = :s" \
    --expression-attribute-values "{\":s\": {\"S\": \"$site\"}}" \
    --limit $count \
    --no-scan-index-forward |
    jq -r '.Items | map([
        .timestamp.S // "null",
        .soil_1.N // "null",
        .soil_2.N // "null",
        .temperature.N // "null",
        .discharge.N // "null",
        .pressure.N // "null",
        .counter.N // "null"
    ]) | .[] | @tsv'
}

# Function to query a single site based on site_type
query_site() {
  local site=$1
  local current_site_type

  # Determine site type - use override if provided, otherwise use default
  if [ "$site_type_override" = true ]; then
    current_site_type="$site_type"
  else
    current_site_type=${site_types[$site]}
  fi

  if [ "$current_site_type" = "air" ]; then
    query_air_site "$site"
  else
    query_drip_site "$site"
  fi
}

# Function to print site data with header
print_site_data() {
  local site=$1
  local data=$2
  local full_name=${site_names[$site]}
  local current_site_type

  # Determine site type - use override if provided, otherwise use default
  if [ "$site_type_override" = true ]; then
    current_site_type="$site_type"
  else
    current_site_type=${site_types[$site]}
  fi

  # Print site header with decoration and full name
  echo "=== Site: $full_name ($site) [${current_site_type}] ==="

  if [ "$current_site_type" = "air" ]; then
    # Print AIR headers with fixed widths
    printf "%-25s %-8s %-8s %-12s %-16s %-8s\n" \
      "TIMESTAMP" "TEMP" "WATER" "FLOW" "PRESS" "COUNTER"

    # Print separator line
    printf "%s\n" "$(printf '=%.0s' {1..85})"

    # Format and print AIR data
    while IFS=$'\t' read -r timestamp temp water_temp discharge pressure counter; do
      # Handle null values for each field
      timestamp=$(handle_null "$timestamp")
      temp=$(handle_null "$temp")
      water_temp=$(handle_null "$water_temp")
      discharge=$(handle_null "$discharge")
      pressure=$(handle_null "$pressure")
      counter=$(handle_null "$counter")

      printf "%-25s %-8s %-8s %-12s %-16s %-8s\n" \
        "$timestamp" "$temp" "$water_temp" "$discharge" "$pressure" "$counter"
    done <<<"$data"
  else
    # Print drip irrigation headers with fixed widths
    printf "%-25s %-8s %-8s %-8s %-12s %-10s %-8s\n" \
      "TIMESTAMP" "SOIL_1" "SOIL_2" "TEMP" "FLOW" "PRESS" "COUNTER"

    # Print separator line
    printf "%s\n" "$(printf '=%.0s' {1..85})"

    # Format and print drip irrigation data
    while IFS=$'\t' read -r timestamp soil_1 soil_2 temp discharge pressure counter; do
      # Handle null values for each field
      timestamp=$(handle_null "$timestamp")
      soil_1=$(handle_null "$soil_1")
      soil_2=$(handle_null "$soil_2")
      temp=$(handle_null "$temp")
      discharge=$(handle_null "$discharge")
      pressure=$(handle_null "$pressure")
      counter=$(handle_null "$counter")

      printf "%-25s %-8s %-8s %-8s %-12s %-10s %-8s\n" \
        "$timestamp" "$soil_1" "$soil_2" "$temp" "$discharge" "$pressure" "$counter"
    done <<<"$data"
  fi

  echo -e "\n" # Add extra newline for spacing between sites
}

# Check if either site name or all flag is provided
if [ -z "$site_name" ] && [ "$all_sites" = false ]; then
  echo "Usage: $0 (-s <site_name> | -a) [-n <count>] [-t <site_type>]"
  echo "Options:"
  echo "  -s <site_name>  Query specific site"
  echo "  -a              Query all sites (Sa, Ay, Li, St, Ig, Skuast, Test, Office, Larjes)"
  echo "  -n <count>      Number of records per site (default: 5)"
  echo "  -t <site_type>  Override site type: 'air' or 'drip' (otherwise uses default for each site)"
  echo "Site Types:"
  echo "  Air sites: Sa (Sakti), Ay (Ayee), Li (Likir), St (Stakmo), Ig (Igoo)"
  echo "  Drip sites: Skuast, Test, Office, Larjes"
  echo "Example: $0 -s Sa -n 10"
  echo "         $0 -a"
  echo "         $0 -s Skuast -t air  # Override default type for Skuast"
  exit 1
fi

# If all_sites flag is true, query all sites
if [ "$all_sites" = true ]; then
  for site in "${sites[@]}"; do
    site_data=$(query_site "$site")
    print_site_data "$site" "$site_data"
  done
else
  # Query single site
  site_data=$(query_site "$site_name")
  print_site_data "$site_name" "$site_data"
fi
