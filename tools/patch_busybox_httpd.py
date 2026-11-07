import sys
# BusyBox 1.36.1 httpd: treat /onvif/* as CGI (needed by onvif_simple_server), as documented upstream.
p = sys.argv[1]
s = open(p).read()
anchor = '''	if (is_prefixed_with(tptr, "cgi-bin/")) {
		if (tptr[8] == '\\0') {
			/* protect listing "cgi-bin/" */
			send_headers_and_exit(HTTP_FORBIDDEN);
		}
		cgi_type = CGI_NORMAL;
	}
'''
add = '''	else if (is_prefixed_with(tptr, "onvif/")) {
		if (tptr[6] == '\\0') {
			/* protect listing "onvif/" */
			send_headers_and_exit(HTTP_FORBIDDEN);
		}
		cgi_type = CGI_NORMAL;
	}
'''
assert s.count(anchor) == 1, ("anchor", s.count(anchor))
s = s.replace(anchor, anchor + add, 1)
open(p, 'w').write(s)
print("patch busybox httpd OK")
