#!/bin/bash

set -euo pipefail

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

run_command_with_spinner() {
    if $VERBOSE; then
        "$@"
    else
        "$@" >/dev/null 2>&1 &
        local pid=$!
        spinner $pid
        wait $pid
        return $?
    fi
}

setup_docker() {
	log "🐳 Setting up Docker..."
	while ! run_command_with_spinner docker info; do
		sleep 1
	done
	log_verbose "Docker is running."
	sleep 3
}

main() {
	# Check if an argument is provided
	if [ $# -gt 0 ] && [ "$1" = "--verbose" ]; then
		VERBOSE=true
		log "Verbose mode enabled."
	fi

	log "🕰️ This can take around 3 minutes! Familiarize yourself with the repository while this happens."

	setup_docker

	log "✅ Startup completed! Docker and Kurtosis CLI ready to go."
	exec bash
}

main "$@"