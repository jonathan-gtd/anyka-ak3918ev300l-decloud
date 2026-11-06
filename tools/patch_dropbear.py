import re, sys
# root's authorized_keys read from /conf/dropbear/authorized_keys (read-only rootfs, $HOME=/)
p = sys.argv[1]
s = open(p).read()

# 1) path of the file that is read
old = re.compile(r'filename = m_malloc\(len \+ 22\);\s*snprintf\(filename, len \+ 22, "[^"]*",\s*ses\.authstate\.pw_dir\);', re.S)
assert len(old.findall(s)) == 1, "bloc lecture"
s = old.sub('(void)len; filename = m_strdup(AUTHKEYS_FILE);', s, count=1)

# 2) permission check: directory + file in /conf/dropbear
start = s.index('static int checkpubkeyperms() {')
end = s.index('static int checkfileperm(char * filename) {')
body = '''static int checkpubkeyperms() {
	TRACE(("enter checkpubkeyperms (cam: %s)", AUTHKEYS_FILE))
	if (checkfileperm(AUTHKEYS_DIR) != DROPBEAR_SUCCESS) return DROPBEAR_FAILURE;
	if (checkfileperm(AUTHKEYS_FILE) != DROPBEAR_SUCCESS) return DROPBEAR_FAILURE;
	TRACE(("leave checkpubkeyperms"))
	return DROPBEAR_SUCCESS;
}

/* Checks that a file is owned by the user or root, and isn't writable by
 * group or other */
/* returns DROPBEAR_SUCCESS or DROPBEAR_FAILURE */
'''
s = s[:start] + body + s[end:]

s = s.replace('static int checkpubkeyperms(void);',
              '#define AUTHKEYS_DIR "/conf/dropbear"\n#define AUTHKEYS_FILE "/conf/dropbear/authorized_keys"\nstatic int checkpubkeyperms(void);', 1)
open(p, 'w').write(s)
print("patch dropbear OK")
