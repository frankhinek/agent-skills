#!/usr/bin/env bash
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/verification-check.sh" verify-valid
