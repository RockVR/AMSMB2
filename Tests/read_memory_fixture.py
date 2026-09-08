import pathlib, socket, sys
from impacket import smbserver
from impacket.ntlm import compute_lmhash, compute_nthash
root=pathlib.Path(sys.argv[1])
(root/'data.bin').write_bytes(bytes(range(256))*16384)
server=smbserver.SimpleSMBServer(listenAddress='127.0.0.1',listenPort=0)
server.addShare('fixture',str(root),readOnly='yes')
server.setSMB2Support(True)
server.addCredential('probe',0,compute_lmhash('probe'),compute_nthash('probe'))
(root/'port').write_text(str(server.getServer().server_address[1]))
server.start()
