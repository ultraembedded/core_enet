### Ethernet MAC 10/100 Mbps

Github:   [https://github.com/ultraembedded/core_enet](https://github.com/ultraembedded/core_enet)

This component is a very basic 10/100Mbps Ethernet MAC.  
This Ethernet NIC operates as a memory-mapped peripheral.  
It does not feature a DMA interface, hence is low performance / CPU intensive to use, but it is, however, very small and simple.  
The register interface happens to have a similar programming model to the Xilinx EmacLite core, hence can make use of the existing Linux Kernel driver (xilinx_emaclite.c).

##### Features
* Support for full-duplex 10/100Mbps Ethernet.
* Wishbone B4 pipelined interface.
* Programmable MAC address for receive filtering.
* 2 x Tx Ping Pong buffers (4KB total).
* 2 x Rx Ping Pong buffers (4KB total).
* MII Ethernet PHY interface (4-bit mode).
* Interrupt output (on Tx space / Rx ready).

##### Limitations
* Half-duplex mode not implemented (it does not currently implement CSMA/CD required for well-behaved half-duplex mode).
* MDIO requires GPIOs (use SW MDIO GPIO in the Linux Kernel).

##### Size
For a Xilinx 7 series device;
```
- Slice LUTs:      534
- Slice Registers: 543
- BlockRAM:        4
```

##### Testing
Verified under simulation then tested on FPGA using Linux 5.14.3 with ping, iperf, wget, tftp.

##### Configuration
* Top Module: enet.v
* parameter PROMISCUOUS        - If set to 0, use MAC address filtering (broadcast, or local addr).
* parameter DEFAULT_MAC_ADDR_L - Bytes 0 - 3 of the default MAC address
* parameter DEFAULT_MAC_ADDR_H - Bytes 4 - 5 of the default MAC address

##### DTS
The following Linux DTS entry should work for this core (change the base address and interrupt config as required);
```
   enet: ethernet@95000000 {
        compatible = "xlnx,xps-ethernetlite-3.00.a";
        device_type = "network";
        interrupts = <4>;
        local-mac-address = [00 00 BE AF FE AD];
        reg = <0x95000000 0x10000>;
        xlnx,duplex = <0x1>;
        xlnx,rx-ping-pong = <0x1>;
        xlnx,tx-ping-pong = <0x1>;
    };
```

##### References
* [MII Interface](https://en.wikipedia.org/wiki/Media-independent_interface)
* [LogiCORE IP AXI Ethernet Lite MAC v3.0)](https://www.xilinx.com/support/documentation/ip_documentation/axi_ethernetlite/v3_0/pg135-axi-ethernetlite.pdf)
