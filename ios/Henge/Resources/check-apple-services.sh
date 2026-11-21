#!/bin/bash
# Run manually INSIDE the macOS guest. No sign-in, cookies, credentials, account
# databases, HTTP bodies, identity serials or raw unified-log messages collected.
set -u
export LC_ALL=C
printf 'Henge guest transport check v1\n'
printf 'macOS='; /usr/bin/sw_vers -productVersion
printf 'macOS_build='; /usr/bin/sw_vers -buildVersion
printf 'architecture='; /usr/bin/uname -m
printf 'guest_utc='; /bin/date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'default_ipv4_route='
if /sbin/route -n get default >/dev/null 2>&1; then printf 'present\n'; else printf 'missing\n'; fi

for host in account.apple.com idmsa.apple.com apps.apple.com; do
    printf 'endpoint=%s ' "$host"
    # Only success/failure, never the local resolver configuration or IPs.
    if /usr/bin/dscacheutil -q host -a name "$host" | /usr/bin/grep -q 'ip_address:'; then
        printf 'dns=ok '
    else
        printf 'dns=no_ipv4_answer '
    fi
    # -q disables user curlrc, proxy is bypassed, no redirects, headers, body,
    # cookie jar or auth arguments. Normal certificate verification stays on.
    result=$(/usr/bin/curl -q --noproxy '*' --proto '=https' --connect-timeout 10 --max-time 20 \
        --silent --output /dev/null --write-out 'http=%{http_code} tls_verify=%{ssl_verify_result} peer_date=%header{date}' \
        "https://$host/" 2>/dev/null)
    code=$?
    # Extract just known fields and the standard HTTP Date. Never echo raw headers.
    http=${result#http=}; http=${http%% *}
    tls=${result#*tls_verify=}; tls=${tls%% *}
    peer_date=${result#*peer_date=}
    if [[ "$http" =~ ^[0-9]{3}$ && "$tls" =~ ^[0-9]+$ ]]; then
        printf 'curl_exit=%d http=%s tls_verify=%s\n' "$code" "$http" "$tls"
    else
        printf 'curl_exit=%d result=unavailable\n' "$code"
    fi
    if [[ "$peer_date" =~ ^[A-Za-z]{3},\ [0-9]{2}\ [A-Za-z]{3}\ [0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ GMT$ ]]; then
        peer_seconds=$(/bin/date -j -u -f '%a, %d %b %Y %T GMT' "$peer_date" '+%s' 2>/dev/null) || peer_seconds=''
        if [[ "$peer_seconds" =~ ^[0-9]+$ ]]; then
            printf 'guest_minus_https_date_seconds=%d\n' "$(( $(/bin/date +%s) - peer_seconds ))"
        fi
    fi
done
for service in akd accountsd storeaccountd appstoreagent trustd securityd; do
    if /usr/bin/pgrep -x "$service" >/dev/null; then state=running; else state=not_running_or_on_demand; fi
    printf 'service=%s state=%s\n' "$service" "$state"
done
printf 'Transport success does not verify Apple Account or App Store login.\n'
