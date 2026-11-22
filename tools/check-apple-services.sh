#!/bin/bash
# Run manually INSIDE the macOS guest. No sign-in, cookies, credentials, account
# databases, HTTP bodies or identity serials printed or saved. --account-errors
# reads recent local error events through a fixed domain/code-only filter.
set -u
export LC_ALL=C
account_errors=0
case "${1-}" in
    '') ;;
    --account-errors) account_errors=1 ;;
    *) printf 'Usage: bash check-apple-services.sh [--account-errors]\n' >&2; exit 2 ;;
esac
printf 'Henge guest transport check v2\n'
printf 'macOS='; /usr/bin/sw_vers -productVersion
build=$(/usr/bin/sw_vers -buildVersion)
printf 'macOS_build=%s\n' "$build"
case "$build" in
    22G120|24G90|25G83|26B123) printf 'account_kernel_profile=recognized\n' ;;
    *) printf 'account_kernel_profile=not_recognized\n' ;;
esac
# These are indicators of what the guest received, not an authentication result.
# Never print the serial, UUID, MLB, network identifiers or account names.
model=$(/usr/sbin/sysctl -n hw.model 2>/dev/null) || model=''
case "$model" in
    Macmini8,1) printf 'account_legacy_model=present\n' ;;
    VirtualMac2,1) printf 'account_legacy_model=absent\n' ;;
    *) printf 'account_legacy_model=unknown\n' ;;
esac
serial_state=$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | /usr/bin/awk '
    /"IOPlatformSerialNumber"[[:space:]]*=[[:space:]]*"/ {
        value=$0
        sub(/^.*"IOPlatformSerialNumber"[[:space:]]*=[[:space:]]*"/, "", value)
        sub(/".*$/, "", value)
        state=value == "1234" ? "yes" : (length(value) ? "no" : "unknown")
    }
    END { print (state ? state : "unknown") }
')
printf 'placeholder_serial=%s\n' "$serial_state"
if [ "$model" = VirtualMac2,1 ] && [ "$serial_state" = yes ]; then
    printf 'next_step=enable_account_compatibility_then_shut_down_and_cold_boot\n'
fi
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
if [ "$account_errors" = 1 ]; then
    # Recent error events only. Raw messages flow directly into a strict
    # allowlist parser and are never echoed or saved. An error pair can be
    # nested or unrelated; it is evidence to investigate, not a diagnosis.
    printf 'account_error_window=last_10_minutes\n'
    /usr/bin/log show --last 10m --style compact --predicate \
        '(process == "akd" OR process == "adid" OR process == "accountsd" OR process == "appleaccountd" OR process == "amsaccountsd" OR process == "storeaccountd" OR process == "appstoreagent" OR process == "storekitd" OR process == "commerce" OR process == "mobileactivationd" OR process == "identityservicesd") AND (messageType == 16 OR messageType == 17)' \
        2>/dev/null | /usr/bin/awk '
# BEGIN ACCOUNT ERROR FILTER
BEGIN {
    n=split("AKAuthenticationError AKAuthenticationErrorDomain AKAppleIDAuthenticationError AKAppleIDAuthenticationErrorDomain AMSErrorDomain AMSAccountErrorDomain ACErrorDomain AAErrorDomain AIDAErrorDomain NSURLErrorDomain NSOSStatusErrorDomain NSCocoaErrorDomain GrandSlamErrorDomain com.apple.MobileActivation.ErrorDomain IDSBAASignerErrorDomain", domains, " ")
}
{
    for (i=1; i<=n; i++) {
        domain=domains[i]
        at=index($0, domain)
        if (!at || (at>1 && substr($0, at-1, 1) ~ /[A-Za-z0-9_.]/)) continue
        tail=substr($0, at+length(domain))
        if (tail ~ /^[[:space:]]+[Cc]ode[[:space:]]*=[[:space:]]*-?[0-9]+/) {
            sub(/^[[:space:]]+[Cc]ode[[:space:]]*=[[:space:]]*/, "", tail)
        } else if (tail ~ /^:[[:space:]]*-?[0-9]+/) {
            sub(/^:[[:space:]]*/, "", tail)
        } else continue
        match(tail, /^-?[0-9]+/)
        code=substr(tail, RSTART, RLENGTH)
        following=substr(tail, RLENGTH+1, 1)
        if (length(code)>10 || following ~ /[A-Za-z0-9_.@-]/) continue
        counts[i SUBSEP code]++
    }
}
END {
    for (key in counts) {
        split(key, pair, SUBSEP)
        print "account_error=" domains[pair[1]] " code=" pair[2] " count=" counts[key]
        found=1
    }
    if (!found) print "account_error_pairs=none_detected"
}
# END ACCOUNT ERROR FILTER
    '
    log_exit=${PIPESTATUS[0]}
    printf 'account_error_log_exit=%d\n' "$log_exit"
    printf 'No detected error pairs does not establish successful sign-in.\n'
fi
printf 'Transport success does not verify Apple Account or App Store login.\n'
