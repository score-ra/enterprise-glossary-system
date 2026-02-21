#!/usr/bin/env bash
# Generate htpasswd files for Nginx basic auth.
#
# Usage:
#   ./scripts/setup-auth.sh
#
# Creates two htpasswd files:
#   config/nginx/auth/htpasswd       -- editors + admins (write access)
#   config/nginx/auth/htpasswd-admin -- admins only (admin access)
#
# Environment variables:
#   EGMS_ADMIN_USER  - Admin username (default: admin)
#   EGMS_ADMIN_PASS  - Admin password (default: prompt or env)
#   EGMS_EDITOR_USER - Editor username (default: editor)
#   EGMS_EDITOR_PASS - Editor password (default: prompt or env)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTH_DIR="$PROJECT_DIR/config/nginx/auth"

mkdir -p "$AUTH_DIR"

ADMIN_USER="${EGMS_ADMIN_USER:-admin}"
ADMIN_PASS="${EGMS_ADMIN_PASS:-}"
EDITOR_USER="${EGMS_EDITOR_USER:-editor}"
EDITOR_PASS="${EGMS_EDITOR_PASS:-}"

# Generate password if not provided
if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS="admin-$(date +%s | sha256sum | head -c 12)"
    echo "Generated admin password: $ADMIN_PASS"
fi

if [ -z "$EDITOR_PASS" ]; then
    EDITOR_PASS="editor-$(date +%s | sha256sum | head -c 12)"
    echo "Generated editor password: $EDITOR_PASS"
fi

# Check for htpasswd or openssl
if command -v htpasswd > /dev/null 2>&1; then
    # Use htpasswd (from apache2-utils)
    htpasswd -cb "$AUTH_DIR/htpasswd" "$ADMIN_USER" "$ADMIN_PASS"
    htpasswd -b "$AUTH_DIR/htpasswd" "$EDITOR_USER" "$EDITOR_PASS"
    htpasswd -cb "$AUTH_DIR/htpasswd-admin" "$ADMIN_USER" "$ADMIN_PASS"
elif command -v openssl > /dev/null 2>&1; then
    # Fallback: use openssl for password hashing
    ADMIN_HASH=$(openssl passwd -apr1 "$ADMIN_PASS")
    EDITOR_HASH=$(openssl passwd -apr1 "$EDITOR_PASS")

    echo "$ADMIN_USER:$ADMIN_HASH" > "$AUTH_DIR/htpasswd"
    echo "$EDITOR_USER:$EDITOR_HASH" >> "$AUTH_DIR/htpasswd"
    echo "$ADMIN_USER:$ADMIN_HASH" > "$AUTH_DIR/htpasswd-admin"
else
    echo "ERROR: Neither htpasswd nor openssl found. Install apache2-utils or openssl." >&2
    exit 1
fi

echo ""
echo "Auth files created:"
echo "  $AUTH_DIR/htpasswd        (editors + admins)"
echo "  $AUTH_DIR/htpasswd-admin  (admins only)"
echo ""
echo "Roles:"
echo "  $ADMIN_USER  -- full admin access (read + write + admin)"
echo "  $EDITOR_USER -- editor access (read + write)"
echo "  (anonymous)  -- read-only access (SKOSMOS UI + SPARQL queries)"
