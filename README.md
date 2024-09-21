# ZigOCD

A library for flashing and debugging microcontrollers..... that doesn't really do much yet.

This library implements a node-api system where each logical part of the stack is represented by a
node, and nodes can expose APIs. For example, there is currently a JLink node which exposes a SWD API.
Since JLink also supports JTAG it can also (in future) expose a JTAG API. Alternatively, JLink may be
substituted for different nodes representing other probes such as CMSIS-DAP which expose the same
APIs. This allows a large number of probes to work for a large number of devices. Even bespoke virtual
probes such as driving raspberry PI gpio lanes directly work as long as they expose the correct APIs.

Naturally, many APIs have a lot of redundant behaviour between implementations. To combat this apis
only actually expose a small number of APIs which need to be implemented for every node. Once these are implemented correctly, all functionality of the API is available. An implementer of SWD for
example does not need to know about any of the registers, it just has to build the packet, send it,
and return the result if applicable.
