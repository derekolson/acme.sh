#!/usr/bin/env sh

#
#NETLIFY_Token="sdfsdfsdfljlbjkljlkjsdfoiwje"
#https://app.netlify.com/user/applications
#

NETLIFY_Api="https://api.netlify.com/api/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_netlify_add() {
  fulldomain=$1
  txtvalue=$2

  NETLIFY_Token="${NETLIFY_Token:-$(_readaccountconf_mutable NETLIFY_Token)}"
  NETLIFY_Account_ID="${NETLIFY_Account_ID:-$(_readaccountconf_mutable NETLIFY_Account_ID)}"
  NETLIFY_Zone_ID="${NETLIFY_Zone_ID:-$(_readaccountconf_mutable NETLIFY_Zone_ID)}"

  if [ "$NETLIFY_Token" ]; then
    _saveaccountconf_mutable NETLIFY_Token "$NETLIFY_Token"
    _saveaccountconf_mutable NETLIFY_Account_ID "$NETLIFY_Account_ID"
    _saveaccountconf_mutable NETLIFY_Zone_ID "$NETLIFY_Zone_ID"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _netlify_rest GET "dns_zones/${_domain_id}/dns_records"

  # if ! echo "$response" | tr -d " " | grep \"hostname\":\"$fulldomain\" >/dev/null; then
  #   _err "Error"
  #   return 1
  # fi

  _info "Adding record"
  if _netlify_rest POST "dns_zones/$_domain_id/dns_records" "{\"type\":\"TXT\",\"hostname\":\"$fulldomain\",\"value\":\"$txtvalue\",\"ttl\":120}"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "The record already exists"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_netlify_rm() {
  fulldomain=$1
  txtvalue=$2

  NETLIFY_Token="${NETLIFY_Token:-$(_readaccountconf_mutable NETLIFY_Token)}"
  NETLIFY_Account_ID="${NETLIFY_Account_ID:-$(_readaccountconf_mutable NETLIFY_Account_ID)}"
  NETLIFY_Zone_ID="${NETLIFY_Zone_ID:-$(_readaccountconf_mutable NETLIFY_Zone_ID)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _netlify_rest GET "dns_zones/${_domain_id}/dns_records"

  if ! echo "$response" | tr -d " " | grep "\"hostname\":\"$fulldomain\"" >/dev/null; then
    _err "Error: $response"
    return 1
  fi

  record_id=$(printf "%s" "$response" | _egrep_o "\"hostname\":\"$fulldomain\",.*\"id\":[^,]*" | cut -d : -f 10 | tr -d \" | tr -d " ")
  _debug "record_id" "$record_id"
  if [ -z "$record_id" ]; then
    _err "Can not get record id to remove."
    return 1
  fi
  if ! _netlify_rest DELETE "dns_zones/$_domain_id/dns_records/$record_id"; then
    _err "Delete record error."
    return 1
  fi
  echo "$response"
  # echo "$response" | tr -d " " | grep \"success\":true >/dev/null

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  p=1

  # Use Zone ID directly if provided
  if [ "$NETLIFY_Zone_ID" ]; then
    if ! _netlify_rest GET "dns_zones/$NETLIFY_Zone_ID"; then
      return 1
    else
      if echo "$response" | tr -d " " | grep \"success\":true >/dev/null; then
        _domain=$(echo "$response" | _egrep_o "\"name\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
        if [ "$_domain" ]; then
          _cutlength=$((${#domain} - ${#_domain} - 1))
          _sub_domain=$(printf "%s" "$domain" | cut -c "1-$_cutlength")
          _domain_id=$NETLIFY_Zone_ID
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    fi
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if [ "$NETLIFY_Account_ID" ]; then
      if ! _netlify_rest GET "dns_zones?account_slug=$NETLIFY_Account_ID"; then
        return 1
      fi
    else
      if ! _netlify_rest GET "dns_zones?name=$h"; then
        return 1
      fi
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(echo "$response" | _egrep_o "\[.\"id\": *\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_netlify_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  token_trimmed=$(echo "$NETLIFY_Token" | tr -d '"')

  export _H1="Content-Type: application/json"
  if [ "$token_trimmed" ]; then
    export _H2="Authorization: Bearer $token_trimmed"
  fi

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$NETLIFY_Api/$ep" "" "$m")"
  else
    response="$(_get "$NETLIFY_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
