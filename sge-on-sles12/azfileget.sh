#!/bin/bash

# Utility wrapper script to pull files from azure file storage account
# Used for application installer

# NOTE:  No error handling or parameter checking.   No harm is done with bad parameters.

# echo "usage: ${0##*/} <storage-account-name> <container-name> <access-key> <file>"

# Pull command line arguments"
storage_account="$1"
container_name="$2"
access_key="$3"
file="$4"

# Base URL
file_store_url="file.core.windows.net"

# Auth type
authorization="SharedKey"

# Misc Request information
request_method="GET"
request_date=$(TZ=GMT date "+%a, %d %h %Y %H:%M:%S %Z")
storage_service_version="2015-04-05"

# HTTP Request headers
x_ms_date_h="x-ms-date:$request_date"
x_ms_version_h="x-ms-version:$storage_service_version"

# Build the signature string
canonicalized_headers="${x_ms_date_h}\n${x_ms_version_h}"
canonicalized_resource="/${storage_account}/${container_name}/${file}"

# Build REST API string to sign for authentication
string_to_sign="${request_method}\n\n\n\n\n\n\n\n\n\n\n\n${canonicalized_headers}\n${canonicalized_resource}"

# Decode the Base64 encoded access key, convert to Hex.
decoded_hex_key="$(echo -n $access_key | base64 -d -w0 | xxd -p -c256)"

# Create the HMAC signature for the Authorization header
signature=$(printf "$string_to_sign" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$decoded_hex_key" -binary | base64 -w0)

# Final header to send
authorization_header="Authorization: $authorization $storage_account:$signature"

# Send request - Transfer status gets written to stdout
curl -H "$x_ms_date_h" -H "$x_ms_version_h" -H "$authorization_header" \
        "https://${storage_account}.${file_store_url}/${container_name}/${file}" \
	-o ${file}
