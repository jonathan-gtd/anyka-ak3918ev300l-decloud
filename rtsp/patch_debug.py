import sys
# 1) ak_rtsp_stream.c: trace the frames pushed into the ring buffer
p = sys.argv[1]
s = open(p, encoding='latin-1').read()
a = '                count++;\n'
assert s.count(a) == 1, ("count++", s.count(a))
s = s.replace(a, a + '                if (count <= 20 || stream->frame_type == 1) printf("PUSH dev%d chn%d n=%d len=%u ftype=%d ts=%llu\\n", dev_id, chn, count, stream->len, (int)stream->frame_type, (unsigned long long)stream->ts);\n', 1)
open(p, 'w', encoding='latin-1').write(s)
print("patch dbg stream OK")

# 2) ak_rtsp_server_sample.c: trace the frames read back by the RTSP server
q = sys.argv[2]
t = open(q, encoding='latin-1').read()
b = '        return aa_ls_get_frame(iDev, iChn, iVideoHandle, pVideo);\n'
assert t.count(b) == 1, ("get_frame", t.count(b))
t = t.replace(b,
    '        static int _dbg = 0;\n'
    '        int _r = aa_ls_get_frame(iDev, iChn, iVideoHandle, pVideo);\n'
    '        if (_dbg < 60 || (_dbg % 100) == 0) printf("GETV h=%d dev=%d chn=%d vh=%d r=%d len=%u ftype=%d ct=%d\\n", iHandle, iDev, iChn, iVideoHandle, _r, pVideo->uiDataLen, pVideo->iFrameType, pVideo->iCodeType);\n'
    '        _dbg++;\n'
    '        return _r;\n', 1)
open(q, 'w', encoding='latin-1').write(t)
print("patch dbg sample OK")
