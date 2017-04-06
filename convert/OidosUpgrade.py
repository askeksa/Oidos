#!/usr/bin/env python

import sys
import zipfile
import XML
import re
import math
import base64
import struct


def upgradeInstrument(xi, xdevice, name):
	def newname(s):
		return re.sub("MetaSynth", "Oidos", s)

	xdevice.PluginIdentifier.replaceText(newname)
	xdevice.PluginDisplayName.replaceText(newname)
	xdevice.PluginShortDisplayName.replaceText(newname)
	if name is not None:
		xi.Name.setData(name)
	else:
		xi.Name.replaceText(newname)

	#pdata = base64.b64decode(xdevice.ParameterChunk.domlist[0].childNodes[0].data + "=")
	#for i,c in enumerate(pdata):
	#	print "%s%02X" % (" " if (i % 4) == 0 else "", ord(c)),
	#print

	xparams = xdevice.Parameters.Parameter.Value
	params = [float(p) for p in xparams]

	# Duplicate filter sweep parameter
	params = params[:11] + [params[13]] + params[11:17] + [0.0] + params[20:27] + [params[29]] + params[27:33]

	for i,p in enumerate(params):
		xparams[i].setData(p)

	pstring = struct.pack("<4I", 1, 1, len(params), 0) + struct.pack("<%df" % len(params), *params)
	xdevice.ParameterChunk.setData(base64.b64encode(pstring))

def upgradeInstruments(xinstrs, name):
	for xi in xinstrs:
		for xdevice in xi.PluginProperties.PluginDevice:
			plugin_id = str(xdevice.PluginIdentifier)
			if plugin_id == "MetaSynth":
				upgradeInstrument(xi, xdevice, name)
				break


def upgradeReverb(xdevice):
	def newname(s):
		return re.sub("MetaEffect", "OidosReverb", s)

	xdevice.PluginIdentifier.replaceText(newname)
	xdevice.PluginDisplayName.replaceText(newname)
	xdevice.PluginShortDisplayName.replaceText(newname)

	#pdata = base64.b64decode(xdevice.ParameterChunk.domlist[0].childNodes[0].data + "=")
	#for i,c in enumerate(pdata):
	#	print "%s%02X" % (" " if (i % 4) == 0 else "", ord(c)),
	#print

	xparams = xdevice.Parameters.Parameter.Value
	params = [float(p) for p in xparams]

	# Reduce parameters
	params = params[:20]

	while len(xdevice.Parameters.Parameter) > 20:
		xdevice.Parameters.removeChild(xdevice.Parameters.Parameter[20])

	pstring = struct.pack("<4I", 1, 1, len(params), 0) + struct.pack("<%df" % len(params), *params)
	xdevice.ParameterChunk.setData(base64.b64encode(pstring))

def upgradeReverbs(xtrack):
	for xdevice in xtrack.FilterDevices.Devices.AudioPluginDevice:
		plugin_id = str(xdevice.PluginIdentifier)
		if plugin_id == "MetaEffect":
			upgradeReverb(xdevice)


infile = sys.argv[1]
outfile = sys.argv[2]

zfile = zipfile.ZipFile(infile)
if infile.endswith(".xrns"):
	info = zfile.getinfo("Song.xml")
	x = XML.makeXML(zfile.read(info))
	upgradeInstruments(x.RenoiseSong.Instruments.Instrument, None)
	upgradeReverbs(x.RenoiseSong.Tracks.SequencerTrack)
	upgradeReverbs(x.RenoiseSong.Tracks.SequencerSendTrack)
elif infile.endswith(".xrni"):
	info = zfile.getinfo("Instrument.xml")
	x = XML.makeXML(zfile.read(info))
	upgradeInstruments(x.RenoiseInstrument, infile[infile.rfind('/')+1:-5])
else:
	print "Unknown file extension: " + infile
	sys.exit()



outzip = zipfile.ZipFile(outfile, 'w')
outzip.writestr(info, x.export())
outzip.close()
