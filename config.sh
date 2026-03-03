#!/bin/bash
# ══════════════════════════════════════════════════════════════════
# Sandbox Guard Configuration
# ══════════════════════════════════════════════════════════════════
# Edit this file to customize your guard behavior.
# This file is sourced by sandbox-guard.sh on every invocation.

# SAFE_ZONE: Your development directory where destructive ops are ALLOWED.
# The guard treats this directory as "contained" — git can restore anything here.
# Examples:
#   Git Bash on Windows: /e/Projects
#   macOS:               /Users/you/dev
#   Linux:               /home/you/projects
SAFE_ZONE="/e/"
