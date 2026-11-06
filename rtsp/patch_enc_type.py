import sys,re
p=sys.argv[1]; s=open(p).read()
a0='            vs->enc_out_type = 1;\n            vs->profile = PROFILE_JPEG;\n        }\n        '
x0=a0+'{ int _ov=aas_ini_get_int(ini,"video0","enc_type",-1); if(_ov>=0){vs->enc_out_type=_ov; printf("OVERRIDE0 enc=%d ",_ov);} }\n        '
a1='            vs1->enc_out_type = 1;\n            vs1->profile = PROFILE_JPEG;\n        }\n        '
x1=a1+'{ int _ov=aas_ini_get_int(ini,"video1","enc_type",-1); if(_ov>=0){vs1->enc_out_type=_ov; printf("OVERRIDE1 enc=%d ",_ov);} }\n        '
assert s.count(a0)==1 and s.count(a1)==1,(s.count(a0),s.count(a1))
s=s.replace(a0,x0,1).replace(a1,x1,1)
# drop the audio codec registration (AENC_* symbols are not in the camera libs)
s=re.sub(r'AENC_Open(Mp3|Aac|Amr)','0',s)
s=re.sub(r'AENC_(Mp3|Aac|Amr)_GetVersionInfo','0',s)
s=s.replace('ak_aenc_registerencoder(&stencode)','0')
open(p,'w').write(s); print("patch enc_type OK")
