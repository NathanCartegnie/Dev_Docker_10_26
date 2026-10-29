#!/bin/bash
# Comptes du registre : ci (push) et dev (pull), mots de passe en bcrypt
set -e
cd "$(dirname "$0")"
mkdir -p auth
docker run --rm --entrypoint htpasswd httpd:2 -Bbn ci ci-push-2024 > auth/htpasswd
docker run --rm --entrypoint htpasswd httpd:2 -Bbn dev dev-pull-2024 >> auth/htpasswd
