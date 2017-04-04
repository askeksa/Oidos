#!/usr/bin/env python

import sys
import zipfile
import XML
import re
import math
import base64
import struct

def newname(s):
	return re.sub("MetaSynth", "Oidos", s)

def upgradeInstrument(xi, name):
	xip.PluginIdentifier.replaceText(newname)
	xip.PluginDisplayName.replaceText(newname)
	xip.PluginShortDisplayName.replaceText(newname)
	if name is not None:
		xi.Name.setData(name)
	else:
		xi.Name.replaceText(newname)

	#pdata = base64.b64decode(xip.ParameterChunk.domlist[0].childNodes[0].data + "=")
	#for i,c in enumerate(pdata):
	#	print "%s%02X" % (" " if (i % 4) == 0 else "", ord(c)),
	#print

	xparams = xip.Parameters.Parameter.Value
	params = [float(p) for p in xparams]

	# Duplicate filter sweep parameter
	params = params[:11] + [params[13]] + params[11:17]

	for i,p in enumerate(params):
		xparams[i].setData(p)

	pstring = struct.pack("<4I", 1,1,18,0) + struct.pack("<18f", *params)
	xip.ParameterChunk.setData(base64.b64encode(pstring))


infile = sys.argv[1]
outfile = sys.argv[2]

zfile = zipfile.ZipFile(infile)
if infile.endswith(".xrns"):
	info = zfile.getinfo("Song.xml")
	x = XML.makeXML(zfile.read(info))
	xinstrs = x.RenoiseSong.Instruments.Instrument
	name = None
elif infile.endswith(".xrni"):
	info = zfile.getinfo("Instrument.xml")
	x = XML.makeXML(zfile.read(info))
	xinstrs = x.RenoiseInstrument
	name = infile[:-5]
else:
	print "Unknown file extension: " + infile
	sys.exit()

for xi in xinstrs:
	for xip in xi.PluginProperties.PluginDevice:
		plugin_id = str(xip.PluginIdentifier)
		if plugin_id == "MetaSynth":
			upgradeInstrument(xi, name)
			break


outzip = zipfile.ZipFile(outfile, 'w')
outzip.writestr(info, x.export())
outzip.close()
