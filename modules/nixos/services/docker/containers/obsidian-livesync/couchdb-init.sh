#!/bin/sh
set -eu

hostname="${COUCHDB_INTERNAL_URL:-http://couchdb:5984}"
username="${COUCHDB_USER:?COUCHDB_USER is required}"
password="${COUCHDB_PASSWORD:?COUCHDB_PASSWORD is required}"
database="${COUCHDB_DATABASE:-obsidiannotes}"

authenticated_curl() {
  curl -fsS --user "${username}:${password}" "$@"
}

until authenticated_curl "${hostname}/_up" | grep -q '"status":"ok"'; do
  sleep 2
done

# This returns 400 after the single-node cluster has already been configured.
# Treat that response as idempotent and continue applying the desired settings.
cluster_status="$(
  curl -sS -o /tmp/cluster-setup-response -w '%{http_code}' \
    --user "${username}:${password}" \
    -H 'Content-Type: application/json' \
    -X POST "${hostname}/_cluster_setup" \
    -d "{\"action\":\"enable_single_node\",\"username\":\"${username}\",\"password\":\"${password}\",\"bind_address\":\"0.0.0.0\",\"port\":5984,\"singlenode\":true}"
)"
case "${cluster_status}" in
  200|201|202|400) ;;
  *)
    cat /tmp/cluster-setup-response >&2
    exit 1
    ;;
esac

put_config() {
  section="$1"
  key="$2"
  value="$3"
  authenticated_curl \
    -H 'Content-Type: application/json' \
    -X PUT "${hostname}/_node/_local/_config/${section}/${key}" \
    -d "${value}" >/dev/null
}

put_config chttpd require_valid_user '"true"'
put_config chttpd_auth require_valid_user '"true"'
put_config httpd WWW-Authenticate '"Basic realm=\"couchdb\""'
put_config httpd enable_cors '"true"'
put_config chttpd enable_cors '"true"'
put_config chttpd max_http_request_size '"4294967296"'
put_config couchdb max_document_size '"50000000"'
put_config cors credentials '"true"'
put_config cors origins '"app://obsidian.md,capacitor://localhost,http://localhost"'

database_status="$(
  curl -sS -o /tmp/database-response -w '%{http_code}' \
    --user "${username}:${password}" \
    -X PUT "${hostname}/${database}"
)"
case "${database_status}" in
  201|202|412) ;;
  *)
    cat /tmp/database-response >&2
    exit 1
    ;;
esac

echo "CouchDB provisioning completed for ${database}."
