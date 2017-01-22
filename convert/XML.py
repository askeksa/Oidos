#!/usr/bin/env python

import xml.dom
import xml.dom.minidom

class XML(object):
    def __init__(self, domlist):
        self.domlist = list(domlist)

    def __getattr__(self, name):
        l = []
        for d in self.domlist:
            for c in d.childNodes:
                if c.nodeName == name:
                    l.append(c)
        return XML(l)

    def __len__(self):
        return len(self.domlist)

    def __getitem__(self, i):
        if i >= len(self.domlist):
            return XML([])
        return XML([self.domlist[i]])

    def __iter__(self):
        for d in self.domlist:
            yield XML([d])

    def __call__(self, attrname):
        s = ""
        for d in self.domlist:
            if d.nodeType == xml.dom.Node.ELEMENT_NODE and d.hasAttribute(attrname):
                s += d.getAttribute(attrname)
        return s

    def __str__(self):
        def collect(dl):
            s = ""
            for d in dl:
                if d.nodeType == xml.dom.Node.TEXT_NODE:
                    s += d.data
                else:
                    s += collect(d.childNodes)
            return s
        return collect(self.domlist)

    def __int__(self):
        return int(str(self))

    def __float__(self):
        return float(str(self))

    def __nonzero__(self):
        return len(self.domlist) != 0

    def replaceText(self, fun):
        def collect(dl):
            for d in dl:
                if d.nodeType == xml.dom.Node.TEXT_NODE:
                    d.data = fun(d.data)
                else:
                    collect(d.childNodes)
        collect(self.domlist)

    def setData(self, data):
        sdata = str(data)
        for d in self.domlist:
            for c in d.childNodes:
                c.data = sdata

    def removeChild(self, child):
        if len(self.domlist) != len(child.domlist):
            raise ValueError
        for p,c in zip(self.domlist, child.domlist):
            p.removeChild(c)

    def insertBefore(self, newChild, refChild):
        if len(self.domlist) != len(newChild.domlist) or len(newChild.domlist) != len(refChild.domlist):
            raise ValueError
        for p,nc,rc in zip(self.domlist, newChild.domlist, refChild.domlist):
            p.insertBefore(nc.childNodes[0],rc)

    def export(self):
        return "".join(x.toxml("utf-8") for x in self.domlist)

def readXML(filename):
    return XML([xml.dom.minidom.parse(filename)])

def makeXML(xstring):
    return XML([xml.dom.minidom.parseString(xstring)])
