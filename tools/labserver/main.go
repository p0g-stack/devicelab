// labserver: a stand-in root process for WebUI checks. Static Go binary, so
// it runs on Android without bionic or glibc questions.
//
//	GET /ws          WebSocket echo; first frame is {"peerUid":N,...}
//	GET /slow?ms=N   answers after N ms (in-flight fetch under paused timers)
//	GET /ping        {"peerUid":N}
//
// peerUid is read from /proc/net/tcp{,6} by the client's port, which is the
// check the root channel would use to reject other apps.
package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

func peerUID(remote string) (int, string) {
	_, portStr, _ := net.SplitHostPort(remote)
	port, _ := strconv.Atoi(portStr)
	want := fmt.Sprintf(":%04X", port)
	for _, f := range []string{"/proc/net/tcp", "/proc/net/tcp6"} {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(b), "\n")[1:] {
			fs := strings.Fields(line)
			if len(fs) > 7 && strings.HasSuffix(fs[1], want) {
				uid, _ := strconv.Atoi(fs[7])
				return uid, f
			}
		}
	}
	return -1, "not found"
}

func info(r *http.Request) map[string]any {
	uid, src := peerUID(r.RemoteAddr)
	return map[string]any{"peerUid": uid, "uidSource": src, "remote": r.RemoteAddr,
		"origin": r.Header.Get("Origin"), "serverUid": os.Getuid(), "t": time.Now().UnixMilli()}
}

func cors(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Private-Network", "true")
}

func main() {
	addr := flag.String("addr", "127.0.0.1:8765", "listen address")
	flag.Parse()
	logf := log.New(os.Stderr, "labserver ", log.Lmicroseconds)
	http.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		cors(w)
		logf.Printf("ping %v", info(r))
		json.NewEncoder(w).Encode(info(r))
	})
	http.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) {
		cors(w)
		ms, _ := strconv.Atoi(r.URL.Query().Get("ms"))
		start := time.Now()
		time.Sleep(time.Duration(ms) * time.Millisecond)
		logf.Printf("slow %dms answered", ms)
		json.NewEncoder(w).Encode(map[string]any{"heldMs": time.Since(start).Milliseconds(), "sentAt": time.Now().UnixMilli()})
	})
	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		key := r.Header.Get("Sec-WebSocket-Key")
		if key == "" {
			http.Error(w, "not a websocket", 400)
			return
		}
		meta := info(r)
		logf.Printf("ws open %v", meta)
		h := sha1.Sum([]byte(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
		conn, rw, err := w.(http.Hijacker).Hijack()
		if err != nil {
			return
		}
		defer conn.Close()
		fmt.Fprintf(rw, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n",
			base64.StdEncoding.EncodeToString(h[:]))
		first, _ := json.Marshal(meta)
		writeFrame(rw.Writer, 1, first)
		rw.Flush()
		for {
			op, payload, err := readFrame(rw.Reader)
			if err != nil || op == 8 {
				logf.Printf("ws closed: %v", err)
				return
			}
			if op == 9 {
				op = 10
			}
			writeFrame(rw.Writer, op, payload)
			rw.Flush()
		}
	})
	logf.Printf("listening on %s as uid %d", *addr, os.Getuid())
	log.Fatal(http.ListenAndServe(*addr, nil))
}

func readFrame(r *bufio.Reader) (byte, []byte, error) {
	var h [2]byte
	if _, err := io.ReadFull(r, h[:]); err != nil {
		return 0, nil, err
	}
	op, n := h[0]&0x0f, uint64(h[1]&0x7f)
	switch n {
	case 126:
		var b [2]byte
		io.ReadFull(r, b[:])
		n = uint64(binary.BigEndian.Uint16(b[:]))
	case 127:
		var b [8]byte
		io.ReadFull(r, b[:])
		n = binary.BigEndian.Uint64(b[:])
	}
	var mask [4]byte
	if h[1]&0x80 != 0 {
		io.ReadFull(r, mask[:])
	}
	p := make([]byte, n)
	if _, err := io.ReadFull(r, p); err != nil {
		return 0, nil, err
	}
	for i := range p {
		p[i] ^= mask[i%4]
	}
	return op, p, nil
}

func writeFrame(w *bufio.Writer, op byte, p []byte) {
	w.WriteByte(0x80 | op)
	switch n := len(p); {
	case n < 126:
		w.WriteByte(byte(n))
	case n < 1<<16:
		w.WriteByte(126)
		binary.Write(w, binary.BigEndian, uint16(n))
	default:
		w.WriteByte(127)
		binary.Write(w, binary.BigEndian, uint64(n))
	}
	w.Write(p)
}
