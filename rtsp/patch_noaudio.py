import sys
# Remove audio completely from ak_rtsp_stream.c (no audio track in the SDP)
p = sys.argv[1]
s = open(p, encoding='latin-1').read()

a = '    init_ai(&rtsp_param.audio);\n    init_aenc(&rtsp_param.audio);\n'
assert s.count(a) == 1, ("init audio", s.count(a))
s = s.replace(a, '    audio_enable = 0; /* audio disabled */\n', 1)

b = ('    ak_thread_create(&(get_tid), audio_get_stream, (void*)chn, ANYKA_THREAD_MIN_STACK_SIZE, 19);\n'
     '    ak_thread_create(&(encode_tid), audio_get_frame_encode, NULL, ANYKA_THREAD_MIN_STACK_SIZE, 19);\n')
assert s.count(b) == 1, ("threads audio", s.count(b))
s = s.replace(b, '    (void)chn;\n', 1)

c = '    ak_thread_join(get_tid);\n    ak_thread_join(encode_tid);\n'
assert s.count(c) == 1, ("join audio", s.count(c))
s = s.replace(c, '', 1)

open(p, 'w', encoding='latin-1').write(s)
print("patch noaudio OK")
