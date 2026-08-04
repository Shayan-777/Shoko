#!/bin/sh

set -u

engine=${1:-}
failures=0

if [ -z "$engine" ] || [ ! -x "$engine" ]; then
  echo "protocol_test: expected an executable engine path" >&2
  exit 2
fi

fail() {
  name=$1
  expected=$2
  actual=$3
  echo "protocol_test: $name" >&2
  echo "  expected: $expected" >&2
  echo "  actual:   $actual" >&2
  failures=$((failures + 1))
}

assert_response() {
  name=$1
  request=$2
  expected=$3
  actual=$(printf '%s\n' "$request" | "$engine")
  [ "$actual" = "$expected" ] || fail "$name" "$expected" "$actual"
}

ping='{"ok":true,"version":"1.1.0","max_slots":4}'
malformed='{"ok":false,"code":"malformed_json","error":"request must be a flat JSON object with string values"}'

assert_response 'ping' '{"op":"ping"}' "$ping"
assert_response 'unicode escape in operation' '{"op":"\u0070ing"}' "$ping"
assert_response 'missing operation' '{}' \
  '{"ok":false,"code":"invalid_request","error":"missing op"}'
assert_response 'unknown operation' '{"op":"dance"}' \
  '{"ok":false,"code":"unknown_operation","error":"unknown op"}'
assert_response 'duplicate field' '{"op":"ping","op":"ping"}' "$malformed"
assert_response 'unknown field' '{"op":"ping","typo":"value"}' "$malformed"
assert_response 'non-string value' '{"op":"ping","slot":1}' "$malformed"
assert_response 'trailing content' '{"op":"ping"} false' "$malformed"
assert_response 'unpaired surrogate' '{"op":"\uD800"}' "$malformed"
assert_response 'translate requires text' '{"op":"translate","slot":"missing"}' \
  '{"ok":false,"code":"invalid_request","error":"translate requires slot and text"}'
assert_response 'translate requires a loaded model' \
  '{"op":"translate","slot":"missing","text":"hello"}' \
  '{"ok":false,"code":"model_not_loaded","error":"model is not loaded"}'
assert_response 'unload requires a slot' '{"op":"unload"}' \
  '{"ok":false,"code":"invalid_request","error":"unload requires slot"}'
assert_response 'unloading an absent slot is idempotent' '{"op":"unload","slot":"missing"}' \
  '{"ok":true}'
assert_response 'load validates required fields' '{"op":"load","slot":"test"}' \
  '{"ok":false,"code":"invalid_request","error":"load requires slot, model and vocab"}'
assert_response 'load reports a missing model' \
  '{"op":"load","slot":"test","model":"/dev/null/shoko-model","vocab":"/dev/null/shoko-vocab"}' \
  '{"ok":false,"code":"model_load_failed","error":"cannot open model file"}'

actual=$(printf '{"op":"ping"}\r\n' | "$engine")
[ "$actual" = "$ping" ] || fail 'CRLF request' "$ping" "$actual"

actual=$(printf '%s' '{"op":"ping"}' | "$engine")
[ "$actual" = "$ping" ] || fail 'final request without newline' "$ping" "$actual"

expected=$(printf '%s\n%s\n%s' "$ping" "$malformed" "$ping")
actual=$(printf '%s\n%s\n%s\n' '{"op":"ping"}' 'not-json' '{"op":"ping"}' | "$engine")
[ "$actual" = "$expected" ] || fail 'malformed request recovery' "$expected" "$actual"

too_large='{"ok":false,"code":"request_too_large","error":"request too large"}'
expected=$(printf '%s\n%s' "$too_large" "$ping")
actual=$(
  awk 'BEGIN {
    printf "{\"op\":\"";
    for (i = 0; i < 1048580; i++) printf "x";
    print "\"}";
    print "{\"op\":\"ping\"}";
  }' | "$engine"
)
[ "$actual" = "$expected" ] || fail 'oversized request recovery' "$expected" "$actual"

if [ "$failures" -ne 0 ]; then
  echo "protocol_test: $failures failure(s)" >&2
  exit 1
fi

echo 'Protocol tests passed'
