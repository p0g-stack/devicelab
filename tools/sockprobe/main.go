// sockprobe: listen on abstract Unix sockets and log who connects, as JSON
// lines: the peer's uid/pid/SELinux context (SO_PEERCRED, SO_PEERSEC) and the
// first bytes it sends. Stand-in for a root process that an app (the
// app-plane APK) must connect back to. Static Go binary.
//
//	sockprobe [-t seconds] [-reply text] name...   (names without the leading @)
package main

import (
	"encoding/json"
	"flag"
	"net"
	"os"
	"strings"
	"syscall"
	"time"
)

func peersec(fd int) string {
	b := make([]byte, 256)
	l := uint32(len(b))
	_, _, e := syscall.Syscall6(syscall.SYS_GETSOCKOPT, uintptr(fd), syscall.SOL_SOCKET, 31 /* SO_PEERSEC */, uintptrOf(b), uintptrOfLen(&l), 0)
	if e != 0 {
		return "err: " + e.Error()
	}
	return strings.TrimRight(string(b[:l]), "\x00")
}

func main() {
	secs := flag.Int("t", 300, "exit after this many seconds")
	reply := flag.String("reply", "", "text written to each connection after reading")
	flag.Parse()
	enc := json.NewEncoder(os.Stdout)
	self, _ := os.ReadFile("/proc/self/attr/current")
	enc.Encode(map[string]any{"event": "start", "uid": os.Getuid(), "context": strings.TrimRight(string(self), "\x00"), "names": flag.Args()})
	for _, name := range flag.Args() {
		ln, err := net.Listen("unix", "@"+name)
		if err != nil {
			enc.Encode(map[string]any{"event": "listen-error", "name": name, "error": err.Error()})
			continue
		}
		go func(name string, ln net.Listener) {
			for {
				c, err := ln.Accept()
				if err != nil {
					return
				}
				go func(c net.Conn) {
					defer c.Close()
					ev := map[string]any{"event": "connect", "name": name, "t": time.Now().UnixMilli()}
					if raw, err := c.(*net.UnixConn).SyscallConn(); err == nil {
						raw.Control(func(fd uintptr) {
							if cr, err := syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED); err == nil {
								ev["peerUid"], ev["peerPid"] = cr.Uid, cr.Pid
							}
							ev["peerContext"] = peersec(int(fd))
						})
					}
					if *reply != "" {
						c.Write([]byte(*reply))
					}
					c.SetReadDeadline(time.Now().Add(10 * time.Second))
					buf := make([]byte, 4096)
					n, _ := c.Read(buf)
					ev["data"] = string(buf[:n])
					enc.Encode(ev)
				}(c)
			}
		}(name, ln)
	}
	time.Sleep(time.Duration(*secs) * time.Second)
	enc.Encode(map[string]any{"event": "exit"})
}
