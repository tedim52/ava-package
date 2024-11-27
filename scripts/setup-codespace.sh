#!/bin/bash

set -euo pipefail
VERBOSE=false 
log() {
    echo "$1"
}

log_verbose() {
    if $VERBOSE; then
        echo "$1"
    fi
}

log_error() {
    echo "❌ Error: $1" >&2
    exit 1
}

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
		sleep 3
	done
	log_verbose "Docker is running."
}

setup_kurtosis() {
	log "🦢 Setting up Kurtosis..."
    sudo echo "deb [trusted=yes] https://apt.fury.io/kurtosis-tech/ /" | sudo tee /etc/apt/sources.list.d/kurtosis.list
    sudo apt update
    sudo apt install kurtosis-cli
    sudo kurtosis engine start
	log_verbose "Kurtosis is running."
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
    setup_kurtosis
    
	log "✅ Startup completed! Docker and Kurtosis CLI ready to go."
	exec bash
}

main "$@"