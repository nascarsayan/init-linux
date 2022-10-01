curl_wsman() {
	host=$1
	[ -z $host ] && echo "usage: test_wsman <ip>" && return 1; 
	curl \
		--header "Content-Type: application/soap+xml;charset=UTF-8" \
		--header "WSMANIDENTIFY: unauthenticated" http://$host:5985/wsman \
		--data '&lt;s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsmid="http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd"&gt;&lt;s:Header/&gt;&lt;s:Body&gt;&lt;wsmid:Identify/&gt;&lt;/s:Body&gt;&lt;/s:Envelope&gt;'
}

nc_wsman() {
	host=$1
	[ -z $host ] && echo "usage: test_wsman <ip>" && return 1;
	nc -vz $host 5985;
}
