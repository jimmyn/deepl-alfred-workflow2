#!/bin/bash

# setup #######################################################################
#set -o errexit -o pipefail -o noclobber -o nounset
LANGUAGE="${DEEPL_TARGET:-EN}"
LANGUAGE_SOURCE="${DEEPL_SOURCE:-auto}"
LANGUAGE_PREFERRED="${DEEPL_PREFERRED:-[\"DE\",\"EN\"]}"
KEY="${DEEPL_KEY:-}"
PRO="${DEEPL_PRO:-}"
POSTFIX="${DEEPL_POSTFIX:-.}"
VERSION="2.0.1"
PATH="$PATH:/usr/local/bin/"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
###############################################################################

# helper functions ############################################################
function printJson() {
  echo '{"items": [{"uid": null,"arg": "'"$1"'","valid": "yes","autocomplete": "autocomplete","title": "'"$1"'"}]}'
}
###############################################################################

# parameters ##################################################################
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"
  case "$key" in
  -l | --lang)
    LANGUAGE="$2"
    shift # past argument
    shift # past value
    ;;
  *) # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift              # past argument
    ;;
  esac
done
set -- "${POSITIONAL[@]:-}" # restore positional parameters
###############################################################################

# help ########################################################################
if [ -z "$1" ]; then
  echo "Home made DeepL CLI (${VERSION}; https://github.com/AlexanderWillner/deepl-alfred-workflow2)"
  echo ""
  echo "SYNTAX : $0 [-l language] <query>" >&2
  echo "Example: $0 -l DE \"This is just an example.\""
  echo ""
  exit 1
fi
###############################################################################

# process query ###############################################################
query="$1"
# shellcheck disable=SC2001
query="$(echo "$query" | sed 's/\"/\\\"/g')"
# shellcheck disable=SC2001
query="$(echo "$query" | sed "s/'/\\\'/g")"
query="$(echo "$query" | iconv -f utf-8-mac -t utf-8 | xargs)"

if [[ $KEY = "" ]] && [[ $query != *"$POSTFIX"   ]]; then
  printJson "End query with $POSTFIX"
  exit 1
fi
###############################################################################

# prepare query ###############################################################
# shellcheck disable=SC2001
query="$(echo "$query" | sed "s/\\$POSTFIX$//")"
data='{"jsonrpc":"2.0","method": "LMT_handle_jobs","params":{"jobs":[{"kind":"default","raw_en_sentence":"'"$query"'","preferred_num_beams":4,"raw_en_context_before":[],"raw_en_context_after":[],"quality":"fast"}],"lang":{"user_preferred_langs":'"${LANGUAGE_PREFERRED}"',"source_lang_user_selected":"'"${LANGUAGE_SOURCE}"'","target_lang":"'"${LANGUAGE:-EN}"'"},"priority":-1,"timestamp":1557063997314},"id":79120002}'
HEADER=(
  --compressed
  -H 'authority: www2.deepl.com'
  -H 'Origin: https://www.deepl.com'
  -H 'Referer: https://www.deepl.com/translator'
  -H 'Accept: */*'
  -H 'Content-Type: application/json'
  -H 'Accept-Language: en-us'
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Safari/605.1.15'
)
###############################################################################

# query #######################################################################
if [ -n "$KEY" ]; then
  if [ "$PRO" = "1" ]; then
    url="https://api.deepl.com/v2/translate"
  else
    url="https://api-free.deepl.com/v2/translate"
  fi
  echo >&2 "curl -s -X POST '$url' -H 'Authorization: DeepL-Auth-Key $KEY' -d 'text=$query' -d 'target_lang=${LANGUAGE:-EN}'"
  result=$(curl -s -X POST "$url" -H "Authorization: DeepL-Auth-Key $KEY" -d "text=$query" -d "target_lang=${LANGUAGE:-EN}")
  echo >&2 "$result"
  osascript -l JavaScript -e 'function run(argv) {
    const translations = JSON.parse(argv[0])["translations"].map(item => ({
      title: item["text"],
      arg: item["text"]
    }))

    return JSON.stringify({ items: translations }, null, 2)
  }' "$result" || echo >&2 "ERROR w/ key: result '$result', query '$query'"
else
  echo >&2 "curl -s 'https://www2.deepl.com/jsonrpc' '${HEADER[@]}' --data-binary $'$data'"
  result=$(curl -s 'https://www2.deepl.com/jsonrpc' \
    "${HEADER[@]}" \
    --data-binary $"$data")
  echo >&2 "$result"
  if [[ $result == *'"error":{"code":'* ]]; then
    message="$(osascript -l JavaScript -e 'function run(argv) { return JSON.parse(argv[0])["error"]["message"] }')"
    printJson "Error: $message"
  else
    osascript -l JavaScript -e 'function run(argv) {
      const translations = JSON.parse(argv[0])["result"]["translations"][0]["beams"].map(item => ({
        title: item["postprocessed_sentence"],
        arg: item["postprocessed_sentence"]
      }))

      return JSON.stringify({ items: translations }, null, 2)
    }' "$result" || echo >&2 "ERROR w/o key: result '$result', query '$query'"
  fi
fi
###############################################################################
