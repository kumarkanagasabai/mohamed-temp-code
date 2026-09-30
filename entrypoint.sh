#!/bin/bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Stop script on NZEC
#set -e

# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
#set -o pipefail

# Use in the the functions: eval $invocation
invocation='say_verbose "Calling: ${yellow:-}${FUNCNAME[0]} ${green:-}$*${white:-}"'

# standard output may be used as a return value in the functions
# we need a way to write text on the screen in the functions so that
# it won't interfere with the return value.
# Exposing stream 3 as a pipe to standard output of the script itself
exec 3>&1

verbose=true
args=("$@")
root_path="/application"
app_data_path="$root_path/app_data"
configuration_path="$app_data_path/configuration"
product_json_path="$configuration_path/product.json"
config_xml_path="$configuration_path/config.xml"
id_path="$root_path/idp"
bi_path="$root_path/bi"
counter=0
is_success=false
etl_path="$root_path/etl/etlservice"
ai_path="$root_path/ai/aiservice"
mcp_path="$root_path/ai/mcpservice"
oci_region="${BOLD_SERVICES_OCI_REGION:-}"
oci_bucket="${BOLD_SERVICES_OCI_BUCKET_NAME:-}"
aws_region="${BOLD_SERVICES_AWS_REGION:-}"
aws_bucket="${BOLD_SERVICES_AMAZON_BUCKET_NAME:-}"
azure_container="${BOLD_SERVICES_AZUREBLOB_CONTAINER_NAME:-}"
azure_account="${BOLD_SERVICES_AZUREBLOB_ACCOUNT_NAME:-}"
has_oci=false
has_aws=false
has_azure=false
local_service_json_file="$configuration_path/local_service_url.json"
console_logs_enabled=${BOLD_SERVICES_CONSOLE_LOG_ENABLED:-false}
Is_Common_IDP=${Is_Common_IDP:-false}
# Setup some colors to use. These need to work in fairly limited shells, like the Ubuntu Docker container where there are only 8 colors.
# See if stdout is a terminal
if [ -t 1 ] && command -v tput > /dev/null; then
    # see if it supports colors
    ncolors=$(tput colors)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        bold="$(tput bold       || echo)"
        normal="$(tput sgr0     || echo)"
        black="$(tput setaf 0   || echo)"
        red="$(tput setaf 1     || echo)"
        green="$(tput setaf 2   || echo)"
        yellow="$(tput setaf 3  || echo)"
        blue="$(tput setaf 4    || echo)"
        magenta="$(tput setaf 5 || echo)"
        cyan="$(tput setaf 6    || echo)"
        white="$(tput setaf 7   || echo)"
    fi
fi

say_warning() {
    printf "%b\n" "${yellow:-}configure_boldbi: Warning: $1${white:-}" >&3
}

say_err() {
    printf "%b\n" "${red:-}configure_boldbi: Error: $1${white:-}" >&2
}

say_success() {
    printf "%b\n" "${cyan:-}configure_boldbi: ${green:-}$1${white:-}" >&2
}

say_bold() {
    printf "%b\n" "${cyan:-}configure_boldbi: ${bold:-}$1${white:-}" >&2
}

say() {
    # using stream 3 (defined in the beginning) to not interfere with stdout of functions
    # which may be used as return value
        printf "%b\n" "${cyan:-}configure_boldbi: ${white:-}$1" >&3
}

say_verbose() {
    if [ "$verbose" = true ]; then
        say "$1"
    fi
}

# args:
# input - $1
to_lowercase() {
    #eval $invocation

    echo "$1" | tr '[:upper:]' '[:lower:]'
    return 0
}

# args:
# input - $1
remove_trailing_slash() {
    #eval $invocation

    local input="${1:-}"
    echo "${input%/}"
    return 0
}

# args:
# input - $1
remove_beginning_slash() {
    #eval $invocation

    local input="${1:-}"
    echo "${input#/}"
    return 0
}

run_service() {
  local service_path="$1"
  local command="$2"
  local log_file="$3"
  local service_name="${log_file%.txt}"

  cd "$service_path" || exit 1

  if [ "$console_logs_enabled" = true ]; then
    stdbuf -oL -eL sh -c "$command" 2>&1 | sed "s/^/[service=${service_name}] /" &
  else
    stdbuf -oL -eL sh -c "$command" > "$app_data_path/logs/syslogs/$log_file" 2>&1 &
  fi
}

start_boldbi_services() {
        eval $invocation
 
       syslogs="$app_data_path/logs/syslogs"
        if [ ! -d "$syslogs" ]; then
          mkdir -p "$syslogs"
        fi
       
        # IDP Web
        run_service "$id_path/web" "dotnet Syncfusion.Server.IdentityProvider.Core.dll --urls=http://localhost:6500" "id_web.txt"
        say "Starting IDP Web application [Identity Provider Web for Bold Enterprise Products.]"
       
        skip_config_if_storage_set
 
        # IDP API
        run_service "$id_path/api" "dotnet Syncfusion.Server.IdentityProvider.API.Core.dll --urls=http://localhost:6501" "id_api.txt"
        say "Starting IDP API application [Identity Provider REST API for Bold Enterprise Products.]"
 
        # UMS
        run_service "$id_path/ums" "dotnet Syncfusion.TenantManagement.Core.dll --urls=http://localhost:6502" "id_ums.txt"
        say "Starting UMS application [Tenant and User Management for Bold Enterprise Products.]"
 
        # BI Web
        run_service "$bi_path/web" "dotnet Syncfusion.Server.Dashboards.dll --urls=http://localhost:6504" "bi_web.txt"
        say "Starting BI Web application [Dashboard Server for Bold BI.]"
 
        # BI API
        run_service "$bi_path/api" "dotnet Syncfusion.Server.API.dll --urls=http://localhost:6505" "bi_api.txt"
        say "Starting BI API application [BI API Service for Bold BI.]"
 
        # BI Jobs
        run_service "$bi_path/jobs" "dotnet Syncfusion.Server.Jobs.dll --urls=http://localhost:6506" "bi_jobs.txt"
        say "Starting BI Jobs application [BI Jobs Service for Bold BI.]"
 
       # if ping -q -c 1 -W 1 "8.8.8.8" >/dev/null; then
       # cd "$root_path"
       # install_chrome_package
       # else
        cd "$root_path"
       # move_chrome_package
       # fi
            move_chromium_to_destination
 
        # BI Designer
        cd "$bi_path/dataservice/"
        move_map_shape_files
        run_service "$bi_path/dataservice" "dotnet Syncfusion.Dashboard.Designer.Web.Service.dll --urls=http://localhost:6507" "bi_designer.txt"
        say "Starting BI Designer application [Dashboard Designer Service for Bold BI.]"
 
        # ETL
        run_service "$etl_path" "dotnet BoldDataHub.dll --urls=http://localhost:6509" "etl.txt"
        say "Starting ETL application [ETL Service for Bold BI.]"
 
        # AI
        run_service "$ai_path" "dotnet BoldBi.Ai.Service.dll --urls=http://localhost:6510" "ai.txt"
        say "Starting AI application [AI Service for Bold BI.]"

        # MCP
        run_service "$mcp_path" "dotnet boldbi-mcp-server.dll --urls=http://localhost:6511" "mcp.txt"
        say "Starting MCP application [MCP Service for Bold BI.]"
}

skip_config_if_storage_set() {
  if [ -n "$oci_region" ] || [ -n "$oci_bucket" ]; then
    has_oci=true
  fi
  if [ -n "$aws_region" ] || [ -n "$aws_bucket" ]; then
    has_aws=true
  fi
  if [ -n "$azure_container" ] || [ -n "$azure_account" ]; then
    has_azure=true
  fi
  if [ "$has_oci" = true ] || [ "$has_aws" = true ] || [ "$has_azure" = true ]; then
    if [ "$has_oci" = true ] && [ "$has_aws" = true ] && [ "$has_azure" = true ]; then
      say "OCI,AWS and Azure storage values detected. Waiting 180 seconds for the config file to be created..."
    elif [ "$has_oci" = true ]; then
      say "OCI storage values detected. Waiting 180 seconds for the config file to be created..."
    elif [ "$has_azure" = true ]; then
      say "Azure storage values detected. Waiting 180 seconds for the config file to be created..."
    elif [ "$has_aws" = true ]; then
      say "AWS storage values detected. Waiting 180 seconds for the config file to be created..."
    fi
    while true; do
        status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:6500/health-check)
        if [ "$status" -eq 200 ]; then
            say "IDP Web application is healthy [Identity Provider Web for Bold Enterprise Products.]"
            sleep 10
            break
        fi
        say "IDP Web is not healthy yet. Retrying in 10 seconds..."
        sleep 10
    done
  else
    check_config_file_generated
  fi
}

check_config_file_generated() {
        eval $invocation

        ## code to check whether the config.xml file is generated or not
        say "Initializing configuration files..."

        while :
        do
                if [ -f "$config_xml_path" ]; then
                        break
                fi
        done

        say_success "Config files generated successfully."
        ##
}
upgrade_log() {
    if [ -f $product_json_path ]; then

        exclude_folders=("logs" "upgradelogs")

        [ ! -d "$app_data_path/upgradelogs" ] && mkdir -p "$app_data_path/upgradelogs"

        json_file="$product_json_path"

        # Read the JSON file into a variable
        json_data=$(cat "$json_file")

        # Search for the version key and extract the version value
        version=$(echo "$json_data" | grep -o '"Version": "[^"]*' | sed 's/"Version": "//')

        if [ -d "$app_data_path/upgradelogs/$version" ]; then
    rm -r "$app_data_path/upgradelogs/$version"
    fi
        mkdir -p "$app_data_path/upgradelogs/$version"

        find "$app_data_path" -type d \( -name "${exclude_folders[0]}" -o -name "${exclude_folders[1]}" \) -prune -o -print > "$app_data_path/upgradelogs/$version/upgrade_logs.txt"
    fi
}
new_services_url_update() {
    IDP_URL=$(grep '"Idp":' "$product_json_path" | sed -E 's/.*"Idp": "(.*?)".*/\1/')
    if grep -q '"AiService": null' "$product_json_path"; then
        # Replace AiService null with the updated value
        sed -i -E "s#(\"AiService\": )null#\1\"$IDP_URL/aiservice\"#" "$product_json_path"
        say_success "AiService URL updated successfully in product.json"
    fi
    # Check and add Mcp
    if ! grep -q '"Mcp"' "$product_json_path"; then
        sed -i "/\"BiDesigner\".*/a\\    \"Mcp\": \"$IDP_URL/mcp\"," "$product_json_path"
        say_success "MCP node updated in product.json with URL"
    fi

    if ! grep -q '/aiservice",' "$product_json_path"; then
        sed -i 's|/aiservice"|/aiservice",|' "$product_json_path"
    fi

    if [ $Is_Common_IDP == "true" ]; then
        # Check and add ReportsAi
        if ! grep -q '"ReportsAi"' "$product_json_path"; then
            sed -i "/\"AiService\".*/a\\    \"ReportsAi\": \"$IDP_URL/reportsai\"," "$product_json_path"
            say_success "ReportsAi node updated in product.json with URL"
        fi
        # Check and add ReportsMcp
        if ! grep -q '"ReportsMcp"' "$product_json_path"; then
            sed -i "/\"ReportsAi\".*/a\\    \"ReportsMcp\": \"$IDP_URL/reportsmcp\"," "$product_json_path"
            say_success "ReportsMCP node updated in product.json with URL"
        fi
    else
        # Check and add ReportsAi
        if ! grep -q '"ReportsAi"' "$product_json_path"; then
            sed -i '/"AiService".*/a\    "ReportsAi": "http://localhost:5000/reportsai",' "$product_json_path"
            say_success "ReportsAi node updated in product.json without URL"
        fi
        # Check and add ReportsMcp
        if ! grep -q '"ReportsMcp"' "$product_json_path"; then
            sed -i '/"ReportsAi".*/a\    "ReportsMcp": "http://localhost:5000/reportsmcp",' "$product_json_path"
            say_success "ReportsMCP node updated in product.json without URL"
        fi
    fi
}

update_url_in_product_json() {
        eval $invocation

        say "Checking whether product.json exists in app_data folder."
        if [ ! -f $product_json_path ]; then

                if [ -z $APP_URL ]; then
                        mkdir -p $configuration_path && cp -rf product.json $product_json_path
                else
                        export IDPURL=$APP_URL
                        jq --arg IDPURL "$IDPURL" '.InternalAppUrl.Idp=$IDPURL' product.json > out1.json  

                        export BIURL=$APP_URL"/bi"
                        jq --arg BIURL "$BIURL" '.InternalAppUrl.Bi=$BIURL' out1.json > out2.json

                        export DESIGNERURL=$APP_URL"/bi/designer"
                        jq --arg DESIGNERURL "$DESIGNERURL" '.InternalAppUrl.BiDesigner=$DESIGNERURL' out2.json > out3.json

                        export AIURL=$APP_URL"/aiservice"
                        jq --arg AIURL "$AIURL" '.InternalAppUrl.AiService=$AIURL' out3.json > out4.json

                        export MCPURL=$APP_URL"/mcp"
                        jq --arg MCPURL "$MCPURL" '.InternalAppUrl.Mcp=$MCPURL' out4.json > out5.json

                        mkdir -p $configuration_path && cp -rf out5.json $product_json_path
                        rm out1.json out2.json out3.json out4.json out5.json
                fi
                say_success "Updated product.json with APP_URL and moved to app_data folder."
        else
                dotnet "$root_path/utilities/installutils/installutils.dll" upgrade_version docker
                new_services_url_update
        fi
}

check_local_service_url_file(){
	urls=$(grep -oP '"[^"]+":\s*"\K[^"]+' "$local_service_json_file")
	has_localhost=false
	has_port=false
	local_service_url_file_env=""

	while IFS= read -r url; do
		[[ -z "$url" ]] && continue
		host=$(echo "$url" | awk -F[/:] '{print $4}')
		port=$(echo "$url" | grep -oP ':[0-9]+' | head -1)
		if [[ "$host" == "localhost" ]]; then
			has_localhost=true
		fi
		if [[ -n "$port" ]]; then
			has_port=true
		fi
	done <<< "$urls"

	if $has_localhost; then
		local_service_url_file_env="docker"
	elif $has_port; then
		local_service_url_file_env="k8s"
	else
		local_service_url_file_env="multi-docker or other"
	fi
}

update_local_service_url() {

	json_content='{
	  "Idp": "http://localhost:6500",
	  "IdpApi": "http://localhost:6501/api",
	  "Ums": "http://localhost:6502/ums",
	  "Bi": "http://localhost:6504/bi",
	  "BiApi": "http://localhost:6505/bi/api",
	  "BiJob": "http://localhost:6506/bi/jobs",
	  "BiDesigner": "http://localhost:6507/bi/designer",
	  "BiDesignerHelper": "http://localhost:6507/bi/designer/helper",
	  "Etl": "http://localhost:6509",
	  "EtlBlazor": "http://localhost:6509/framework/blazor.server.js",
	  "Ai": "http://localhost:6510/aiservice",
      "Mcp": "http://localhost:6511/mcp",
	  "Reports": "http://localhost:6504/reporting",
      "ReportsApi": "http://localhost:6505/reporting/api",
      "ReportsJob": "http://localhost:6506/reporting/jobs",
      "ReportsViewer": "http://localhost:6507/reporting/viewer",
      "ReportsService": "http://localhost:6508/reporting/reportservice",
      "ReportsAi": "http://localhost:6510/reportsai",
      "ReportsMcp": "http://localhost:6511/reportsmcp"
	}'

	# Check if the JSON file exists
	if [ ! -f "$local_service_json_file" ]; then
		mkdir -p "$configuration_path"
		echo "$json_content" > "$local_service_json_file"
		say "Local service Json file Created and URL updated"
    else
		check_local_service_url_file
		if [ "$local_service_url_file_env" != "docker" ]; then
			say "Local service JSON file is $local_service_url_file_env environment file, so recreating it"
			rm -f "$local_service_json_file"
			echo "$json_content" > "$local_service_json_file"
			say "Local service JSON file created and URLs updated"
		fi
	fi
}

update_nginx_configuration() {

nginx_conf="/etc/nginx/sites-available/boldbi-nginx-config"

new_location_block=$(cat <<EOL
        location /etlservice/ {
        root               /application/etl/etlservice/wwwroot;
        proxy_pass         http://localhost:6509/;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
        location /etlservice/_framework/blazor.server.js {
        root               /application/etl/etlservice/wwwroot;
        proxy_pass         http://localhost:6509/_framework/blazor.server.js;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
   }
}
EOL
)

if ! grep -Eq "location .*/etlservice/.*" "$nginx_conf"; then
    # Append the new location block to the end of the file
    sed -i '${/}/d;}' $nginx_conf
    echo "$new_location_block" >> "$nginx_conf"
    say "ETL location block added in Nginx file"
fi
}
update_ai_nginx_configuration() {

nginx_conf="/etc/nginx/sites-available/boldbi-nginx-config"

new_location_block=$(cat <<EOL
        location /aiservice {
        proxy_pass http://localhost:6510/aiservice;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOL
)

if ! grep -Eq "location .*/aiservice.*" "$nginx_conf"; then
    # Append the new location block to the end of the file
    sed -i '${/}/d;}' $nginx_conf
    echo "$new_location_block" >> "$nginx_conf"
    say "AI location block added in Nginx file"
fi
}

update_mcp_nginx_configuration() {

nginx_conf="/etc/nginx/sites-available/boldbi-nginx-config"

new_location_block=$(cat <<EOL
        location /mcp {
        proxy_pass http://localhost:6511;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOL
)

if ! grep -Eq "location .*/mcp.*" "$nginx_conf"; then
    # Append the new location block to the end of the file
    sed -i '${/}/d;}' $nginx_conf
    echo "$new_location_block" >> "$nginx_conf"
    say "MCP location block added in Nginx file"
fi
}

reset_proxy_pass_to_default() {
    eval $invocation

    nginx_conf="/etc/nginx/sites-available/boldbi-nginx-config"

    sed -i -E '
        /:6509/! {
            s|(proxy_pass[ \t]+http://localhost:[0-9]+).*|\1;|g
            s|(proxy_pass[ \t]+http://localhost:[0-9]+)/[ \t]*;|\1;|g
        }
    ' "$nginx_conf"

    local_service_json_file="$configuration_path/local_service_url.json"

    json_content='{
    	  "Idp": "http://localhost:6500",
    	  "IdpApi": "http://localhost:6501/api",
    	  "Ums": "http://localhost:6502/ums",
    	  "Bi": "http://localhost:6504/bi",
    	  "BiApi": "http://localhost:6505/bi/api",
    	  "BiJob": "http://localhost:6506/bi/jobs",
    	  "BiDesigner": "http://localhost:6507/bi/designer",
    	  "BiDesignerHelper": "http://localhost:6507/bi/designer/helper",
    	  "Etl": "http://localhost:6509",
    	  "EtlBlazor": "http://localhost:6509/framework/blazor.server.js",
    	  "Ai": "http://localhost:6510/aiservice",
          "Mcp": "http://localhost:6511/mcp",
    	  "Reports": "http://localhost:6504/reporting",
          "ReportsApi": "http://localhost:6505/reporting/api",
          "ReportsJob": "http://localhost:6506/reporting/jobs",
          "ReportsViewer": "http://localhost:6507/reporting/viewer",
          "ReportsService": "http://localhost:6508/reporting/reportservice",
          "ReportsAi": "http://localhost:6510/reportsai",
          "ReportsMcp": "http://localhost:6511/reportsmcp"
    	}'

    echo "$json_content" > "$local_service_json_file"

    return 0
}

configure_nginx () {
        eval $invocation

        say "Configuring Nginx web server."
        cd $root_path


        # Standard reverse proxy configuration
        if [ "$BOLD_SERVICES_REVERSE_PROXY" = "True" ] || [ "$BOLD_SERVICES_REVERSE_PROXY" = "true" ]; then
                sed -i 's/proxy_set_header   X-Forwarded-Proto $scheme;/proxy_set_header   X-Forwarded-Proto $http_x_forwarded_proto;/g' boldbi-nginx-config
        fi

        # CloudFront configuration
        if [ "$BOLD_SERVICES_CLOUD_FRONT" = "True" ] || [ "$BOLD_SERVICES_CLOUD_FRONT" = "true" ]; then
                sed -i \
                -e 's/\$http_x_forwarded_proto/\$http_cloudfront_forwarded_proto/g' \
                -e 's/\$scheme/\$http_cloudfront_forwarded_proto/g' \
                boldbi-nginx-config

                say "CloudFront mode enabled. Using CloudFront-Forwarded-Proto."
        fi

        if [ "$OS_ENV" != "alpine" ]; then
                nginx_sites_available_dir="/etc/nginx/sites-available"
                nginx_sites_enabled_dir="/etc/nginx/sites-enabled"

                if [ ! -f $nginx_sites_available_dir/boldbi-nginx-config ]; then
                        [ ! -d "$nginx_sites_available_dir" ] && mkdir -p "$nginx_sites_available_dir"
                        [ ! -d "$nginx_sites_enabled_dir" ] && mkdir -p "$nginx_sites_enabled_dir"

                        cp boldbi-nginx-config $nginx_sites_available_dir/boldbi-nginx-config
                fi
                                update_nginx_configuration
                                update_ai_nginx_configuration
                                update_mcp_nginx_configuration
                                reset_proxy_pass_to_default
                [ ! -f "$nginx_sites_enabled_dir/boldbi-nginx-config" ] && ln -sf $nginx_sites_available_dir/boldbi-nginx-config $nginx_sites_enabled_dir/default
        else
                echo "include /etc/nginx/sites-available/boldbi-nginx-config;" > /etc/nginx/http.d/default.conf

                nginx_sites_available_dir="/etc/nginx/sites-available"

                if [ ! -f $nginx_sites_available_dir/boldbi-nginx-config ]; then
                        [ ! -d "$nginx_sites_available_dir" ] && mkdir -p "$nginx_sites_available_dir"
                        cp boldbi-nginx-config $nginx_sites_available_dir/boldbi-nginx-config
                fi
        fi
        nginx -c /etc/nginx/nginx.conf
        say "Starting Nginx web server."
}


install_client_libraries() {
        eval $invocation
        # Eliminate special characters and spaces.
        OPTIONAL_LIBS=$(echo "$OPTIONAL_LIBS" | tr -dc '[:alpha:],')
        # Eliminate any extra commas if there are any available.
        OPTIONAL_LIBS=$(echo "$OPTIONAL_LIBS" | sed 's/,\+/,/g')
    bash $root_path/clientlibrary/install-optional.libs.sh $OPTIONAL_LIBS
}

move_map_shape_files() {
        if [ -f "$root_path/utilities/customwidgetupgrader/CustomWidgetUpgrader.dll" ]; then
            dotnet "$root_path/utilities/customwidgetupgrader/CustomWidgetUpgrader.dll" true &>/dev/null
        fi
}

# move_chrome_package(){

#         puppeteer_location="$bi_path/dataservice/puppeteer"

#         if [ -d "$puppeteer_location/Chrome" ]; then
#                 chmod +x "$puppeteer_location"/Chrome/
#                 [ -f "$bi_path/dataservice/phantomjs" ] && rm -rf "$bi_path/dataservice/phantomjs"
#                 say "Permission provided to puppeteer"
#         fi
# }
move_chromium_to_destination() {
    chromium_path="/usr/bin/chromium"
    chrome_destination="$bi_path/dataservice/puppeteer/Chrome"

    if [ -f "$chromium_path" ]; then
        [ -f "$chrome_destination/chrome" ] && rm -f "$chrome_destination/chrome"
        cp "$chromium_path" "$chrome_destination/chrome"
        chmod +x "$chrome_destination"
        say "Chromium package moved and renamed to 'chrome' successfully"
    fi
}

final_configuration() {
        eval $invocation

        ## code to check whether all services were running or not
        APP_URL=($(cat $product_json_path | jq '.InternalAppUrl.Idp'))
        APP_URL=$(eval echo $APP_URL)
        if [[ "$APP_URL" =~ ^http://localhost(:[0-9]+)? ]]; then
        APP_URL="http://localhost"
        fi
        domain="$(remove_trailing_slash "$APP_URL")"
       # domain=$(basename "$APP_URL")
        health_check_endpoint="$domain/api/status"
        keyword1='"is_running":true'
        keyword2='"is_running":false'

        say "Completing final configuration. Please wait..."

        while sleep 5; do
                counter=$((counter+1))

                if curl -s "$health_check_endpoint" | grep -q "$keyword1"
                then
                        say "This may take some time..."
                        while :
                        do
                                if ! curl -s "$health_check_endpoint" | grep -q "$keyword2"
                                then
                                        is_success=true
                                        break
                                fi
                        done
                        break
                elif [[ "$counter" -eq 18 ]]; then
                    say "This is taking more time than usual. Please wait..."
                elif [[ "$counter" -gt 36 ]]; then
                        say "Please check whether your domain in APP_URL is correct. Unable to configure boldbi with $domain"
                        break
                fi
        done

    if $is_success; then
            say_success "Bold BI configuration completed successfully."
            say_success "Bold BI is ready to use now.You can access Bold BI application in your browser at http://localhost:port-number or http://host-ip:port-number."
        fi
}

final_notes() {
        if [ ! -n "$BOLD_SERVICES_UNLOCK_KEY" ]; then
          eval $invocation
          say "Configure the Bold BI On-Premise application startup to use the application."
          say "Please refer the following link for more details"
          say "https://help.boldbi.com/embedded-bi/application-startup"
          say "Please refer here for Bold BI Embedded documentation => https://help.boldbi.com/embedded-bi/"
        fi

}

scan_services() {

    service_message_shown_id_web=false
    service_message_shown_id_api=false
    service_message_shown_id_ums=false
    service_message_shown_bi_web=false
    service_message_shown_bi_api=false
    service_message_shown_bi_jobs=false
    service_message_shown_bi_dataservice=false
    service_message_shown_etl=false
    service_message_shown_ai=false
    while sleep 60; do
        ps aux | grep Syncfusion.Server.IdentityProvider.Core.dll | grep -q -v grep
        PROCESS_1_STATUS=$?

        ps aux | grep Syncfusion.Server.IdentityProvider.API.Core.dll | grep -q -v grep
        PROCESS_2_STATUS=$?

        ps aux | grep Syncfusion.TenantManagement.Core.dll | grep -q -v grep
        PROCESS_3_STATUS=$?

        ps aux | grep Syncfusion.Server.Dashboards.dll | grep -q -v grep
        PROCESS_4_STATUS=$?

        ps aux | grep Syncfusion.Server.API.dll | grep -q -v grep
        PROCESS_5_STATUS=$?

        ps aux | grep Syncfusion.Server.Jobs.dll | grep -q -v grep
        PROCESS_6_STATUS=$?

        ps aux | grep Syncfusion.Dashboard.Designer.Web.Service.dll | grep -q -v grep
        PROCESS_7_STATUS=$?

        ps aux | grep BoldDataHub.dll | grep -q -v grep
        PROCESS_8_STATUS=$?

        ps aux | grep BoldBi.Ai.Service.dll | grep -q -v grep
        PROCESS_9_STATUS=$?

        if [ $PROCESS_1_STATUS -ne 0 -o $PROCESS_2_STATUS -ne 0 -o $PROCESS_3_STATUS -ne 0 -o $PROCESS_4_STATUS -ne 0 -o $PROCESS_5_STATUS -ne 0 -o $PROCESS_6_STATUS -ne 0 -o $PROCESS_7_STATUS -ne 0 -o $PROCESS_8_STATUS -ne 0 -o $PROCESS_9_STATUS -ne 0 ]; then

            # Restart the services one by one if they are down
            if [ $PROCESS_1_STATUS -ne 0 ]; then
                if ! $service_message_shown_id_web; then
                    say "The IDP Web service is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\" location."
                    service_message_shown_id_web=true
                fi

            fi

            if [ $PROCESS_2_STATUS -ne 0 ]; then
                if ! $service_message_shown_id_api; then
                    say "The IDP API service is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\" location."
                    service_message_shown_id_api=true
                fi

            fi

            if [ $PROCESS_3_STATUS -ne 0 ]; then
                if ! $service_message_shown_id_ums; then
                    say "The IDP UMS service is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\" location."
                    service_message_shown_id_ums=true
                fi

            fi

            if [ $PROCESS_4_STATUS -ne 0 ]; then
                if ! $service_message_shown_bi_web; then
                    say "The BI Web service is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\" location."
                    service_message_shown_bi_web=true
                fi
            fi

            if [ $PROCESS_5_STATUS -ne 0 ]; then
                if ! $service_message_shown_bi_api; then
                    say "The BI API service is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\" location."
                    service_message_shown_bi_api=true
                fi

            fi

            if [ $PROCESS_6_STATUS -ne 0 ]; then
                if ! $service_message_shown_bi_jobs; then
                    say "The BI Jobs service is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\" location."
                    service_message_shown_bi_jobs=true
                fi
            fi

            if [ $PROCESS_7_STATUS -ne 0 ]; then
                if ! $service_message_shown_bi_dataservice; then
                    say "The BI Designer service is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\" location."
                    service_message_shown_bi_dataservice=true
                fi

           fi
            if [ $PROCESS_8_STATUS -ne 0 ]; then
                if ! $service_message_shown_etl; then
                    say "The BI Designer ETL is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\" location."
                  service_message_shown_bi_etl=true
                fi

           fi
            if [ $PROCESS_9_STATUS -ne 0 ]; then
                if ! $service_message_shown_ai; then
                    say "The AI service is down. You can find the reason for the service being down from the service logs available at the \"$syslogs\> location."
                  service_message_shown_ai=true
                fi

           fi
        else
            # Reset the error_shown and service_message_shown flags

                        service_message_shown_id_web=false
                        service_message_shown_id_api=false
                        service_message_shown_id_ums=false
                        service_message_shown_bi_web=false
                        service_message_shown_bi_api=false
                        service_message_shown_bi_jobs=false
                        service_message_shown_bi_dataservice=false
                        service_message_shown_etl=false
                        service_message_shown_ai=false
        fi
    done
}

check_and_start_postgres() {
    if command -v psql >/dev/null 2>&1; then
        say "PostgreSQL is installed on this Bold BI Docker Image."
        chown -R postgres:postgres /var/lib/postgresql
        service postgresql start
        service postgresql status
    fi
}

configure_boldbi() {
        eval $invocation

        upgrade_log
        update_url_in_product_json
        update_local_service_url
        start_boldbi_services
        configure_nginx
        install_client_libraries
        final_configuration
        if $is_success; then final_notes; fi
        scan_services
}

check_and_start_postgres
configure_boldbi
