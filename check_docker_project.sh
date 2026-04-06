#!/usr/bin/env bash
# check_docker_project.sh — List running devcontainer projects

printf "\n%-14s %-12s %-50s\n" "CONTAINER" "STATUS" "PROJECT"
printf "%-14s %-12s %-50s\n" "─────────────" "───────────" "──────────────────────────────────────────────────"

docker ps --format '{{.ID}}\t{{.Status}}\t{{.Label "devcontainer.local_folder"}}' | while IFS=$'\t' read -r id status folder; do
  if [[ -n "$folder" ]]; then
    project=$(basename "$folder")
    printf "%-14s %-12s %s (%s)\n" "${id:0:12}" "$status" "$project" "$folder"
  else
    printf "%-14s %-12s %s\n" "${id:0:12}" "$status" "(not a devcontainer)"
  fi
done

echo ""
