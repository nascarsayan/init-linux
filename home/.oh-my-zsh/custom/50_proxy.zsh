set_proxy() {
    local proxy_url=""
    local cert_file=""
    local isolated="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)
                proxy_url="$2"
                shift 2
                ;;
            --cert)
                cert_file="$2"
                shift 2
                ;;
            --isolated)
                isolated="true"
                shift
                ;;
            --help)
                show_proxy_usage
                return 0
                ;;
            *)
                echo "Invalid argument: $1"
                show_proxy_usage
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$proxy_url" ]]; then
        echo "Missing required argument: --url"
        show_proxy_usage
        return 1
    fi

    # Validate URL format
    if ! echo "$proxy_url" | grep -P -q '^(http|https)://'; then
        echo "Invalid URL format. Please provide a URL starting with 'http://' or 'https://'."
        show_proxy_usage
        return 1
    fi

    # Clear existing proxy environment variables
    unset HTTP_PROXY
    unset http_proxy
    unset HTTPS_PROXY
    unset https_proxy
    unset NO_PROXY
    unset no_proxy
    unset REQUESTS_CA_BUNDLE

    # Set proxy variables based on the provided URL
    if [[ -n "$cert_file" ]]; then
        if [[ ! -f "$cert_file" ]]; then
            echo "Certificate file not found: $cert_file"
            return 1
        fi
        export REQUESTS_CA_BUNDLE="$cert_file"
    fi

    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"

    # Set NO_PROXY based on isolated flag
    if [[ "$isolated" == "true" ]]; then
        export NO_PROXY=".svc,kubernetes.default.svc,192.168.0.0/16,localhost,127.0.0.0/8,10.96.0.0/12,10.244.0.0/16,10.224.0.0/16"
    else
        export NO_PROXY=".svc,kubernetes.default.svc,10.0.0.0/8,192.168.0.0/16,localhost,127.0.0.0/8"
    fi
    export no_proxy="$NO_PROXY"
}

show_proxy() {
    echo "Proxy environment variables set:"
    echo "HTTP_PROXY: $HTTP_PROXY"
    echo "http_proxy: $http_proxy"
    echo "HTTPS_PROXY: $HTTPS_PROXY"
    echo "https_proxy: $https_proxy"
    echo "NO_PROXY: $NO_PROXY"
    echo "no_proxy: $no_proxy"
    echo "REQUESTS_CA_BUNDLE: $REQUESTS_CA_BUNDLE"
}

show_proxy_usage() {
    echo "Usage: set_proxy [--url <proxy_url>] [--cert <cert_file>] [--isolated] [--help]"
    echo "  --url       : URL of the proxy server (including scheme, optional username:password, and optional port)"
    echo "                Examples: "
    echo "                  - http://proxy.example.com"
    echo "                  - http://username:password@proxy.example.com:3128"
    echo "  --cert      : Path to the certificate file for SSL proxies (optional)"
    echo "  --isolated  : Set NO_PROXY environment variable for isolated cluster (default: false)"
    echo "  --help      : Show usage information"
}
