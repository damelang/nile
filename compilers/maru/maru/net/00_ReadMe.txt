This is a minimal implementation of IP, ICMP and TCP/IP.

link.k implements the physical link layer by reading packets that arrive on a
network tunnel pseudo-device.

test-link.k tests the link layer by dumping every packet that arrives on the
pseudo device as raw hexadecimal bytes.

ip.k implements the IP layer, filtering and forwarding traffic received from the
link layer according to destination address and internet protocol number.

test-ip.k tests the IP layer by decoding and printing the IP header of every
packet that arrives from the link layer.

icmp.k implements the Internet Control Message Protocol, filtering and
forwarding traffic received from the IP layer according the the type and code of
each message.

test-icmp.k implements a server that anwswers ICMP ECHO requests by sending an
ICMP ECHOREPLY packet back to the requestor, via the IP and link layers.

tcp.k implements enough of the Transmission Control Protocol to support simple
connection-oriented servers.  It filters and forwards TCP segments received from
the IP layer according to the TCP destination port number.

test-tcp.k implements the traditional "daytime" service as a service above the
TCP layer.

test.k implements all of the above services plus a simple HTTP daemon that
answers a valid web page that includes a simple greeting and the current time.

structure-diagram.k extends the Maru reader to understand the "ASCII art"
diagrams that appear in the various IETF RFCs to describe network packet header
structures.  It is used in ip.k, icmp.k and tcp.k to describe the structure of
the packet/segment headers that are dealt with at each of those layers.

icmp.osdefs, link.osdefs and tcp.osdefs are small scripts written in a
domain-specific language (called "licit") that elicits non-illicit definitions
of operating system 'magic constants' (whenever they are available) from the
header files present on the local system.  This avoids having to hard-code these
constants into the source code.  The files icmp.osdefs.k, link.osdefs.k and
tcp.osdefs.k are generated from these licit scripts, according to the grammar in
the file '../osdefs.g'.

The *.png files are screen captures of the above tests running.

NOTE: Because of the significant differences between operating systems regarding
      the creation, configuration and operation of network pseudo devices, the
      link layer will only work in its current form on a Linux kernel (version
      2.6.36 or newer).  The other layers are platform independent, and will
      work fine on a Windows or Mac system, as long as a properly-configured
      pseudo device and compatible implementation of the link layer are
      provided.  This is left as an exercise for the reader.
